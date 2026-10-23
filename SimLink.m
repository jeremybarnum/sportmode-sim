// SimLink: the link between the phone and the watch, switchable in the Simulators.
//
// Paired Simulators keep WatchConnectivity up while both apps run; there is no
// Bluetooth or Wi-Fi to turn off. Injected into both apps (DYLD_INSERT_LIBRARIES,
// beside ImpossiBLE), this library reads a control file shared by the two
// Simulators: "down" puts the phone out of the watch's reach, "slow N" delivers
// each live message N seconds late (a sluggish link, still reachable), anything
// else (or no file) leaves the link as it is. While the link is down:
//   - isReachable reads NO, and the delegate hears sessionReachabilityDidChange;
//   - sendMessage and sendMessageData fail at once with "not reachable";
//   - what arrives through the queued channels (user info, application context,
//     files) is held, and handed over in order when the link is back, as the
//     system delivers a queue that waited.
// The paired Simulators deliver a queued transfer (user info, complication
// info, a file) only when the receiving app launches, never while it runs.
// So this library carries those itself: the sender writes each one to a
// folder the receiver reads (in order, while the link is up), and the app
// sees the delegate call it would have had. A user info transfer not yet
// delivered shows in the sender's outstandingUserInfoTransfers and can be
// cancelled, as on a device. Application context, which the Simulators do
// deliver, stays with the system.
//
// "hold" keeps everything in flight between the two (live messages, and the queued
// channels' deliveries) until the control file says otherwise, then hands it over in
// order: a link reachable but stalled, as a dropped wrist, for as long as a test needs.
//
// "wedge" in the control file is the field's one-way wedge (#113 variant A): isReachable
// still reads YES, but each live message is lost, and its sender hears a timeout
// after $SIMLINK_LIVE_TIMEOUT seconds (default 15).
//
// With SIMLINK_LIVE=1 this library carries the live messages too (sendMessage,
// sendMessageData, and their replies), through folders like the queued channels',
// instead of the paired Simulators: on a small machine those can take minutes to
// deliver one while reachable reads YES. As on a device, a message the receiver
// does not take within the timeout (its app not running, not yet activated, or
// without the delegate method the message needs) fails to its sender, payloads
// must be property lists of at most 65,536 bytes, and a reply that does not come
// in 60 s times out. Reachability is SimLink's too, as on a device: the watch
// reads the phone reachable while the link is up (iOS would wake the phone app),
// the phone reads the watch reachable while the watch app runs (it touches a
// heartbeat file each second). Activation and application context stay with the
// system.
//
// Control file: $SIMLINK_FILE, default /tmp/sportmode-sim-link. Queues:
// $SIMLINK_QUEUE/to-phone and to-watch, default /tmp/sportmode-sim-queue; live
// messages $SIMLINK_QUEUE/live-to-phone and live-to-watch.

#import <Foundation/Foundation.h>
#import <WatchConnectivity/WatchConnectivity.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <fcntl.h>

static NSString *controlPath;
static NSString *outbox, *inbox, *filesDir;   // the queued channels' folders
static BOOL linkDown;
static double latency;                      // "slow N": seconds each incoming live message waits
static dispatch_queue_t slowQueue;          // where they wait, in arrival order
static dispatch_queue_t heldQueue;          // the held deliveries, in arrival order
static NSMutableArray<dispatch_block_t> *held;
static NSDictionary *deliveredContext;      // the last application context the app was given
static BOOL wedged;                         // "wedge": reachable, and every live message lost
static BOOL holding;                        // "hold": reachable, everything kept in flight
static NSMutableArray<dispatch_block_t> *onHold;   // the live messages kept, in order; on slowQueue
static BOOL liveCarried;                    // SIMLINK_LIVE=1: this library carries the live messages
static double liveTimeout;                  // seconds a live message waits to be taken

