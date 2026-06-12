import AppKit
import ServiceManagement

// MARK: - Defaults & messages

enum Config {
    static let waterIntervalMinutes = 60     // drink water every hour
    static let walkAfterWorkMinutes = 45     // walk break after 45 min of work
    static let lunchMinutes = 12 * 60        // 12:00
    static let dinnerMinutes = 18 * 60 + 30  // 18:30
    static let mealWindowMinutes = 45        // still remind if app opens a bit late
    static let idleResetSeconds: Double = 300 // away 5 min = work timer resets
    static let bubbleSeconds: Double = 18    // how long the speech bubble stays

    static let waterMessages = [
        "💧 喝水时间到啦～\nTime for some water!",
        "💧 咕嘟咕嘟，补充水分哦～\nStay hydrated!",
    ]
    static let walkMessages = [
        "🚶‍♀️ 工作好久啦，起来走走吧～\nYou've worked a while — take a little walk!",
        "🌸 休息一下，伸展伸展～\nTime to stretch those legs!",
    ]
    static let lunchMessages = [
        "🍱 午饭时间！要好好吃饭哦～\nLunch time, go eat something yummy!",
    ]
    static let dinnerMessages = [
        "🍝 晚饭时间到啦，不许跳过哦～\nDinner time, don't skip it!",
    ]
}

// MARK: - Persistent settings

struct CustomReminder: Codable, Equatable {
    var id = UUID()
    var text: String
    var isDaily: Bool   // true = daily at a time of day, false = repeating interval
    var minutes: Int    // time-of-day minutes if daily, else interval minutes
    var enabled = true
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    var remindersEnabled: Bool { didSet { d.set(remindersEnabled, forKey: "remindersEnabled") } }
    var waterEnabled: Bool     { didSet { d.set(waterEnabled, forKey: "waterEnabled") } }
    var waterMinutes: Int      { didSet { d.set(waterMinutes, forKey: "waterMinutes") } }
    var walkEnabled: Bool      { didSet { d.set(walkEnabled, forKey: "walkEnabled") } }
    var walkMinutes: Int       { didSet { d.set(walkMinutes, forKey: "walkMinutes") } }
    var lunchEnabled: Bool     { didSet { d.set(lunchEnabled, forKey: "lunchEnabled") } }
    var lunchMinutes: Int      { didSet { d.set(lunchMinutes, forKey: "lunchMinutes") } }
    var dinnerEnabled: Bool    { didSet { d.set(dinnerEnabled, forKey: "dinnerEnabled") } }
    var dinnerMinutes: Int     { didSet { d.set(dinnerMinutes, forKey: "dinnerMinutes") } }
    var loginItemDesired: Bool { didSet { d.set(loginItemDesired, forKey: "loginItemDesired") } }
    var petScale: Double  { didSet { d.set(petScale, forKey: "petScale") } }
    var petSpeed: Double  { didSet { d.set(petSpeed, forKey: "petSpeed") } }
    // custom message texts for the built-in reminders; empty = use the default bilingual messages
    var waterText: String  { didSet { d.set(waterText, forKey: "waterText") } }
    var walkText: String   { didSet { d.set(walkText, forKey: "walkText") } }
    var lunchText: String  { didSet { d.set(lunchText, forKey: "lunchText") } }
    var dinnerText: String { didSet { d.set(dinnerText, forKey: "dinnerText") } }
    var customReminders: [CustomReminder] {
        didSet {
            if let data = try? JSONEncoder().encode(customReminders) {
                d.set(data, forKey: "customReminders")
            }
        }
    }

    private init() {
        let ud = UserDefaults.standard
        func bool(_ key: String, _ def: Bool) -> Bool {
            ud.object(forKey: key) == nil ? def : ud.bool(forKey: key)
        }
        func int(_ key: String, _ def: Int) -> Int {
            ud.object(forKey: key) == nil ? def : ud.integer(forKey: key)
        }
        remindersEnabled = bool("remindersEnabled", true)
        waterEnabled = bool("waterEnabled", true)
        waterMinutes = int("waterMinutes", Config.waterIntervalMinutes)
        walkEnabled = bool("walkEnabled", true)
        walkMinutes = int("walkMinutes", Config.walkAfterWorkMinutes)
        lunchEnabled = bool("lunchEnabled", true)
        lunchMinutes = int("lunchMinutes", Config.lunchMinutes)
        dinnerEnabled = bool("dinnerEnabled", true)
        dinnerMinutes = int("dinnerMinutes", Config.dinnerMinutes)
        loginItemDesired = bool("loginItemDesired", true)
        petScale = ud.object(forKey: "petScale") == nil ? 1.0 : ud.double(forKey: "petScale")
        petSpeed = ud.object(forKey: "petSpeed") == nil ? 1.0 : ud.double(forKey: "petSpeed")
        waterText = ud.string(forKey: "waterText") ?? ""
        walkText = ud.string(forKey: "walkText") ?? ""
        lunchText = ud.string(forKey: "lunchText") ?? ""
        dinnerText = ud.string(forKey: "dinnerText") ?? ""
        if let data = ud.data(forKey: "customReminders"),
           let arr = try? JSONDecoder().decode([CustomReminder].self, from: data) {
            customReminders = arr
        } else {
            customReminders = []
        }
    }
}

func formatTime(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, minutes % 60)
}

// MARK: - Speech bubble

final class BubbleView: NSView {
    static let font = NSFont.systemFont(ofSize: 14, weight: .medium)
    // 9-slice geometry of bubble.png (image pixels); the tail sits in the bottom-left corner slice
    static let srcL: CGFloat = 400, srcR: CGFloat = 150, srcT: CGFloat = 150, srcB: CGFloat = 278
    static let sliceScale: CGFloat = 0.125
    static let imageTailHeight: CGFloat = 128 * sliceScale   // 16
    static let imageTailCenterX: CGFloat = 281 * sliceScale  // ~35, from the bubble's left edge
    static let drawnTailHeight: CGFloat = 12

    var image: NSImage?
    var text = ""
    var onDismiss: (() -> Void)?

    var tailHeight: CGFloat { image == nil ? BubbleView.drawnTailHeight : BubbleView.imageTailHeight }

