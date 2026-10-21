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
// Control file: $SIMLINK_FILE, default /tmp/sportmode-sim-link. Queues:
// $SIMLINK_QUEUE/to-phone and to-watch, default /tmp/sportmode-sim-queue.

#import <Foundation/Foundation.h>
#import <WatchConnectivity/WatchConnectivity.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *controlPath;
static NSString *outbox, *inbox, *filesDir;   // the queued channels' folders
static BOOL linkDown;
static double latency;                      // "slow N": seconds each incoming live message waits
static dispatch_queue_t slowQueue;          // where they wait, in arrival order
static dispatch_queue_t heldQueue;          // the held deliveries, in arrival order
static NSMutableArray<dispatch_block_t> *held;
static NSDictionary *deliveredContext;      // the last application context the app was given

static BOOL readDown(void) {
    NSString *s = [[NSString stringWithContentsOfFile:controlPath encoding:NSUTF8StringEncoding error:nil]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    double slow = [s hasPrefix:@"slow "] ? [[s substringFromIndex:5] doubleValue] : 0;
    if (slow != latency) NSLog(@"SimLink: live messages %@", slow > 0 ? [NSString stringWithFormat:@"%.1f s late", slow] : @"on time");
    latency = slow;
    return [s isEqualToString:@"down"];
}

// A live message, now or after the link's latency.
static void arrive(dispatch_block_t block) {
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

// Runs now, or later in order if the link is down (or earlier deliveries still wait).
static void deliver(dispatch_block_t block) {
    __block BOOL now = NO;
    dispatch_sync(heldQueue, ^{
        if (!linkDown && held.count == 0) {
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

static void sl_messageReply(id self, SEL _cmd, WCSession *session, NSDictionary *message, id reply) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    arrive(^{ ((void (*)(id, SEL, id, id, id))appMessageReply)(self, _cmd, session, message, reply); });
}

static void sl_data(id self, SEL _cmd, WCSession *session, NSData *data) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    arrive(^{ ((void (*)(id, SEL, id, id))appData)(self, _cmd, session, data); });
}

static void sl_dataReply(id self, SEL _cmd, WCSession *session, NSData *data, id reply) {
    if (linkDown) { NSLog(@"SimLink: live message dropped, link down"); return; }
    arrive(^{ ((void (*)(id, SEL, id, id, id))appDataReply)(self, _cmd, session, data, reply); });
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
    if (!linkDown) {
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

static BOOL sl_isReachable(WCSession *self, SEL _cmd) {
    if (linkDown) return NO;
    return ((BOOL (*)(id, SEL))origIsReachable)(self, _cmd);
}

static NSError *notReachable(void) {
    return [NSError errorWithDomain:WCErrorDomain code:WCErrorCodeNotReachable
                           userInfo:@{NSLocalizedDescriptionKey: @"WatchConnectivity session on paired device is not reachable."}];
}

static void sl_sendMessage(WCSession *self, SEL _cmd, NSDictionary *message, id replyHandler, void (^errorHandler)(NSError *)) {
    if (linkDown) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
    ((void (*)(id, SEL, id, id, id))origSendMessage)(self, _cmd, message, replyHandler, errorHandler);
}

static void sl_sendMessageData(WCSession *self, SEL _cmd, NSData *data, id replyHandler, void (^errorHandler)(NSError *)) {
    if (linkDown) {
        if (errorHandler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorHandler(notReachable()); });
        return;
    }
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

// One item: a property list, named so that names sort in sending order. Returns its path.
static NSString *enqueue(NSDictionary *item) {
    static uint64_t counter;
    NSString *name = [NSString stringWithFormat:@"%020llu-%06llu.plist",
                      (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1e6), (unsigned long long)++counter];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:item format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSString *tmp = [outbox stringByAppendingPathComponent:[@"." stringByAppendingString:name]];
    if (!data || ![data writeToFile:tmp atomically:NO]) { NSLog(@"SimLink: could not queue %@", item[@"kind"]); return nil; }
    NSString *path = [outbox stringByAppendingPathComponent:name];
    rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation);
    return path;
}

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
    if (linkDown || !delegate || session.activationState != WCSessionActivationStateActivated) return;
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

static IMP swap(SEL sel, IMP replacement) {
    Method m = class_getInstanceMethod([WCSession class], sel);
    if (!m) { NSLog(@"SimLink: WCSession has no %@", NSStringFromSelector(sel)); return NULL; }
    return method_setImplementation(m, replacement);
}

#pragma mark - The control file

static void linkChanged(BOOL down) {
    linkDown = down;
    NSLog(@"SimLink: link %@", down ? @"DOWN" : @"UP");
    WCSession *session = WCSession.defaultSession;
    id<WCSessionDelegate> delegate = session.delegate;
    if (!down) {
        // Hand over what waited, in order; what arrives meanwhile queues behind it.
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
    for (NSString *dir in @[outbox, inbox, filesDir]) {
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    heldQueue = dispatch_queue_create("SimLink.held", DISPATCH_QUEUE_SERIAL);
    slowQueue = dispatch_queue_create("SimLink.slow", DISPATCH_QUEUE_SERIAL);
    held = [NSMutableArray array];
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
    NSLog(@"SimLink: loaded, control file %@, link %@", controlPath, linkDown ? @"DOWN" : @"UP");
    // A serial queue of its own: the change runs the delegate, which may take a while.
    dispatch_queue_t q = dispatch_queue_create("SimLink.watch", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        BOOL down = readDown();
        if (down != linkDown) linkChanged(down);
        drainInbox();
    });
    dispatch_resume(timer);
    static dispatch_source_t keep;
    keep = timer;
}