static BOOL readDown(void) {
    NSString *s = [[NSString stringWithContentsOfFile:controlPath encoding:NSUTF8StringEncoding error:nil]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    double slow = [s hasPrefix:@"slow "] ? [[s substringFromIndex:5] doubleValue] : 0;
    if (slow != latency) NSLog(@"SimLink: live messages %@", slow > 0 ? [NSString stringWithFormat:@"%.1f s late", slow] : @"on time");
    latency = slow;
    BOOL wedge = [s isEqualToString:@"wedge"];
    if (wedge != wedged) NSLog(@"SimLink: link %@", wedge ? @"WEDGED (reachable, live messages lost)" : @"no longer wedged");
    wedged = wedge;
    BOOL hold = [s isEqualToString:@"hold"];
    if (hold != holding) NSLog(@"SimLink: link %@", hold ? @"HOLDING (reachable, nothing delivered)" : @"released");
    holding = hold;
    return [s isEqualToString:@"down"];
}

// A live message, now or after the link's latency.
static void arrive(dispatch_block_t block) {
    if (holding) {
        dispatch_block_t kept = [block copy];
        dispatch_async(slowQueue, ^{ [onHold addObject:kept]; });
        return;
    }
    if (latency <= 0) { block(); return; }
    double wait = latency;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), slowQueue, ^{
        if (linkDown) { NSLog(@"SimLink: late live message dropped, link down"); return; }
        block();
    });
}

#pragma mark - A file held across the gap

@interface SLSessionFile : WCSessionFile
@property (nonatomic, strong) NSURL *heldURL;
@property (nonatomic, copy) NSDictionary<NSString *, id> *heldMetadata;
@end

@implementation SLSessionFile
- (NSURL *)fileURL { return self.heldURL; }
- (NSDictionary<NSString *, id> *)metadata { return self.heldMetadata; }
@end

#pragma mark - A transfer waiting in the queue

// What transferUserInfo returns: outstanding until the receiver takes its file, and cancelled by
// removing the file before then.
@interface SLUserInfoTransfer : WCSessionUserInfoTransfer
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary<NSString *, id> *heldUserInfo;
@property (nonatomic) BOOL complication;
@end

static NSMutableArray<SLUserInfoTransfer *> *outstanding;

@implementation SLUserInfoTransfer
- (NSDictionary<NSString *, id> *)userInfo { return self.heldUserInfo; }
- (BOOL)isCurrentComplicationInfo { return self.complication; }
// Waiting for the receiver, not moving: what a device reports for a transfer not yet started.
- (BOOL)isTransferring { return NO; }
- (void)cancel {
    [NSFileManager.defaultManager removeItemAtPath:self.path error:nil];
    @synchronized (outstanding) { [outstanding removeObject:self]; }
}
@end

#pragma mark - The delegate, seen through the link

// WatchConnectivity asks the delegate's class what it implements, so the receiving methods are
// hooked on that class, not wrapped in a proxy: each hook checks the link, then calls the app's own.
static IMP appMessage, appMessageReply, appData, appDataReply, appUserInfo, appContext, appFile;

// Runs now, or later in order if the link is down or held (or earlier deliveries still wait).
static void deliver(dispatch_block_t block) {
    __block BOOL now = NO;
    dispatch_sync(heldQueue, ^{
        if (!linkDown && !holding && held.count == 0) {
            now = YES;
        } else {
            [held addObject:[block copy]];
        }
    });
    if (now) block();
}

static void sl_message(id self, SEL _cmd, WCSession *session, NSDictionary *message) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    arrive(^{ ((void (*)(id, SEL, id, id))appMessage)(self, _cmd, session, message); });
}

// A reply handler can be a block on the caller's stack: copied before it waits out the latency,
// or the late delivery copies a block whose frame is gone.
static void sl_messageReply(id self, SEL _cmd, WCSession *session, NSDictionary *message, id reply) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    id replyBlock = [reply copy];
    arrive(^{ ((void (*)(id, SEL, id, id, id))appMessageReply)(self, _cmd, session, message, replyBlock); });
}

static void sl_data(id self, SEL _cmd, WCSession *session, NSData *data) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    arrive(^{ ((void (*)(id, SEL, id, id))appData)(self, _cmd, session, data); });
}