    override func draw(_ dirtyRect: NSRect) {
        if let img = image {
            drawNineSlice(img)
        } else {
            drawVectorBubble()
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: BubbleView.font,
            .foregroundColor: NSColor.black.withAlphaComponent(0.85),
        ]
        let textRect = NSRect(x: 16, y: tailHeight + 11,
                              width: bounds.width - 32, height: bounds.height - tailHeight - 24)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    private func drawNineSlice(_ img: NSImage) {
        NSGraphicsContext.current?.imageInterpolation = .high
        let s = BubbleView.sliceScale
        let W = img.size.width, H = img.size.height
        let sx: [CGFloat] = [0, BubbleView.srcL, W - BubbleView.srcR, W]
        let sy: [CGFloat] = [0, BubbleView.srcB, H - BubbleView.srcT, H]
        let dx: [CGFloat] = [0, BubbleView.srcL * s, bounds.width - BubbleView.srcR * s, bounds.width]
        let dy: [CGFloat] = [0, BubbleView.srcB * s, bounds.height - BubbleView.srcT * s, bounds.height]
        for i in 0..<3 {
            for j in 0..<3 {
                let src = NSRect(x: sx[i], y: sy[j], width: sx[i+1] - sx[i], height: sy[j+1] - sy[j])
                let dst = NSRect(x: dx[i], y: dy[j], width: dx[i+1] - dx[i], height: dy[j+1] - dy[j])
                if dst.width > 0.1 && dst.height > 0.1 {
                    img.draw(in: dst, from: src, operation: .sourceOver, fraction: 1.0)
                }
            }
        }
    }

    private func drawVectorBubble() {
        let tailH = BubbleView.drawnTailHeight
        let body = NSRect(x: 0, y: tailH, width: bounds.width, height: bounds.height - tailH)
            .insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let cx = bounds.midX
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: cx - 9, y: tailH + 2))
        tail.line(to: NSPoint(x: cx, y: 1))
        tail.line(to: NSPoint(x: cx + 9, y: tailH + 2))
        tail.close()
        path.append(tail)
        NSColor(calibratedWhite: 1.0, alpha: 0.97).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }
}

// MARK: - Pet view (draws the cat + close button, handles click/drag/right-click)

final class PetView: NSView {
    var frames: [NSImage] = []
    var eatImage: NSImage?
    var sleepImage: NSImage?
    var poseOverride: NSImage? {
        didSet { if poseOverride !== oldValue { needsDisplay = true } }
    }
    var isEating = false {
        didSet { if isEating != oldValue { needsDisplay = true } }
    }
    var isSleeping = false {
        didSet { if isSleeping != oldValue { needsDisplay = true } }
    }
    var frameIndex = 0 {
        didSet { if frameIndex != oldValue { needsDisplay = true } }
    }
    var facingRight = false {
        didSet { if facingRight != oldValue { needsDisplay = true } }
    }
    var showsCloseButton = false {
        didSet { if showsCloseButton != oldValue { needsDisplay = true } }
    }
    weak var controller: PetController?

    var petSize = NSSize(width: 130, height: 114)
    var petRect: NSRect {
        NSRect(x: (bounds.width - petSize.width) / 2, y: 0,
               width: petSize.width, height: petSize.height)
    }
    var closeButtonRect: NSRect {
        NSRect(x: petRect.maxX - 20, y: petRect.maxY + 4, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !frames.isEmpty, let ctx = NSGraphicsContext.current else { return }
        let img = (isEating ? eatImage : nil)
            ?? (isSleeping ? sleepImage : nil)
            ?? poseOverride
            ?? frames[min(frameIndex, frames.count - 1)]
        ctx.imageInterpolation = .high
        ctx.saveGraphicsState()
        if facingRight {
            // artwork faces left; pet is horizontally centered, so mirror the whole bounds
            let t = NSAffineTransform()
            t.translateX(by: bounds.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
        }
        // aspect-fit each frame, anchored to the bottom center so feet stay grounded
        let aspect = img.size.width / img.size.height
        var dw = petRect.width
        var dh = dw / aspect
        if dh > petRect.height {
            dh = petRect.height
            dw = dh * aspect
        }
        let drawRect = NSRect(x: petRect.midX - dw / 2, y: petRect.minY, width: dw, height: dh)
        img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGraphicsState()

        if showsCloseButton {
            let r = closeButtonRect
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            NSColor(calibratedWhite: 1.0, alpha: 0.95).setFill()
            circle.fill()
            NSColor(calibratedWhite: 0.25, alpha: 1.0).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            let x = NSBezierPath()
            x.lineWidth = 2
            let inset: CGFloat = 8
            x.move(to: NSPoint(x: r.minX + inset, y: r.minY + inset))
            x.line(to: NSPoint(x: r.maxX - inset, y: r.maxY - inset))
            x.move(to: NSPoint(x: r.minX + inset, y: r.maxY - inset))
            x.line(to: NSPoint(x: r.maxX - inset, y: r.minY + inset))
            NSColor(calibratedWhite: 0.25, alpha: 1.0).setStroke()
            x.stroke()
        }
    }

    // distinguish click (toggle pause) from drag (move the pet)
    private var pressLocation = NSPoint.zero
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        pressLocation = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = NSEvent.mouseLocation
        if !dragging {
            guard hypot(loc.x - pressLocation.x, loc.y - pressLocation.y) > 4 else { return }
            dragging = true
            controller?.beginDrag()
        }
        guard let window = self.window else { return }
        var origin = window.frame.origin
        origin.x += event.deltaX
        origin.y -= event.deltaY
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            controller?.endDrag()
        } else {
            controller?.handleClick(at: convert(event.locationInWindow, from: nil),
                                    clickCount: event.clickCount)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showSettings()
    }

    // hover tracking (for belly rubs while lying down)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.hoverMoved(deltaX: event.deltaX)
    }

    // file drag & drop: the pet is a hungry trash bin
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        isEating = true
        controller?.fileDragActive = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isEating = false
        controller?.fileDragActive = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isEating = false
        controller?.fileDragActive = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isEating = false
        controller?.fileDragActive = false
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        controller?.trash(urls)
        return true
    }
}

// MARK: - Settings window (right-click the pet)

final class SettingsWindowController: NSObject, NSWindowDelegate {
    weak var controller: PetController?
    private var window: NSWindow?

    private var masterCheck: NSButton!
    private var waterCheck: NSButton!
    private var waterField: NSTextField!
    private var waterStepper: NSStepper!
    private var walkCheck: NSButton!
    private var walkField: NSTextField!
    private var walkStepper: NSStepper!
    private var lunchCheck: NSButton!
    private var lunchPicker: NSDatePicker!
    private var dinnerCheck: NSButton!
    private var dinnerPicker: NSDatePicker!
    private var loginCheck: NSButton!
    private var waterMsgField: NSTextField!
    private var walkMsgField: NSTextField!
    private var lunchMsgField: NSTextField!
    private var dinnerMsgField: NSTextField!
    private var tabView: NSTabView!
    private var remindersTabStack: NSStackView!
    private var customTabStack: NSStackView!
    private var generalTabStack: NSStackView!
    private var customListStack: NSStackView!
    private var newReminderField: NSTextField!
    private var newTypePopup: NSPopUpButton!
    private var newMinutesField: NSTextField!
    private var newMinutesStepper: NSStepper!
    private var newMinutesLabel: NSTextField!
    private var newTimePicker: NSDatePicker!
    private var sizeSlider: NSSlider!
    private var sizeValueLabel: NSTextField!
    private var speedSlider: NSSlider!
    private var speedValueLabel: NSTextField!

    init(controller: PetController) {
        self.controller = controller
    }

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible() {
        if window?.isVisible == true { refresh() }
    }

