#!/usr/bin/env python3
"""The notification texts a Simulator holds, pending and delivered, one per line:
notifications.py <simulator udid> [pending|delivered]. Read from the Simulator's notification store,
so a test can check a notification whose text the app never logs (a scheduled Loop Failure)."""
import glob, os, plistlib, sys

udid = sys.argv[1]
kinds = sys.argv[2:] or ["pending", "delivered"]
root = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data/Library/UserNotifications")
names = {"pending": "PendingNotifications.plist", "delivered": "DeliveredNotifications.plist"}
for kind in kinds:
    for path in glob.glob(os.path.join(root, "*", names[kind])):
        try:
            data = plistlib.load(open(path, "rb"))
        except Exception:
            continue
        for obj in data.get("$objects", []) if isinstance(data, dict) else []:
            if isinstance(obj, str) and len(obj) > 3 and " " in obj and not obj.startswith("NS"):
                print(f"{kind}\t{obj}")