static void sl_dataReply(id self, SEL _cmd, WCSession *session, NSData *data, id reply) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    id replyBlock = [reply copy];
    arrive(^{ ((void (*)(id, SEL, id, id, id))appDataReply)(self, _cmd, session, data, replyBlock); });
}

static void sl_userInfo(id self, SEL _cmd, WCSession *session, NSDictionary *userInfo) {
    if (linkDown) NSLog(@"SimLink: user info held until the link is back");
    deliver(^{ ((void (*)(id, SEL, id, id))appUserInfo)(self, _cmd, session, userInfo); });
}

static void sl_context(id self, SEL _cmd, WCSession *session, NSDictionary *context) {
    if (linkDown) NSLog(@"SimLink: application context held until the link is back");
    deliver(^{
        deliveredContext = context;
        ((void (*)(id, SEL, id, id))appContext)(self, _cmd, session, context);
    });
}

static void sl_file(id self, SEL _cmd, WCSession *session, WCSessionFile *file) {
    if (!linkDown && !holding) {
        __block BOOL now = NO;
        dispatch_sync(heldQueue, ^{ now = held.count == 0; });
        if (now) { ((void (*)(id, SEL, id, id))appFile)(self, _cmd, session, file); return; }
    }
    // The system deletes the file when this returns: keep a copy for later.
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SimLink"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *copy = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, file.fileURL.lastPathComponent]]];
    [NSFileManager.defaultManager copyItemAtURL:file.fileURL toURL:copy error:nil];
    SLSessionFile *f = ((id (*)(id, SEL))objc_msgSend)([SLSessionFile alloc], @selector(init));
    f.heldURL = copy;
    f.heldMetadata = file.metadata;
    NSLog(@"SimLink: file %@ held until the link is back", file.fileURL.lastPathComponent);
    deliver(^{
        ((void (*)(id, SEL, id, id))appFile)(self, _cmd, session, f);
        [NSFileManager.defaultManager removeItemAtURL:copy error:nil];
    });
}

// Hooks one receiving method on the delegate's class, if the class has it; the app's own is kept.
static void hook(Class cls, SEL sel, IMP replacement, IMP *app) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || *app) return;
    // Added on the class itself when inherited, so only this class changes.
    class_addMethod(cls, sel, method_getImplementation(m), method_getTypeEncoding(m));
    *app = method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
}

static void hookDelegate(id delegate) {
    Class cls = object_getClass(delegate);
    hook(cls, @selector(session:didReceiveMessage:), (IMP)sl_message, &appMessage);
    hook(cls, @selector(session:didReceiveMessage:replyHandler:), (IMP)sl_messageReply, &appMessageReply);
    hook(cls, @selector(session:didReceiveMessageData:), (IMP)sl_data, &appData);
    hook(cls, @selector(session:didReceiveMessageData:replyHandler:), (IMP)sl_dataReply, &appDataReply);
    hook(cls, @selector(session:didReceiveUserInfo:), (IMP)sl_userInfo, &appUserInfo);
    hook(cls, @selector(session:didReceiveApplicationContext:), (IMP)sl_context, &appContext);
    hook(cls, @selector(session:didReceiveFile:), (IMP)sl_file, &appFile);
    NSLog(@"SimLink: hooked the session delegate %@", NSStringFromClass(cls));
}

#pragma mark - WCSession

static IMP origIsReachable, origSendMessage, origSendMessageData, origSetDelegate, origReceivedContext;

static BOOL liveReachable(void);

static BOOL sl_isReachable(WCSession *self, SEL _cmd) {
    if (linkDown) return NO;
    if (liveCarried) return liveReachable();
    return ((BOOL (*)(id, SEL))origIsReachable)(self, _cmd);
}

static NSError *notReachable(void) {
    return [NSError errorWithDomain:WCErrorDomain code:WCErrorCodeNotReachable
                           userInfo:@{NSLocalizedDescriptionKey: @"WatchConnectivity session on paired device is not reachable."}];
}

