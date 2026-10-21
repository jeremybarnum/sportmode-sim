#!/usr/bin/env python3
"""The notification texts a Simulator holds, pending and delivered, one per line:
notifications.py <simulator udid> [pending|delivered]. Read from the Simulator's notification store,
so a test can check a notification whose text the app never logs (a scheduled Loop Failure).

notifications.py <simulator udid> --since HH:MM:SS [pending|delivered]: the notifications created at
or after that time today, one per line: kind, time, title, message. A notification posted again
under the same identifier replaces the one before, so counting texts cannot tell a new one from an
old one; its creation time can."""
import datetime, glob, os, plistlib, sys

args = sys.argv[1:]
udid = args.pop(0)
since = None
if args[:1] == ["--since"]:
    hh, mm, ss = (int(x) for x in args[1].split(":"))
    since = datetime.datetime.now().replace(hour=hh, minute=mm, second=ss, microsecond=0)
    args = args[2:]
kinds = args or ["pending", "delivered"]
root = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data/Library/UserNotifications")
names = {"pending": "PendingNotifications.plist", "delivered": "DeliveredNotifications.plist"}


def records(objects):
    """Each archived notification: a dictionary whose keys include AppNotificationTitle."""
    def get(ref):
        return objects[ref.data] if isinstance(ref, plistlib.UID) else ref
    for obj in objects:
        if not (isinstance(obj, dict) and "NS.keys" in obj):
            continue
        keys = [get(k) for k in obj["NS.keys"]]
        if "AppNotificationTitle" not in keys:
            continue
        rec = dict(zip(keys, (get(v) for v in obj["NS.objects"])))
        created = rec.get("AppNotificationCreationDate")
        when = None
        if isinstance(created, dict) and "NS.time" in created:
            utc = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc) + datetime.timedelta(seconds=created["NS.time"])
            when = utc.astimezone().replace(tzinfo=None)
        yield when, rec.get("AppNotificationTitle") or "", rec.get("AppNotificationMessage") or ""


for kind in kinds:
    for path in glob.glob(os.path.join(root, "*", names[kind])):
        try:
            data = plistlib.load(open(path, "rb"))
        except Exception:
            continue
        objects = data.get("$objects", []) if isinstance(data, dict) else []
        if since is None:
            for obj in objects:
                if isinstance(obj, str) and len(obj) > 3 and " " in obj and not obj.startswith("NS"):
                    print(f"{kind}\t{obj}")
            continue
        for when, title, message in records(objects):
            if when is not None and when >= since:
                print(f"{kind}\t{when:%H:%M:%S}\t{title}\t{message}")
