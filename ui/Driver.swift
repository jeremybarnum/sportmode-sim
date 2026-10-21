// A UI test that serves commands for one app instead of running a script: it attaches to the app
// already running (launched by sim.sh with the Bluetooth shim injected) and, until told to quit,
// reads a command from /tmp/sportmode-ui/<side>.cmd, carries it out and writes the result to
// <side>.out. The bundle id of the app to drive is in <side>.app.
//
//   tap <label>          tap the button (or else any element) with that label or identifier
//   tap~ <text>          the same, for a label containing the text
//   wait <s> <label>     wait up to s seconds for it to appear
//   gone <s> <label>     wait up to s seconds for it to go
//   swipe <direction>    swipe the screen: left, right, up or down
//   type <text>          type into the focused field
//   double <text>        double-tap the element whose label contains the text
//   press [s] <text>     press and hold it (default 2 s)
//   slide <text>         drag a slide-to-confirm control from end to end
//   field [text]         tap the first text field (or the first whose placeholder or label has the text)
//   tapxy <x> <y>        tap a point, in points from the top left (a control with no label)
//   pressxy <x> <y> [s]  press and hold a point (default 2 s)
//   swipeleft <text>     swipe left on the element whose label contains the text (a row's actions)
//   crown <turns> [v]    turn the crown (watch); 1.0 is a full turn; v in turns per second
//   sys <label>          tap a button of a system sheet or alert (phone)
//   systype <text>       type into a system sheet, such as the passcode (phone); \n for return
//   tree                 the app's element tree, to <side>.tree
//   quit                 end the test
//
// A command line is "<id> <verb> <argument>"; the result is "<id> ok|fail <message>".

import XCTest

final class Driver: XCTestCase {
    #if os(watchOS)
    let side = "watch"
    #else
    let side = "phone"
    #endif
    let dir = URL(fileURLWithPath: "/tmp/sportmode-ui")
    let timeout: TimeInterval = 10