    private func build() {
        let s = Settings.shared

        masterCheck = NSButton(checkboxWithTitle: "Enable all reminders", target: self, action: #selector(uiChanged))

        waterCheck = NSButton(checkboxWithTitle: "💧 Drink water — every", target: self, action: #selector(uiChanged))
        (waterField, waterStepper) = makeMinutesControls(value: s.waterMinutes,
                                                         fieldAction: #selector(waterFieldChanged),
                                                         stepperAction: #selector(waterStepperChanged))
        walkCheck = NSButton(checkboxWithTitle: "🚶‍♀️ Walk break — after", target: self, action: #selector(uiChanged))
        (walkField, walkStepper) = makeMinutesControls(value: s.walkMinutes,
                                                       fieldAction: #selector(walkFieldChanged),
                                                       stepperAction: #selector(walkStepperChanged))

        lunchCheck = NSButton(checkboxWithTitle: "🍱 Lunch at", target: self, action: #selector(uiChanged))
        lunchPicker = makeTimePicker(minutes: s.lunchMinutes)
        dinnerCheck = NSButton(checkboxWithTitle: "🍝 Dinner at", target: self, action: #selector(uiChanged))
        dinnerPicker = makeTimePicker(minutes: s.dinnerMinutes)

        loginCheck = NSButton(checkboxWithTitle: "Start MacPet automatically at login", target: self, action: #selector(loginToggled))

        waterMsgField = makeMessageField()
        walkMsgField = makeMessageField()
        lunchMsgField = makeMessageField()
        dinnerMsgField = makeMessageField()

        func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

        // custom reminders section
        customListStack = NSStackView()
        customListStack.orientation = .vertical
        customListStack.alignment = .leading
        customListStack.spacing = 6

        newReminderField = NSTextField(string: "")
        newReminderField.placeholderString = "提醒内容 / Reminder text…"
        newReminderField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        newTypePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        newTypePopup.addItems(withTitles: ["Every", "Daily at"])
        newTypePopup.target = self
        newTypePopup.action = #selector(newTypeChanged)

        (newMinutesField, newMinutesStepper) = makeMinutesControls(
            value: 30,
            fieldAction: #selector(newMinutesFieldChanged),
            stepperAction: #selector(newMinutesStepperChanged))
        newMinutesLabel = label("min")

        newTimePicker = makeTimePicker(minutes: 20 * 60)
        newTimePicker.target = nil
        newTimePicker.action = nil
        newTimePicker.isHidden = true

        let addButton = NSButton(title: "Add", target: self, action: #selector(addCustomReminder))

        // tab 1: built-in reminders
        let remindersNote = label("Walk timer resets after 5 min away from the keyboard.\nLeave a message field blank to use the default bilingual message.")
        remindersNote.font = NSFont.systemFont(ofSize: 11)
        remindersNote.textColor = .secondaryLabelColor

        remindersTabStack = tabStack([
            masterCheck,
            separator(),
            hRow([waterCheck, waterField, waterStepper, label("minutes")]),
            waterMsgField,
            hRow([walkCheck, walkField, walkStepper, label("minutes of work")]),
            walkMsgField,
            hRow([lunchCheck, lunchPicker]),
            lunchMsgField,
            hRow([dinnerCheck, dinnerPicker]),
            dinnerMsgField,
            remindersNote,
        ])

        // tab 2: pet size/speed + user-defined reminders
        let petTitle = label("宠物 Pet")
        petTitle.font = NSFont.boldSystemFont(ofSize: 13)

        sizeSlider = NSSlider(value: Settings.shared.petScale, minValue: 0.6, maxValue: 2.0,
                              target: self, action: #selector(sizeChanged))
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        sizeValueLabel = label("")
        speedSlider = NSSlider(value: Settings.shared.petSpeed, minValue: 0.3, maxValue: 3.0,
                               target: self, action: #selector(speedChanged))
        speedSlider.isContinuous = true
        speedSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        speedValueLabel = label("")

        let customTitle = label("自定义提醒 Custom Reminders")
        customTitle.font = NSFont.boldSystemFont(ofSize: 13)

        let customHint = label("Add your own reminders — toggle with the checkbox, remove with ✕.\nChanges apply immediately and are saved permanently.")
        customHint.font = NSFont.systemFont(ofSize: 11)
        customHint.textColor = .secondaryLabelColor

        customTabStack = tabStack([
            petTitle,
            hRow([label("大小 Size"), sizeSlider, sizeValueLabel]),
            hRow([label("速度 Speed"), speedSlider, speedValueLabel]),
            separator(),
            customTitle,
            customListStack,
            hRow([newReminderField, newTypePopup, newMinutesField, newMinutesStepper,
                  newMinutesLabel, newTimePicker, addButton]),
            customHint,
        ])

        // tab 3: general / user menu + manual
        let dropButton = NSButton(title: "Drop From Top", target: controller,
                                  action: #selector(PetController.resetPosition))
        let quitButton = NSButton(title: "Quit MacPet", target: NSApp,
                                  action: #selector(NSApplication.terminate(_:)))
        let manualTitle = label("使用说明 User Manual")
        manualTitle.font = NSFont.boldSystemFont(ofSize: 13)

        generalTabStack = tabStack([
            loginCheck,
            hRow([dropButton, quitButton]),
            separator(),
            manualTitle,
            makeManualView(),
        ])

        rebuildCustomList()

        tabView = NSTabView()
        func addTab(_ title: String, _ view: NSView) {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabView.addTabViewItem(item)
        }
        addTab("提醒 Reminders", remindersTabStack)
        addTab("自定义 Custom", customTabStack)
        addTab("通用 General", generalTabStack)
        tabView.selectTabViewItem(at: 0)

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 360)),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "MacPet Settings"
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.contentView = tabView
        win.delegate = self
        window = win
        relayout()
        win.center()
    }

    private func tabStack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 12
        s.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return s
    }

    func selectTab(_ index: Int) {
        tabView?.selectTabViewItem(at: index)
    }

    private func makeManualView() -> NSScrollView {
        let manual = NSMutableAttributedString()
        func section(_ title: String, _ lines: [String]) {
            manual.append(NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ]))
            manual.append(NSAttributedString(string: lines.map { "• " + $0 }.joined(separator: "\n") + "\n\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }

        section("🐶 桌面宠物 Desktop Pet", [
            "小狗会在屏幕底部走来走去、蹦蹦跳跳，偶尔停下来喘口气。",
            "The dog walks along the bottom of your screen, hops around, and sometimes pauses to rest.",
            "有时它会慢慢坐下、翻过身躺平，休息够了再爬起来继续走。",
            "Sometimes it settles all the way down — sits, rolls belly-up for a while, then gets up and walks on.",
        ])
        section("🥰 摸肚子 Belly Rubs", [
            "小狗躺平 3 秒后会撒娇：「摸摸我吧～」或「陪我玩一会儿吧～」。",
            "After lying belly-up for 3 seconds it asks: \"摸摸我吧～\" or \"陪我玩一会儿吧～\".",
            "把鼠标放在它身上来回滑动就是在摸它——它会跟着你的手扭来扭去。",
            "Stroke your mouse back and forth over its belly — it wriggles along with each stroke.",
            "被摸的时候它绝对不会起来；你停下来，它才心满意足地爬起来继续散步。",
            "It won't get up while being petted; stop, and it happily gets up and walks on.",
        ])
        section("🖱️ 基本操作 Basic Controls", [
            "单击小狗：暂停 / 继续走动。暂停时头上出现 ✕，点 ✕ 退出程序。",
            "Click the dog: pause / resume. While paused an ✕ appears above it — click the ✕ to quit the app.",
            "拖拽小狗：拎到任何地方，松手后它会掉回地面。",
            "Drag the dog anywhere — let go and it falls back to the ground.",
            "暂停状态下拖到哪里它就停在哪里，像贴纸一样。",
            "A paused dog stays wherever you drop it, like a sticker.",
        ])
        section("⬆️ 窗户上散步 Window-Edge Walk", [
            "把小狗放到任意窗口的上边缘松手，它会站上去，在窗口顶上散步、休息。",
            "Drop the dog on the top edge of any app window — it perches there and walks, rests, and plays along it.",
            "窗口移动时它会跟着走；窗口关掉了它就跳下来。",
            "It rides along when the window moves, and hops off if the window closes.",
            "把它拖走松手，它就落回屏幕底部继续正常散步。",
            "Drag it away and it falls back to the bottom of the screen.",
        ])
        section("📏 大小与速度 Size & Speed", [
            "在「自定义」页用两个滑块调整小狗的大小和走路速度，立即生效。",
            "Use the two sliders in the 自定义 Custom tab to adjust the dog's size and walking speed — changes apply instantly.",
        ])
        section("😴 睡觉 Sleep Mode", [
            "把小狗拖出屏幕边缘再松手，它会蜷起来睡觉（自动缩回来一点，方便点到）。",
            "Drag it past a screen edge and let go — it curls up to sleep, tucked back so you can still reach it.",
            "睡觉时它一动不动，可以随便拖放；双击叫醒它。",
            "A sleeping dog stays put and can be dragged anywhere; double-click it to wake it up.",
        ])
        section("🗑️ 吃掉文件 Trash Bin", [
            "把不要的文件拖到小狗身上，它会张嘴吃掉——文件被移到废纸篓（可恢复）。",
            "Drag unwanted files onto the dog — it gobbles them into the Trash (recoverable, not deleted).",
            "第一次喂桌面 / 文稿 / 下载里的文件时，macOS 可能会请求文件夹权限，点允许即可。",
            "The first time you feed it files from Desktop/Documents/Downloads, macOS may ask for folder access — click Allow.",
        ])
        section("💧 内置提醒 Built-in Reminders", [
            "喝水：每隔一段时间提醒一次（只在你用电脑时）。",
            "Water: every N minutes, only while you're actively at the computer.",
            "散步：连续工作一段时间后提醒；离开电脑 5 分钟以上，计时自动重置。",
            "Walk: after continuous work; stepping away 5+ minutes resets the timer.",
            "午饭 / 晚饭：每天固定时间提醒一次。",
            "Lunch / Dinner: once a day at the set time.",
            "气泡点一下就消失，不点 18 秒后也会自动消失。",
            "Click a bubble to dismiss it; it auto-hides after 18 seconds.",
            "在「提醒」页修改时间和提醒文字（留空则用默认双语文案）。",
            "Edit times and message texts in the 提醒 Reminders tab (blank = default message).",
        ])
        section("✏️ 自定义提醒 Custom Reminders", [
            "在「自定义」页输入内容，选 Every（每隔几分钟）或 Daily at（每天几点），点 Add。",
            "In the 自定义 Custom tab, type a message, pick Every N minutes or Daily at a time, then click Add.",
            "勾选框开关提醒，点 ✕ 删除。",
            "Toggle each one with its checkbox; remove it with the ✕.",
        ])
        section("🐾 菜单栏 Menu Bar", [
            "屏幕右上角的 🐾 图标：打开设置、开关提醒、测试提醒、召回小狗（Drop From Top）、退出。",
            "The 🐾 icon in the menu bar: settings, reminders on/off, test a reminder, recall the dog, and quit.",
        ])
        section("⚙️ 其他 Misc", [
            "右键点小狗，随时打开这个设置窗口。",
            "Right-click the dog anytime to open this settings window.",
            "程序会在开机登录时自动启动（可在本页开关）。",
            "The app starts automatically when you log in (toggle above).",
        ])

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(manual)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 460).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        DispatchQueue.main.async {  // after layout, start at the top
            textView.scroll(.zero)
        }
        return scroll
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true
        return box
    }

    private func hRow(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.spacing = 6
        return r
    }

    private func makeMessageField() -> NSTextField {
        let f = NSTextField(string: "")
        f.placeholderString = "自定义提醒文字（留空用默认） / Custom message (blank = default)"
        f.font = NSFont.systemFont(ofSize: 12)
        f.widthAnchor.constraint(equalToConstant: 330).isActive = true
        f.target = self
        f.action = #selector(uiChanged)
        (f.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        return f
    }

    private func rebuildCustomList() {
        for v in customListStack.arrangedSubviews {
            customListStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let reminders = Settings.shared.customReminders
        if reminders.isEmpty {
            let empty = NSTextField(labelWithString: "No custom reminders yet — add one below.")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            customListStack.addArrangedSubview(empty)
        }
        for (i, r) in reminders.enumerated() {
            let title = r.isDaily ? "\(r.text) — daily at \(formatTime(r.minutes))"
                                  : "\(r.text) — every \(r.minutes) min"
            let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(customToggled(_:)))
            check.state = r.enabled ? .on : .off
            check.tag = i
            let del = NSButton(title: "✕", target: self, action: #selector(customDeleted(_:)))
            del.tag = i
            del.controlSize = .small
            del.bezelStyle = .rounded
            customListStack.addArrangedSubview(hRow([check, del]))
        }
    }

    private func relayout() {
        guard let win = window else { return }
        let stacks = [remindersTabStack, customTabStack, generalTabStack].compactMap { $0 }
        let w = stacks.map { $0.fittingSize.width }.max() ?? 420
        let h = stacks.map { $0.fittingSize.height }.max() ?? 320
        win.setContentSize(NSSize(width: w + 24, height: h + 64))  // room for the tab bar
    }

    @objc private func sizeChanged() {
        Settings.shared.petScale = sizeSlider.doubleValue
        sizeValueLabel.stringValue = String(format: "%.1f×", sizeSlider.doubleValue)
        controller?.applyScale()
    }

    @objc private func speedChanged() {
        Settings.shared.petSpeed = speedSlider.doubleValue
        speedValueLabel.stringValue = String(format: "%.1f×", speedSlider.doubleValue)
    }

    @objc private func newTypeChanged() {
        let daily = newTypePopup.indexOfSelectedItem == 1
        newMinutesField.isHidden = daily
        newMinutesStepper.isHidden = daily
        newMinutesLabel.isHidden = daily
        newTimePicker.isHidden = !daily
        relayout()
    }

    @objc private func newMinutesFieldChanged() {
        let v = clampMinutes(newMinutesField.integerValue)
        newMinutesField.integerValue = v
        newMinutesStepper.integerValue = v
    }

    @objc private func newMinutesStepperChanged() {
        newMinutesField.integerValue = newMinutesStepper.integerValue
    }

    @objc private func addCustomReminder() {
        let text = newReminderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        let daily = newTypePopup.indexOfSelectedItem == 1
        let minutes = daily ? minutesOfDay(newTimePicker.dateValue)
                            : clampMinutes(newMinutesField.integerValue)
        var arr = Settings.shared.customReminders
        arr.append(CustomReminder(text: text, isDaily: daily, minutes: minutes))
        Settings.shared.customReminders = arr
        newReminderField.stringValue = ""
        rebuildCustomList()
        relayout()
    }

    @objc private func customToggled(_ sender: NSButton) {
        var arr = Settings.shared.customReminders
        guard sender.tag < arr.count else { return }
        arr[sender.tag].enabled = sender.state == .on
        Settings.shared.customReminders = arr
    }

    @objc private func customDeleted(_ sender: NSButton) {
        var arr = Settings.shared.customReminders
        guard sender.tag < arr.count else { return }
        arr.remove(at: sender.tag)
        Settings.shared.customReminders = arr
        rebuildCustomList()
        relayout()
    }

    private func makeMinutesControls(value: Int, fieldAction: Selector, stepperAction: Selector) -> (NSTextField, NSStepper) {
        let field = NSTextField(string: "\(value)")
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
        field.target = self
        field.action = fieldAction
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        let stepper = NSStepper()
        stepper.minValue = 5
        stepper.maxValue = 240
        stepper.increment = 5
        stepper.integerValue = value
        stepper.target = self
        stepper.action = stepperAction
        return (field, stepper)
    }

    private func makeTimePicker(minutes: Int) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                                 second: 0, of: Date()) ?? Date()
        picker.target = self
        picker.action = #selector(uiChanged)
        return picker
    }

    private func refresh() {
        let s = Settings.shared
        masterCheck.state = s.remindersEnabled ? .on : .off
        waterCheck.state = s.waterEnabled ? .on : .off
        waterField.integerValue = s.waterMinutes
        waterStepper.integerValue = s.waterMinutes
        walkCheck.state = s.walkEnabled ? .on : .off
        walkField.integerValue = s.walkMinutes
        walkStepper.integerValue = s.walkMinutes
        lunchCheck.state = s.lunchEnabled ? .on : .off
        dinnerCheck.state = s.dinnerEnabled ? .on : .off
        waterMsgField.stringValue = s.waterText
        walkMsgField.stringValue = s.walkText
        lunchMsgField.stringValue = s.lunchText
        dinnerMsgField.stringValue = s.dinnerText
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        sizeSlider.doubleValue = s.petScale
        sizeValueLabel.stringValue = String(format: "%.1f×", s.petScale)
        speedSlider.doubleValue = s.petSpeed
        speedValueLabel.stringValue = String(format: "%.1f×", s.petSpeed)
        rebuildCustomList()
        relayout()
        updateEnabledStates()
    }

    private func updateEnabledStates() {
        let master = masterCheck.state == .on
        for check in [waterCheck, walkCheck, lunchCheck, dinnerCheck] {
            check?.isEnabled = master
        }
        waterField.isEnabled = master && waterCheck.state == .on
        waterStepper.isEnabled = master && waterCheck.state == .on
        waterMsgField.isEnabled = master && waterCheck.state == .on
        walkField.isEnabled = master && walkCheck.state == .on
        walkStepper.isEnabled = master && walkCheck.state == .on
        walkMsgField.isEnabled = master && walkCheck.state == .on
        lunchPicker.isEnabled = master && lunchCheck.state == .on
        lunchMsgField.isEnabled = master && lunchCheck.state == .on
        dinnerPicker.isEnabled = master && dinnerCheck.state == .on
        dinnerMsgField.isEnabled = master && dinnerCheck.state == .on
    }

    private func clampMinutes(_ v: Int) -> Int { max(5, min(240, v)) }

    @objc private func waterFieldChanged() {
        let v = clampMinutes(waterField.integerValue)
        waterField.integerValue = v
        waterStepper.integerValue = v
        uiChanged()
    }
    @objc private func waterStepperChanged() {
        waterField.integerValue = waterStepper.integerValue
        uiChanged()
    }
    @objc private func walkFieldChanged() {
        let v = clampMinutes(walkField.integerValue)
        walkField.integerValue = v
        walkStepper.integerValue = v
        uiChanged()
    }
    @objc private func walkStepperChanged() {
        walkField.integerValue = walkStepper.integerValue
        uiChanged()
    }

    @objc private func uiChanged() {
        let s = Settings.shared
        s.remindersEnabled = masterCheck.state == .on
        s.waterEnabled = waterCheck.state == .on
        s.waterMinutes = clampMinutes(waterField.integerValue)
        s.walkEnabled = walkCheck.state == .on
        s.walkMinutes = clampMinutes(walkField.integerValue)
        s.lunchEnabled = lunchCheck.state == .on
        s.lunchMinutes = minutesOfDay(lunchPicker.dateValue)
        s.dinnerEnabled = dinnerCheck.state == .on
        s.dinnerMinutes = minutesOfDay(dinnerPicker.dateValue)
        s.waterText = waterMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.walkText = walkMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.lunchText = lunchMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.dinnerText = dinnerMsgField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.remindersEnabled { controller?.hideBubble() }
        controller?.syncRemindersMenuState()
        updateEnabledStates()
    }

    @objc private func loginToggled() {
        let wantIt = loginCheck.state == .on
        Settings.shared.loginItemDesired = wantIt
        do {
            if wantIt {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 12) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Controller (animation state machine + reminders)

final class PetController: NSObject, NSApplicationDelegate {
    enum State { case walking, idle, airborne, dragged, paused, sleeping }

    let basePetSize = NSSize(width: 130, height: 114)
    let baseWindowSize = NSSize(width: 144, height: 142)  // room for the ✕ above the pet
    var petScale: CGFloat { CGFloat(Settings.shared.petScale) }
    var petSize: NSSize {
        NSSize(width: basePetSize.width * petScale, height: basePetSize.height * petScale)
    }
    var windowSize: NSSize {
        NSSize(width: baseWindowSize.width * petScale, height: baseWindowSize.height * petScale)
    }
    var walkSpeed: CGFloat { 2.0 * CGFloat(Settings.shared.petSpeed) }
    let gravity: CGFloat = 0.55
    let jumpVelocity: CGFloat = 9.5
    struct Perch {
        var windowID: UInt32
        var edgeY: CGFloat   // AppKit y of the host window's top edge
        var minX: CGFloat
        var maxX: CGFloat
    }
    var perch: Perch?            // perched on another app window's top edge
    private var perchRefreshTick = 0

    var window: NSWindow!
    var petView: PetView!
    var statusItem: NSStatusItem!
    var animationTimer: Timer!
    var reminderTimer: Timer!
    var remindersMenuItem: NSMenuItem!
    lazy var settingsController = SettingsWindowController(controller: self)

    var state: State = .airborne
    var fileDragActive = false
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var direction: CGFloat = -1
    var phase: CGFloat = 0
    var stateTime: CGFloat = 0
    var stateDuration: CGFloat = 0
    var idleSettles = false      // this idle plays the stand→sit→lie sequence
    var sitImage: NSImage?
    var lieImage: NSImage?
    var lie2Image: NSImage?      // alternate belly-up frame for petting strokes
    var lastPetMoveAt = Date.distantPast
    var inviteShownThisIdle = false
    var inviteActive = false     // the current bubble is a "pet me" invite

    // reminders
    let launchTime = Date()
    var workSeconds: Double = 0
    var lastWaterAt = Date()
    var mealFiredDay: [String: Int] = [:]
    var customFiredDay: [UUID: Int] = [:]
    var customLastFired: [UUID: Date] = [:]
    var bubbleImage: NSImage?
    var bubbleWindow: NSWindow?
    var bubbleHideTask: DispatchWorkItem?

    var screenArea: NSRect {
        (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frames = loadFrames()
        guard !frames.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "MacPet"
            alert.informativeText = "Could not load pet0.png/pet1.png (expected in the app's Resources folder or next to the executable)."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        petView = PetView(frame: NSRect(origin: .zero, size: windowSize))
        petView.petSize = petSize
        petView.frames = frames
        petView.controller = self
        petView.eatImage = loadImage(named: "pet_eat")
        petView.sleepImage = loadImage(named: "pet_sleep")
        sitImage = loadImage(named: "pet_sit")
        lieImage = loadImage(named: "pet_lie")
        lie2Image = loadImage(named: "pet_lie2")
        petView.registerForDraggedTypes([.fileURL])
        bubbleImage = loadImage(named: "bubble")

        window = makeTransparentWindow(size: windowSize)
        window.contentView = petView

        let area = screenArea
        x = area.midX - windowSize.width / 2
        y = area.maxY - windowSize.height - 10
        state = .airborne
        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.orderFrontRegardless()

        setUpStatusItem()
        registerLoginItemIfWanted()

        animationTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        reminderTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkReminders()
        }
        RunLoop.main.add(reminderTimer, forMode: .common)

        let env = ProcessInfo.processInfo.environment
        if env["MACPET_TEST_REMINDER"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.testReminder()
            }
        }
        if let which = env["MACPET_TEST_SETTINGS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showSettings()
                if let i = Int(which) { self?.settingsController.selectTab(i) }
            }
        }
        if env["MACPET_TEST_IDLE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.stateTime = 0
                self.idleSettles = true
                self.inviteShownThisIdle = false
                self.stateDuration = 14
            }
        }
        if env["MACPET_TEST_SLEEP"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.enterSleep()
            }
        }
        if env["MACPET_TEST_EAT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.petView.isEating = true
                self?.fileDragActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self?.petView.isEating = false
                    self?.fileDragActive = false
                }
            }
        }
    }

    func registerLoginItemIfWanted() {
        guard Settings.shared.loginItemDesired else { return }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    func makeTransparentWindow(size: NSSize) -> NSWindow {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: .borderless,
                           backing: .buffered,
                           defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        return win
    }

    func loadImage(named name: String, ext: String = "png") -> NSImage? {
        if let path = Bundle.main.path(forResource: name, ofType: ext),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        let exeDir = (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent
        if let dir = exeDir, let img = NSImage(contentsOfFile: dir + "/\(name).\(ext)") {
            return img
        }
        return nil
    }

    func loadFrames() -> [NSImage] {
        // 0 = standing, 1 = leap
        var frames: [NSImage] = []
        for name in ["pet0", "pet1"] {
            guard let img = loadImage(named: name) else { break }  // frames must be contiguous
            frames.append(img)
        }
        if frames.isEmpty, let img = loadImage(named: "pet", ext: "svg") {
            frames.append(img)  // single-pose fallback
        }
        return frames
    }

    func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()

        let settings = NSMenuItem(title: "Reminder Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        remindersMenuItem = NSMenuItem(title: "Enable Reminders", action: #selector(toggleReminders), keyEquivalent: "")
        remindersMenuItem.target = self
        remindersMenuItem.state = Settings.shared.remindersEnabled ? .on : .off
        menu.addItem(remindersMenuItem)

        let test = NSMenuItem(title: "Test Reminder", action: #selector(testReminder), keyEquivalent: "t")
        test.target = self
        menu.addItem(test)

        menu.addItem(NSMenuItem.separator())
        let reset = NSMenuItem(title: "Drop From Top", action: #selector(resetPosition), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(NSMenuItem(title: "Quit MacPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func showSettings() {
        settingsController.show()
    }

    @objc func toggleReminders() {
        Settings.shared.remindersEnabled.toggle()
        syncRemindersMenuState()
        settingsController.refreshIfVisible()
        if !Settings.shared.remindersEnabled { hideBubble() }
    }

    func syncRemindersMenuState() {
        remindersMenuItem.state = Settings.shared.remindersEnabled ? .on : .off
    }

    @objc func testReminder() {
        deliver(reminder: reminderText(Settings.shared.waterText, Config.waterMessages))
    }

    @objc func resetPosition() {
        let area = screenArea
        x = area.midX - windowSize.width / 2
        y = area.maxY - windowSize.height - 10
        vx = 0; vy = 0
        state = .airborne
        perch = nil
        petView.showsCloseButton = false
        petView.isSleeping = false  // emergency recall also wakes it
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: physics / behavior, 60 fps

    func tick() {
        if fileDragActive {
            positionBubble()
            return  // hold still with mouth open, ready to chomp
        }
        if perch != nil { refreshPerchIfNeeded() }
        let area = screenArea
        let ground = perch?.edgeY ?? area.minY
        var minX = area.minX
        var maxX = area.maxX - windowSize.width
        if let p = perch {
            // walk only along the host window's top edge
            minX = max(minX, p.minX - windowSize.width / 2)
            maxX = min(maxX, p.maxX - windowSize.width / 2)
            if minX > maxX { minX = maxX }
        }
        var bob: CGFloat = 0
        stateTime += 1.0 / 60.0

        switch state {
        case .dragged, .paused, .sleeping:
            // window may be moved by the mouse; keep physics in sync, don't fight it
            x = window.frame.origin.x
            y = window.frame.origin.y
            petView.poseOverride = nil
            petView.frameIndex = state == .dragged ? 1 : 0  // dangle vs stand
            positionBubble()
            return

        case .walking:
            petView.poseOverride = nil
            y = ground  // tracks scale changes and the top-edge perch line
            x += walkSpeed * direction
            phase += 0.22
            bob = abs(sin(phase)) * 5
            petView.frameIndex = sin(phase) >= 0 ? 0 : 1    // step cycle
            if x <= minX { x = minX; direction = 1 }
            if x >= maxX { x = maxX; direction = -1 }

            let roll = CGFloat.random(in: 0..<1)
            if roll < 0.003 {
                state = .idle
                stateTime = 0
                // half the time just stand; half the time settle down for a proper rest
                if sitImage != nil && lieImage != nil && CGFloat.random(in: 0..<1) < 0.5 {
                    idleSettles = true
                    inviteShownThisIdle = false
                    stateDuration = CGFloat.random(in: 9...16)
                } else {
                    idleSettles = false
                    stateDuration = CGFloat.random(in: 1.5...4.0)
                }
            } else if roll < 0.005 {
                state = .airborne
                vy = jumpVelocity
                vx = direction * walkSpeed * 1.8
            }

        case .idle:
            petView.frameIndex = 0
            y = ground  // ride along if the host window moves
            if idleSettles {
                // stand → sit → lie belly-up → sit → stand
                let t = stateTime, d = stateDuration
                if t < 0.8 || t > d - 0.8 {
                    petView.poseOverride = nil              // standing
                    bob = sin(phase) * 1.5
                } else if t < 2.4 || t > d - 2.4 {
                    petView.poseOverride = sitImage         // sitting
                } else {
                    // lying belly-up — the petting zone
                    let petting = Date().timeIntervalSince(lastPetMoveAt) < 0.6
                    if petting {
                        // enjoy the belly rubs: don't get up while being petted
                        stateTime = min(stateTime, d - 2.45)
                        // pose is set by hoverMoved() per stroke direction
                    } else {
                        petView.poseOverride = lieImage
                        if !inviteShownThisIdle, t >= 2.4 + 3.0 {
                            inviteShownThisIdle = true
                            showBubble(["摸摸我吧～", "陪我玩一会儿吧～"].randomElement()!, hideAfter: 8)
                            inviteActive = true
                            NSSound(named: "Purr")?.play()
                        }
                    }
                }
            } else {
                petView.poseOverride = nil                  // just stand still
                bob = sin(phase) * 1.5
            }
            phase += 0.05
            if stateTime >= stateDuration {
                petView.poseOverride = nil
                if CGFloat.random(in: 0..<1) < 0.4 { direction = -direction }
                state = .walking
            }

        case .airborne:
            petView.poseOverride = nil
            petView.frameIndex = 1                          // leap pose
            vy -= gravity
            y += vy
            x += vx
            if x <= minX { x = minX; vx = abs(vx) * 0.5 }
            if x >= maxX { x = maxX; vx = -abs(vx) * 0.5 }
            if y <= ground {
                y = ground
                vy = 0
                vx = 0
                state = .walking
            }
        }

        petView.facingRight = direction > 0
        window.setFrameOrigin(NSPoint(x: x, y: y + bob))
        positionBubble()
    }

    // MARK: click / drag

    func handleClick(at point: NSPoint, clickCount: Int) {
        if state == .sleeping {
            if clickCount >= 2 { wakeUp() }  // single clicks don't disturb sleep
            return
        }
        if petView.showsCloseButton,
           petView.closeButtonRect.insetBy(dx: -6, dy: -6).contains(point) {
            NSApp.terminate(nil)
            return
        }
        togglePaused()
    }

    func enterSleep() {
        state = .sleeping
        perch = nil  // sleeping pets stay exactly where they're put
        petView.isSleeping = true
        petView.showsCloseButton = false
        clampSleepingPosition()
    }

    /// Tuck the sleeping pet back so enough of it stays on screen to double-click.
    func clampSleepingPosition() {
        let area = screenArea
        let f = window.frame
        let minVisible: CGFloat = 80
        let nx = max(area.minX - (f.width - minVisible), min(f.origin.x, area.maxX - minVisible))
        let ny = max(area.minY - (f.height - minVisible), min(f.origin.y, area.maxY - minVisible))
        x = nx; y = ny
        window.setFrameOrigin(NSPoint(x: nx, y: ny))
    }

    func wakeUp() {
        petView.isSleeping = false
        x = window.frame.origin.x
        y = window.frame.origin.y
        vx = 0; vy = 0
        state = .airborne  // stretches, falls back to its ground, walks on
    }

    /// Apply the size slider: resize the window around the pet's current spot.
    func applyScale() {
        let area = screenArea
        let old = window.frame
        let newSize = windowSize
        var nx = old.midX - newSize.width / 2
        nx = max(area.minX, min(nx, area.maxX - newSize.width))
        var ny = old.origin.y
        if let p = perch {
            ny = p.edgeY
        } else if state == .walking || state == .idle {
            ny = area.minY
        }
        window.setFrame(NSRect(x: nx, y: ny, width: newSize.width, height: newSize.height),
                        display: true)
        petView.petSize = petSize
        petView.needsDisplay = true
        x = nx
        y = ny
    }

    func togglePaused() {
        if state == .paused {
            petView.showsCloseButton = false
            x = window.frame.origin.x
            y = window.frame.origin.y
            vx = 0; vy = 0
            state = .airborne  // falls back down if frozen mid-air
        } else {
            state = .paused
            petView.showsCloseButton = true
        }
    }

    func beginDrag() {
        if state != .paused && state != .sleeping { state = .dragged }
    }

    func endDrag() {
        x = window.frame.origin.x
        y = window.frame.origin.y
        vx = 0; vy = 0
        if state == .sleeping {
            clampSleepingPosition()  // keep it reachable for the wake-up double-click
            return
        }
        // dropped (partly) beyond the screen edge? time for a nap —
        // this applies even to a paused pet, so it can never be stranded off-screen
        let area = screenArea
        let f = window.frame
        if f.minX < area.minX - 25 || f.maxX > area.maxX + 25 ||
           f.minY < area.minY - 25 || f.maxY > area.maxY + 25 {
            enterSleep()
            return
        }
        if state == .paused { return }  // stays where you put it (on screen)
        if let target = findPerch() {
            // dropped on the top edge of an app window: perch and walk there
            perch = target
            y = target.edgeY
            window.setFrameOrigin(NSPoint(x: x, y: y))
            state = .walking
        } else {
            perch = nil  // dragged away from any edge: back to the floor
            state = .airborne
        }
    }

    // MARK: window-edge perching

    func visibleWindowEdges() -> [Perch] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        var edges: [Perch] = []
        for info in list {  // ordered front to back
            guard (info[kCGWindowLayer as String] as? Int) == 0,           // normal windows only
                  (info[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.1,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict),
                  rect.width >= 200, rect.height >= 80,
                  let wid = info[kCGWindowNumber as String] as? UInt32
            else { continue }
            edges.append(Perch(windowID: wid,
                               edgeY: screenTop - rect.minY,  // CG y counts down from screen top
                               minX: rect.minX,
                               maxX: rect.maxX))
        }
        return edges
    }

    func findPerch() -> Perch? {
        let petBottom = window.frame.minY
        let petMidX = window.frame.midX
        let area = screenArea
        for t in visibleWindowEdges() {  // frontmost window wins
            guard petMidX >= t.minX - 10, petMidX <= t.maxX + 10,
                  abs(petBottom - t.edgeY) <= 35,
                  t.edgeY > area.minY + 10, t.edgeY < area.maxY - 10
            else { continue }
            return t
        }
        return nil
    }

    /// Re-check the host window ~6×/s: follow it if it moves, hop off if it's gone.
    func refreshPerchIfNeeded() {
        perchRefreshTick += 1
        guard perchRefreshTick >= 10 else { return }
        perchRefreshTick = 0
        guard let current = perch else { return }
        if let updated = visibleWindowEdges().first(where: { $0.windowID == current.windowID }),
           updated.edgeY > screenArea.minY + 10, updated.edgeY < screenArea.maxY - 10 {
            perch = updated
        } else {
            // host window closed, minimized, or left the screen — hop off
            perch = nil
            if state == .walking || state == .idle {
                petView.poseOverride = nil
                vy = 0; vx = 0
                state = .airborne
            }
        }
    }

    // MARK: reminders (checked once per second)

    func checkReminders() {
        let s = Settings.shared
        guard s.remindersEnabled else { return }

        let idle = systemIdleSeconds()
        let active = idle < 120

        // walk break: count continuous work, reset when she steps away
        if idle > Config.idleResetSeconds {
            workSeconds = 0
        } else if idle < 60 {
            workSeconds += 1
        }
        if s.walkEnabled && active && workSeconds >= Double(s.walkMinutes) * 60 {
            workSeconds = 0
            deliver(reminder: reminderText(s.walkText, Config.walkMessages))
            return
        }

        // water: only when she's actually at the computer
        if s.waterEnabled && active && Date().timeIntervalSince(lastWaterAt) >= Double(s.waterMinutes) * 60 {
            lastWaterAt = Date()
            deliver(reminder: reminderText(s.waterText, Config.waterMessages))
            return
        }

        // meals: fire once per day inside the meal window
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let hour = comps.hour, let minute = comps.minute,
              let day = Calendar.current.ordinality(of: .day, in: .year, for: now) else { return }
        let nowMinutes = hour * 60 + minute

        func meal(_ key: String, enabled: Bool, target: Int, custom: String, messages: [String]) {
            guard enabled, nowMinutes >= target, nowMinutes < target + Config.mealWindowMinutes,
                  mealFiredDay[key] != day else { return }
            mealFiredDay[key] = day
            deliver(reminder: reminderText(custom, messages))
        }
        meal("lunch", enabled: s.lunchEnabled, target: s.lunchMinutes,
             custom: s.lunchText, messages: Config.lunchMessages)
        meal("dinner", enabled: s.dinnerEnabled, target: s.dinnerMinutes,
             custom: s.dinnerText, messages: Config.dinnerMessages)

        // user-defined reminders
        for r in s.customReminders where r.enabled {
            if r.isDaily {
                if nowMinutes >= r.minutes, nowMinutes < r.minutes + Config.mealWindowMinutes,
                   customFiredDay[r.id] != day {
                    customFiredDay[r.id] = day
                    deliver(reminder: r.text)
                }
            } else if active {
                let last = customLastFired[r.id] ?? launchTime
                if Date().timeIntervalSince(last) >= Double(r.minutes) * 60 {
                    customLastFired[r.id] = Date()
                    deliver(reminder: r.text)
                }
            }
        }
    }

    // MARK: petting (mouse strokes over the lying dog)

    func hoverMoved(deltaX: CGFloat) {
        guard state == .idle, idleSettles, let lie = lieImage,
              stateTime >= 2.4, stateTime <= stateDuration - 2.4 else { return }
        lastPetMoveAt = Date()
        if inviteActive {   // she came to pet — invite accomplished
            hideBubble()
            inviteActive = false
        }
        if abs(deltaX) >= 1 {
            // each stroke direction shows its own belly-up frame
            petView.poseOverride = deltaX > 0 ? (lie2Image ?? lie) : lie
        }
    }

    // MARK: trash bin

    func trash(_ urls: [URL]) {
        var trashedNames: [String] = []
        var failed = 0
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashedNames.append(url.lastPathComponent)
            } catch {
                failed += 1
            }
        }
        if !trashedNames.isEmpty {
            NSSound(named: "Pop")?.play()
            let what = trashedNames.count == 1 ? trashedNames[0] : "\(trashedNames.count) items"
            var msg = "🗑️ 咔嚓～吃掉啦！\n\(what) → Trash"
            if failed > 0 { msg += "\n(\(failed) couldn't be trashed)" }
            showBubble(msg)
            if state == .walking || state == .idle {  // happy hop
                state = .airborne
                vy = jumpVelocity
                vx = 0
            }
        } else {
            NSSound.beep()
            showBubble("😿 这个吃不下去…\nCouldn't move that to Trash")
        }
    }

    func reminderText(_ custom: String, _ defaults: [String]) -> String {
        custom.isEmpty ? defaults.randomElement()! : custom
    }

    func systemIdleSeconds() -> Double {
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func deliver(reminder text: String) {
        showBubble(text)
        NSSound(named: "Glass")?.play()
        if state == .walking || state == .idle {
            state = .airborne          // attention hop
            vy = jumpVelocity * 0.85
            vx = 0
        }
    }

    // MARK: speech bubble

    func showBubble(_ text: String, hideAfter: Double = Config.bubbleSeconds) {
        hideBubble()
        inviteActive = false
        let attrs: [NSAttributedString.Key: Any] = [.font: BubbleView.font]
        let bound = (text as NSString).boundingRect(
            with: NSSize(width: 230, height: 600),
            options: [.usesLineFragmentOrigin],
            attributes: attrs)
        let tailH = bubbleImage == nil ? BubbleView.drawnTailHeight : BubbleView.imageTailHeight
        let size = NSSize(width: max(ceil(bound.width) + 32, 110),
                          height: ceil(bound.height) + 26 + tailH)

        let view = BubbleView(frame: NSRect(origin: .zero, size: size))
        view.image = bubbleImage
        view.text = text
        view.onDismiss = { [weak self] in self?.hideBubble() }

        let win = makeTransparentWindow(size: size)
        win.contentView = view
        bubbleWindow = win
        positionBubble()
        win.orderFrontRegardless()

        let task = DispatchWorkItem { [weak self] in self?.hideBubble() }
        bubbleHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: task)
    }

    func hideBubble() {
        bubbleHideTask?.cancel()
        bubbleHideTask = nil
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }

    func positionBubble() {
        guard let bubble = bubbleWindow else { return }
        let pf = window.frame
        let area = screenArea
        // pixel bubble's tail is near its left edge; point it at the pet
        var bx = bubbleImage == nil ? pf.midX - bubble.frame.width / 2
                                    : pf.midX - BubbleView.imageTailCenterX
        bx = max(area.minX + 4, min(bx, area.maxX - bubble.frame.width - 4))
        let by = min(pf.maxY - 14, area.maxY - bubble.frame.height)
        bubble.setFrameOrigin(NSPoint(x: bx, y: by))
    }
}

// MARK: - entry point

let app = NSApplication.shared
let controller = PetController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