static NSError *wcError(WCErrorCode code, NSString *description) {
    return [NSError errorWithDomain:WCErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSError *timedOut(void) {
    return wcError(WCErrorCodeMessageReplyTimedOut, @"Message reply took too long.");
}

static void sendLive(NSString *kind, id payload, id replyHandler, void (^errorHandler)(NSError *));

// A live message lost on a wedged link: the sender hears only, after the timeout, that it timed out.
static void loseToWedge(void (^errorHandler)(NSError *)) {
    NSLog(@"SimLink: live message lost, link wedged");
    if (!errorHandler) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(liveTimeout * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(timedOut()); });
}

static void sl_sendMessage(WCSession *self, SEL _cmd, NSDictionary *message, id replyHandler, void (^errorHandler)(NSError *)) {
    if (linkDown) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
    if (wedged) { loseToWedge(errorHandler); return; }
    if (liveCarried && !liveReachable()) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
    if (liveCarried) { sendLive(@"message", message, replyHandler, errorHandler); return; }
    ((void (*)(id, SEL, id, id, id))origSendMessage)(self, _cmd, message, replyHandler, errorHandler);
}

static void sl_sendMessageData(WCSession *self, SEL _cmd, NSData *data, id replyHandler, void (^errorHandler)(NSError *)) {
    if (linkDown) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
    if (wedged) { loseToWedge(errorHandler); return; }
    if (liveCarried && !liveReachable()) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
    if (liveCarried) { sendLive(@"data", data, replyHandler, errorHandler); return; }
    ((void (*)(id, SEL, id, id, id))origSendMessageData)(self, _cmd, data, replyHandler, errorHandler);
}

static void sl_setDelegate(WCSession *self, SEL _cmd, id delegate) {
    if (delegate) hookDelegate(delegate);
    ((void (*)(id, SEL, id))origSetDelegate)(self, _cmd, delegate);
}

static NSDictionary *sl_receivedApplicationContext(WCSession *self, SEL _cmd) {
    if (linkDown) return deliveredContext ?: @{};
    return ((NSDictionary * (*)(id, SEL))origReceivedContext)(self, _cmd);
}

#pragma mark - The queued channels

// One item in a folder: a property list, named so that names sort in sending order. Returns its path.
static NSString *enqueueIn(NSString *dir, NSDictionary *item) {
    static uint64_t counter;
    NSString *name = [NSString stringWithFormat:@"%020llu-%06llu.plist",
                      (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1e6),
                      (unsigned long long)__atomic_add_fetch(&counter, 1, __ATOMIC_RELAXED)];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:item format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSString *tmp = [dir stringByAppendingPathComponent:[@"." stringByAppendingString:name]];
    if (!data || ![data writeToFile:tmp atomically:NO]) { NSLog(@"SimLink: could not queue %@", item[@"kind"]); return nil; }
    NSString *path = [dir stringByAppendingPathComponent:name];
    rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation);
    return path;
}

static NSString *enqueue(NSDictionary *item) { return enqueueIn(outbox, item); }

static id queueUserInfo(NSDictionary *userInfo, BOOL complication) {
    NSString *path = enqueue(@{@"kind": @"userInfo", @"userInfo": userInfo ?: @{}});
    if (!path) return nil;
    SLUserInfoTransfer *t = ((id (*)(id, SEL))objc_msgSend)([SLUserInfoTransfer alloc], @selector(init));
    t.path = path;
    t.heldUserInfo = userInfo ?: @{};
    t.complication = complication;
    @synchronized (outstanding) { [outstanding addObject:t]; }
    return t;
}

static id sl_transferUserInfo(WCSession *self, SEL _cmd, NSDictionary *userInfo) {
    return queueUserInfo(userInfo, NO);
}

static id sl_transferComplicationUserInfo(WCSession *self, SEL _cmd, NSDictionary *userInfo) {
    return queueUserInfo(userInfo, YES);
}