    func testServe() throws {
        let bundle = try String(contentsOf: dir.appendingPathComponent("\(side).app"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.activate()
        write("ready", "0 ok attached to \(bundle)")
        var last = ""
        var beat = Date.distantPast
        while true {
            // A heartbeat, so the shell can tell a driver that stopped answering (the watch shut down
            // under it) from one that is busy.
            if Date().timeIntervalSince(beat) > 1 { write("beat", "\(Date())"); beat = Date() }
            guard let line = try? String(contentsOf: dir.appendingPathComponent("\(side).cmd"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let space = line.firstIndex(of: " "), String(line[..<space]) != last
            else { Thread.sleep(forTimeInterval: 0.1); continue }
            let id = String(line[..<space])
            last = id
            let rest = line[line.index(after: space)...]
            let verb = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            let arg = rest.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            if verb == "quit" { write("out", "\(id) ok quit"); return }
            let started = Date()
            let (ok, message) = run(verb, arg, app)
            write("out", "\(id) \(ok ? "ok" : "fail") \(message) (\(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
        }
    }

    private func run(_ verb: String, _ arg: String, _ app: XCUIApplication) -> (Bool, String) {
        switch verb {
        case "tap", "tap~":
            guard let element = find(arg, contains: verb == "tap~", in: app, within: timeout) else {
                return (false, "no \(arg)")
            }
            let label = element.label
            // A view that takes taps without being a control (a status display) is not "hittable"
            // to XCTest, and tapping it ends the test: tap its middle instead.
            if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            return (true, "tapped \(label)")
        case "swipeleft":
            // An element's own swipe, for a list row's actions.
            guard let element = find(arg, contains: true, in: app, within: timeout) else { return (false, "no \(arg)") }
            element.swipeLeft()
            return (true, "swiped \(arg)")
        case "tapxy":
            // A point on the screen, in points from the top left: for a control with no label.
            let xy = arg.split(separator: " ").compactMap { Double($0) }
            guard xy.count == 2 else { return (false, "tapxy <x> <y>") }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            return (true, "tapped \(arg)")
        case "field":
            let fields = app.textFields.allElementsBoundByIndex.filter { field in
                arg.isEmpty || field.label.contains(arg) || ((field.placeholderValue ?? "").contains(arg))
            }
            guard let field = fields.first else { return (false, "no text field \(arg)") }
            field.tap()
            return (true, "tapped the text field")
        case "pressxy":
            let v = arg.split(separator: " ").compactMap { Double($0) }
            guard v.count >= 2 else { return (false, "pressxy <x> <y> [s]") }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: v[0], dy: v[1]))
                .press(forDuration: v.count > 2 ? v[2] : 2)
            return (true, "pressed \(arg)")
        case "slide":
            // A slide-to-confirm control: drag from its left end to its right end.
            guard let element = find(arg, contains: true, in: app, within: timeout) else { return (false, "no \(arg)") }
            #if os(iOS)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
                .press(forDuration: 0.3, thenDragTo: element.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            #else
            element.swipeRight()
            #endif
            return (true, "slid \(arg)")
        case "press":
            let (seconds, label) = timed(arg)
            guard let element = find(label, contains: true, in: app, within: timeout) else { return (false, "no \(label)") }
            element.press(forDuration: seconds == timeout ? 2 : seconds)
            return (true, "pressed \(label)")
        case "double":
            guard let element = find(arg, contains: true, in: app, within: timeout) else { return (false, "no \(arg)") }
            element.doubleTap()
            return (true, "double-tapped \(arg)")
        case "wait", "gone":
            let (seconds, label) = timed(arg)
            if verb == "wait" {
                return find(label, contains: false, in: app, within: seconds) != nil ? (true, "seen") : (false, "not seen")
            }
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if find(label, contains: false, in: app, within: 0) == nil { return (true, "gone") }
                Thread.sleep(forTimeInterval: 0.2)
            }
            return (false, "still there")
        case "swipe":
            switch arg {
            case "left": app.swipeLeft()
            case "right": app.swipeRight()
            case "up": app.swipeUp()
            case "down": app.swipeDown()
            default: return (false, "swipe left|right|up|down")
            }
            return (true, "swiped \(arg)")
        case "type":
            app.typeText(arg)
            return (true, "typed")
        case "crown":
            #if os(watchOS)
            let parts = arg.split(separator: " ").compactMap { Double($0) }
            if parts.count > 1 {
                XCUIDevice.shared.rotateDigitalCrown(delta: CGFloat(parts[0]), velocity: XCUIGestureVelocity(CGFloat(parts[1])))
            } else {
                XCUIDevice.shared.rotateDigitalCrown(delta: CGFloat(parts.first ?? 1))
            }
            return (true, "turned")
            #else
            return (false, "no crown on the phone")
            #endif
        case "systype":
            #if os(iOS)
            XCUIApplication(bundleIdentifier: "com.apple.springboard").typeText(arg.replacingOccurrences(of: "\\n", with: "\n"))
            return (true, "typed")
            #else
            return (false, "phone only")
            #endif
        case "sys":
            #if os(iOS)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            guard let element = find(arg, contains: false, in: springboard, within: timeout) else { return (false, "no \(arg)") }
            element.tap()
            return (true, "tapped \(arg)")
            #else
            return (false, "phone only")
            #endif
        case "tree":
            write("tree", app.debugDescription)
            return (true, "tree written")
        default:
            return (false, "unknown command \(verb)")
        }
    }

    private func find(_ text: String, contains: Bool, in app: XCUIApplication, within seconds: TimeInterval) -> XCUIElement? {
        let predicate = contains
            ? NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", text, text)
            : NSPredicate(format: "label == %@ OR identifier == %@", text, text)
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let button = app.buttons.matching(predicate).firstMatch
            if button.exists { return button }
            let any = app.descendants(matching: .any).matching(predicate).firstMatch
            if any.exists { return any }
            if seconds > 0 { Thread.sleep(forTimeInterval: 0.2) }
        } while Date() < end
        return nil
    }

    private func timed(_ arg: String) -> (TimeInterval, String) {
        let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { return (timeout, arg) }
        return (seconds, parts[1])
    }

    private func write(_ name: String, _ text: String) {
        try? (text + "\n").write(to: dir.appendingPathComponent("\(side).\(name)"), atomically: true, encoding: .utf8)
    }
}