// The transfers whose files the receiver has not taken yet.
static NSArray *sl_outstandingUserInfoTransfers(WCSession *self, SEL _cmd) {
    @synchronized (outstanding) {
        NSIndexSet *gone = [outstanding indexesOfObjectsPassingTest:^BOOL(SLUserInfoTransfer *t, NSUInteger i, BOOL *stop) {
            return ![NSFileManager.defaultManager fileExistsAtPath:t.path];
        }];
        [outstanding removeObjectsAtIndexes:gone];
        return [outstanding copy];
    }
}

static id sl_transferFile(WCSession *self, SEL _cmd, NSURL *url, NSDictionary *metadata) {
    NSString *copy = [filesDir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, url.lastPathComponent]];
    if (![NSFileManager.defaultManager copyItemAtPath:url.path toPath:copy error:nil]) {
        NSLog(@"SimLink: could not queue file %@", url.lastPathComponent);
        return nil;
    }
    enqueue(@{@"kind": @"file", @"path": copy, @"metadata": metadata ?: @{}});
    return nil;
}

// What waits in the inbox, handed to the app in order while the link is up.
static void drainInbox(void) {
    WCSession *session = WCSession.defaultSession;
    id delegate = session.delegate;
    if (linkDown || holding || !delegate || session.activationState != WCSessionActivationStateActivated) return;
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:inbox error:nil]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [inbox stringByAppendingPathComponent:name];
        NSDictionary *item = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:path] options:0 format:NULL error:nil];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        if ([item[@"kind"] isEqual:@"userInfo"] && appUserInfo) {
            ((void (*)(id, SEL, id, id))appUserInfo)(delegate, @selector(session:didReceiveUserInfo:), session, item[@"userInfo"]);
        } else if ([item[@"kind"] isEqual:@"file"] && appFile) {
            SLSessionFile *f = ((id (*)(id, SEL))objc_msgSend)([SLSessionFile alloc], @selector(init));
            f.heldURL = [NSURL fileURLWithPath:item[@"path"]];
            f.heldMetadata = item[@"metadata"];
            ((void (*)(id, SEL, id, id))appFile)(delegate, @selector(session:didReceiveFile:), session, f);
            [NSFileManager.defaultManager removeItemAtPath:item[@"path"] error:nil];
        } else {
            NSLog(@"SimLink: %@ dropped: the app takes none", item[@"kind"]);
        }
    }
}

#pragma mark - The live messages (SIMLINK_LIVE=1)

static NSString *liveOutbox, *liveInbox;
static NSString *watchAlive;                // touched each second while the watch app can take messages
static dispatch_queue_t liveQueue;          // the sends' bookkeeping and the deliveries, in order
static NSMutableDictionary<NSString *, NSDictionary *> *pending;   // id -> the sender's handlers; on liveQueue
static const NSUInteger maxLivePayload = 65536;
static const double replyTimeout = 60;

// A sent message answered, failed, or done with: its handlers hear so, once. On liveQueue.
static void finish(NSString *ident, id reply, NSError *error) {
    NSDictionary *p = pending[ident];
    if (!p) return;
    [pending removeObjectForKey:ident];
    void (^errorHandler)(NSError *) = p[@"error"];
    void (^replyHandler)(id) = p[@"reply"];
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    if (error) {
        if (errorHandler) dispatch_async(q, ^{ errorHandler(error); });
    } else if (replyHandler && reply) {
        dispatch_async(q, ^{ replyHandler(reply); });
    }
}

static void sendLive(NSString *kind, id payload, id replyHandler, void (^errorHandler)(NSError *)) {
    // What the system refuses before sending: a payload that is not a property list, or too large.
    NSData *bytes = [kind isEqual:@"data"] ? payload
        : [NSPropertyListSerialization dataWithPropertyList:payload ?: @{} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSError *refused = !bytes ? wcError(WCErrorCodePayloadUnsupportedTypes, @"Payload contains unsupported type.")
        : bytes.length > maxLivePayload ? wcError(WCErrorCodePayloadTooLarge, @"Payload is too large.") : nil;
    if (refused) {
        NSLog(@"SimLink: live %@ refused: %@", kind, refused.localizedDescription);
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(refused); });
        return;
    }
    NSString *ident = NSUUID.UUID.UUIDString;
    id reply = [replyHandler copy], error = [errorHandler copy];
    dispatch_async(liveQueue, ^{
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        if (reply) p[@"reply"] = reply;
        if (error) p[@"error"] = error;
        pending[ident] = p;
        NSString *path = enqueueIn(liveOutbox, @{@"kind": kind, @"id": ident, @"payload": payload ?: @{}, @"wantsReply": @(reply != nil)});
        if (!path) { finish(ident, nil, wcError(WCErrorCodeDeliveryFailed, @"Delivery failed.")); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(liveTimeout * NSEC_PER_SEC)), liveQueue, ^{
            // Still in the folder: never taken. Removing it here and taking it there cannot both succeed.
            if (unlink(path.fileSystemRepresentation) == 0) {
                NSLog(@"SimLink: live %@ not taken in %.0f s: timed out", kind, liveTimeout);
                finish(ident, nil, timedOut());
            } else if (!reply) {
                finish(ident, nil, nil);
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(replyTimeout * NSEC_PER_SEC)), liveQueue, ^{
                    finish(ident, nil, timedOut());
                });
            }
        });
    });
}

static BOOL sessionReady(void) {
    WCSession *session = WCSession.defaultSession;
    return session.delegate && session.activationState == WCSessionActivationStateActivated;
}

static BOOL liveReachable(void) {
    if (linkDown) return NO;
#if TARGET_OS_WATCH
    return YES;
#else
    struct stat st;
    if (stat(watchAlive.fileSystemRepresentation, &st) != 0) return NO;
    return NSDate.date.timeIntervalSince1970 - (double)st.st_mtimespec.tv_sec < 3;
#endif
}

static void drainLive(void);

// Each tick: the watch app's heartbeat, and the delegate told when reachability changes. On liveQueue.
static void liveTick(void) {
    static int wasReachable = -1;
#if TARGET_OS_WATCH
    static unsigned ticks;
    if (ticks++ % 20 == 0 && sessionReady()) {
        int fd = open(watchAlive.fileSystemRepresentation, O_CREAT | O_WRONLY, 0644);
        if (fd >= 0) close(fd);
        utimes(watchAlive.fileSystemRepresentation, NULL);
    }
#endif
    BOOL reachable = liveReachable();
    if (wasReachable != -1 && reachable != wasReachable) {
        NSLog(@"SimLink: counterpart %@", reachable ? @"reachable" : @"not reachable");
        WCSession *session = WCSession.defaultSession;
        id<WCSessionDelegate> delegate = session.delegate;
        if ([delegate respondsToSelector:@selector(sessionReachabilityDidChange:)]) [delegate sessionReachabilityDidChange:session];
    }
    wasReachable = reachable;
    drainLive();
}

// What came in, in order: answers to this app's messages, and messages for it, taken while it can
// take them (a delegate, an activated session). Through the delegate's hooked methods, so a message
// meets the link as the system's would: dropped while it is down, late while it is slow. On liveQueue.
static void drainLive(void) {
    WCSession *session = WCSession.defaultSession;
    id delegate = session.delegate;
    BOOL ready = sessionReady();
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:liveInbox error:nil]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [liveInbox stringByAppendingPathComponent:name];
        NSDictionary *item = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:path] ?: [NSData data]
                                                                       options:0 format:NULL error:nil];
        if (!item) continue;
        NSString *kind = item[@"kind"], *ident = item[@"id"];
        BOOL answer = [kind isEqual:@"reply"] || [kind isEqual:@"failed"];
        if (!answer && !ready) continue;   // left for its sender to time out, as on a device
        // Taken by moving it aside: fails if its sender gave up on it first.
        NSString *taken = [liveInbox stringByAppendingPathComponent:[@".taken-" stringByAppendingString:name]];
        if (rename(path.fileSystemRepresentation, taken.fileSystemRepresentation) != 0) continue;
        unlink(taken.fileSystemRepresentation);
        if ([kind isEqual:@"reply"]) { finish(ident, item[@"payload"], nil); continue; }
        if ([kind isEqual:@"failed"]) { finish(ident, nil, wcError([item[@"code"] integerValue], item[@"why"])); continue; }
        // A sender long gone (its app ended before its timeout): a device would never deliver it.
        double sent = [[name substringToIndex:MIN(name.length, 20)] doubleValue] / 1e6;
        if (NSDate.date.timeIntervalSince1970 - sent > liveTimeout + 5) {
            NSLog(@"SimLink: stale live %@ dropped", kind);
            continue;
        }
        BOOL data = [kind isEqual:@"data"], wantsReply = [item[@"wantsReply"] boolValue];
        SEL sel = data ? (wantsReply ? @selector(session:didReceiveMessageData:replyHandler:) : @selector(session:didReceiveMessageData:))
                       : (wantsReply ? @selector(session:didReceiveMessage:replyHandler:) : @selector(session:didReceiveMessage:));
        if (![delegate respondsToSelector:sel]) {
            NSLog(@"SimLink: live %@ refused: the app has no %@", kind, NSStringFromSelector(sel));
            enqueueIn(liveOutbox, @{@"kind": @"failed", @"id": ident, @"code": @(WCErrorCodeDeliveryFailed),
                                    @"why": @"Delivery failed: the counterpart does not take this message."});
            continue;
        }
        if (wantsReply) {
            void (^replyBlock)(id) = ^(id response) {
                dispatch_async(liveQueue, ^{ enqueueIn(liveOutbox, @{@"kind": @"reply", @"id": ident, @"payload": response ?: @{}}); });
            };
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(delegate, sel, session, item[@"payload"], replyBlock);
        } else {
            ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, sel, session, item[@"payload"]);
        }
    }
}

static IMP swap(SEL sel, IMP replacement) {
    Method m = class_getInstanceMethod([WCSession class], sel);
    if (!m) { NSLog(@"SimLink: WCSession has no %@", NSStringFromSelector(sel)); return NULL; }
    return method_setImplementation(m, replacement);
}

#pragma mark - The control file

// Hand over what waited, in order; what arrives meanwhile queues behind it.
static void handOverHeld(void) {
    NSUInteger n = 0;
    for (;;) {
        __block dispatch_block_t block = nil;
        dispatch_sync(heldQueue, ^{ if (held.count) block = held[0]; });
        if (!block) break;
        block();
        dispatch_sync(heldQueue, ^{ [held removeObjectAtIndex:0]; });
        n++;
    }
    if (n) NSLog(@"SimLink: %lu held deliveries handed over", (unsigned long)n);
}

// "hold" ended: the live messages kept, then the queued deliveries, in order.
static void released(void) {
    dispatch_async(slowQueue, ^{
        NSArray<dispatch_block_t> *kept = [onHold copy];
        [onHold removeAllObjects];
        if (kept.count) NSLog(@"SimLink: %lu live message(s) kept on hold handed over", (unsigned long)kept.count);
        for (dispatch_block_t b in kept) {
            if (linkDown) { NSLog(@"SimLink: live message kept on hold dropped, link down"); continue; }
            b();
        }
    });
    if (!linkDown) handOverHeld();
}

static void linkChanged(BOOL down) {
    linkDown = down;
    NSLog(@"SimLink: link %@", down ? @"DOWN" : @"UP");
    WCSession *session = WCSession.defaultSession;
    id<WCSessionDelegate> delegate = session.delegate;
    if (!down && !holding) handOverHeld();
    if ([delegate respondsToSelector:@selector(sessionReachabilityDidChange:)]) {
        [delegate sessionReachabilityDidChange:session];
    }
}

__attribute__((constructor))
static void SimLinkLoad(void) {
    if (!NSClassFromString(@"WCSession")) return;
    controlPath = NSProcessInfo.processInfo.environment[@"SIMLINK_FILE"] ?: @"/tmp/sportmode-sim-link";
    NSString *queue = NSProcessInfo.processInfo.environment[@"SIMLINK_QUEUE"] ?: @"/tmp/sportmode-sim-queue";
#if TARGET_OS_WATCH
    outbox = [queue stringByAppendingPathComponent:@"to-phone"];
    inbox = [queue stringByAppendingPathComponent:@"to-watch"];
#else
    outbox = [queue stringByAppendingPathComponent:@"to-watch"];
    inbox = [queue stringByAppendingPathComponent:@"to-phone"];
#endif
    filesDir = [queue stringByAppendingPathComponent:@"files"];
#if TARGET_OS_WATCH
    liveOutbox = [queue stringByAppendingPathComponent:@"live-to-phone"];
    liveInbox = [queue stringByAppendingPathComponent:@"live-to-watch"];
#else
    liveOutbox = [queue stringByAppendingPathComponent:@"live-to-watch"];
    liveInbox = [queue stringByAppendingPathComponent:@"live-to-phone"];
#endif
    watchAlive = [queue stringByAppendingPathComponent:@"watch-alive"];
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    liveCarried = [env[@"SIMLINK_LIVE"] isEqualToString:@"1"];
    liveTimeout = [env[@"SIMLINK_LIVE_TIMEOUT"] doubleValue] ?: 15;
    for (NSString *dir in @[outbox, inbox, filesDir, liveOutbox, liveInbox]) {
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    heldQueue = dispatch_queue_create("SimLink.held", DISPATCH_QUEUE_SERIAL);
    slowQueue = dispatch_queue_create("SimLink.slow", DISPATCH_QUEUE_SERIAL);
    held = [NSMutableArray array];
    onHold = [NSMutableArray array];
    origIsReachable = swap(@selector(isReachable), (IMP)sl_isReachable);
    origSendMessage = swap(@selector(sendMessage:replyHandler:errorHandler:), (IMP)sl_sendMessage);
    origSendMessageData = swap(@selector(sendMessageData:replyHandler:errorHandler:), (IMP)sl_sendMessageData);
    origSetDelegate = swap(@selector(setDelegate:), (IMP)sl_setDelegate);
    origReceivedContext = swap(@selector(receivedApplicationContext), (IMP)sl_receivedApplicationContext);
    outstanding = [NSMutableArray array];
    swap(@selector(transferUserInfo:), (IMP)sl_transferUserInfo);
    swap(@selector(transferCurrentComplicationUserInfo:), (IMP)sl_transferComplicationUserInfo);
    swap(@selector(outstandingUserInfoTransfers), (IMP)sl_outstandingUserInfoTransfers);
    swap(@selector(transferFile:metadata:), (IMP)sl_transferFile);
    linkDown = readDown();
    NSLog(@"SimLink: loaded, control file %@, link %@, live messages carried by %@", controlPath,
          linkDown ? @"DOWN" : @"UP", liveCarried ? @"SimLink" : @"the Simulators");
    if (liveCarried) {
        liveQueue = dispatch_queue_create("SimLink.live", DISPATCH_QUEUE_SERIAL);
        pending = [NSMutableDictionary dictionary];
        dispatch_source_t live = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, liveQueue);
        dispatch_source_set_timer(live, dispatch_time(DISPATCH_TIME_NOW, 0), 50 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(live, ^{ liveTick(); });
        dispatch_resume(live);
        static dispatch_source_t keepLive;
        keepLive = live;
    }
    // A serial queue of its own: the change runs the delegate, which may take a while.
    dispatch_queue_t q = dispatch_queue_create("SimLink.watch", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        BOOL wasHolding = holding;
        BOOL down = readDown();
        if (down != linkDown) linkChanged(down);
        if (wasHolding && !holding) released();
        drainInbox();
    });
    dispatch_resume(timer);
    static dispatch_source_t keep;
    keep = timer;
}
