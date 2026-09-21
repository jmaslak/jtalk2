// The main jtalk2 window: the message box, the voice pop-up and the speed
// slider.

import AppKit
import AVFoundation

// MARK: - Text view

final class TalkTextView: NSTextView {
    var onSpeak: (() -> Void)?
    var onCancel: (() -> Void)?
    var onKeyDown: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        onKeyDown?()
        super.keyDown(with: event)
    }

    /// Return speaks. Shift-Return inserts a line break instead.
    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            super.insertNewline(sender)
        } else {
            onSpeak?()
        }
    }

    /// Option-Return also inserts a line break.
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        super.insertNewline(sender)
    }

    /// Esc cancels speech rather than opening the completion list.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - Controller

final class TalkWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private static let voiceKey = "VoiceIdentifier"
    private static let rateKey = "SpeechRate"
    private static let fontSizeKey = "FontSize"
    private static let keyClickKey = "KeyClick"
    private static let textColorKey = "TextColor"
    private static let backgroundColorKey = "BackgroundColor"

    private let speaker = Speaker()
    private let window: NSWindow
    private let textView = TalkTextView(frame: .zero)
    private let voicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rateSlider = NSSlider()
    private let scrollView = NSScrollView()
    private let clicker = KeyClicker()
    let pronunciations: PronunciationStore
    private lazy var pronunciationWindow = PronunciationWindow(store: pronunciations)

    /// The text in the message box. The setter exists for tests.
    var message: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    /// What is highlighted in the message box.
    var highlightedRange: NSRange { textView.selectedRange() }

    init(pronunciations: PronunciationStore = PronunciationStore()) {
        self.pronunciations = pronunciations
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        super.init()

        window.title = "JTalk2"
        window.delegate = self
        window.setFrameAutosaveName("TalkWindow")
        window.contentView = buildContentView()
        window.minSize = NSSize(width: 360, height: 180)

        speaker.onFinish = { [weak self] in self?.selectAll() }

        buildVoiceMenu()
        if keyClickEnabled {
            clicker.prepare()
        }
        window.makeFirstResponder(textView)
    }

    func show() {
        window.center()
        window.setFrameUsingName("TalkWindow")
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let root = NSView()

        voicePopUp.translatesAutoresizingMaskIntoConstraints = false
        voicePopUp.target = self
        voicePopUp.action = #selector(voiceChanged)
        voicePopUp.toolTip = "Voice"
        voicePopUp.setAccessibilityLabel("Voice")

        rateSlider.translatesAutoresizingMaskIntoConstraints = false
        rateSlider.minValue = Double(Self.slowestRate)
        rateSlider.maxValue = Double(AVSpeechUtteranceMaximumSpeechRate)
        rateSlider.doubleValue = Double(Self.savedRate)
        rateSlider.isContinuous = true
        rateSlider.target = self
        rateSlider.action = #selector(rateChanged)
        rateSlider.toolTip = "Speaking speed"
        rateSlider.setAccessibilityLabel("Speed")

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: Self.savedFontSize)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.setAccessibilityLabel("Message")
        textView.onSpeak = { [weak self] in self?.speak() }
        textView.onCancel = { [weak self] in self?.stop() }
        textView.onKeyDown = { [weak self] in
            guard let self, self.keyClickEnabled else { return }
            self.clicker.click()
        }

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize =
            NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = scrollView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView

        applyColors(text: Self.savedColor(Self.textColorKey) ?? .textColor,
                    background: Self.savedColor(Self.backgroundColorKey) ?? .textBackgroundColor)

        root.addSubview(voicePopUp)
        root.addSubview(rateSlider)
        root.addSubview(scroll)

        // The voice name is long and the speed slider is not, so let the pop-up
        // give up width first when the window is narrow.
        voicePopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            voicePopUp.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            voicePopUp.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),

            rateSlider.leadingAnchor.constraint(equalTo: voicePopUp.trailingAnchor, constant: 12),
            rateSlider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            rateSlider.centerYAnchor.constraint(equalTo: voicePopUp.centerYAnchor),
            rateSlider.widthAnchor.constraint(equalToConstant: 120),

            scroll.topAnchor.constraint(equalTo: voicePopUp.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
        ])

        return root
    }

    // MARK: Voices

    /// Rebuilt from scratch whenever the available voices change — notably when
    /// Personal Voice access is granted part way through launch.
    func buildVoiceMenu() {
        let groups = Voices.grouped()
        let menu = NSMenu()
        for group in [groups.personal, groups.mine, groups.rest] where !group.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            for voice in group {
                menu.addItem(item(for: voice))
            }
        }
        voicePopUp.menu = menu
        voicePopUp.isEnabled = !menu.items.isEmpty

        let wanted = UserDefaults.standard.string(forKey: Self.voiceKey)
            ?? Voices.systemDefault?.identifier
        if let match = menu.items.first(where: { ($0.representedObject as? AVSpeechSynthesisVoice)?.identifier == wanted }) {
            voicePopUp.select(match)
        }
    }

    private func item(for voice: AVSpeechSynthesisVoice) -> NSMenuItem {
        let item = NSMenuItem(title: Voices.title(voice), action: nil, keyEquivalent: "")
        item.representedObject = voice
        return item
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        voicePopUp.selectedItem?.representedObject as? AVSpeechSynthesisVoice
    }

    @objc private func voiceChanged() {
        guard let voice = selectedVoice else { return }
        UserDefaults.standard.set(voice.identifier, forKey: Self.voiceKey)
        window.makeFirstResponder(textView)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(toggleKeyClick) else { return true }
        menuItem.state = keyClickEnabled ? .on : .off
        return clicker.isAvailable
    }

    // MARK: Key clicks

    /// Whether each keystroke makes a click. Off unless the user turns it on,
    /// and forced off if the click sound could not be loaded.
    var keyClickEnabled: Bool {
        get { clicker.isAvailable && UserDefaults.standard.bool(forKey: Self.keyClickKey) }
        set {
            guard clicker.isAvailable else { return }
            UserDefaults.standard.set(newValue, forKey: Self.keyClickKey)
            if newValue {
                clicker.prepare()
            }
        }
    }

    var keyClickAvailable: Bool { clicker.isAvailable }

    @objc func toggleKeyClick() {
        keyClickEnabled.toggle()
    }

    // MARK: Colors

    /// Color of the text. Setting it saves immediately.
    var textColor: NSColor {
        get { textView.textColor ?? .textColor }
        set {
            applyColors(text: newValue, background: backgroundColor)
            Self.saveColor(newValue, forKey: Self.textColorKey)
        }
    }

    /// Color behind the text. Setting it saves immediately.
    var backgroundColor: NSColor {
        get { textView.backgroundColor }
        set {
            applyColors(text: textColor, background: newValue)
            Self.saveColor(newValue, forKey: Self.backgroundColorKey)
        }
    }

    /// Back to the system colors, which follow light and dark mode.
    @objc func resetColors() {
        UserDefaults.standard.removeObject(forKey: Self.textColorKey)
        UserDefaults.standard.removeObject(forKey: Self.backgroundColorKey)
        applyColors(text: .textColor, background: .textBackgroundColor)
    }

    private func applyColors(text: NSColor, background: NSColor) {
        textView.textColor = text
        textView.backgroundColor = background
        textView.insertionPointColor = text
        scrollView.drawsBackground = true
        scrollView.backgroundColor = background
        // The post-speech highlight has to stay readable whatever pair of colors
        // is chosen, so it is drawn as inverse video rather than the system
        // selection color.
        textView.selectedTextAttributes = [
            .backgroundColor: text,
            .foregroundColor: background,
        ]
    }

    private static func savedColor(_ key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private static func saveColor(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color,
                                                           requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: Color panel

    private enum ColorWell {
        case text
        case background
    }

    private var editingColor: ColorWell?

    @objc func chooseTextColor() { openColorPanel(for: .text) }
    @objc func chooseBackgroundColor() { openColorPanel(for: .background) }

    private func openColorPanel(for well: ColorWell) {
        editingColor = well
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged))
        panel.isContinuous = true
        panel.color = well == .text ? textColor : backgroundColor
        panel.title = well == .text ? "Text Color" : "Background Color"
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        switch editingColor {
        case .text: textColor = panel.color
        case .background: backgroundColor = panel.color
        case nil: break
        }
    }

    // MARK: Font size

    private static let defaultFontSize: CGFloat = 24

    /// The sizes ⌘+ and ⌘- step through. Coarser as they get bigger, so going
    /// from readable to very large does not take twenty keystrokes.
    private static let fontSizes: [CGFloat] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64, 80, 96, 144, 288]

    private static var savedFontSize: CGFloat {
        guard UserDefaults.standard.object(forKey: fontSizeKey) != nil else { return defaultFontSize }
        let saved = CGFloat(UserDefaults.standard.double(forKey: fontSizeKey))
        return min(max(saved, fontSizes.first!), fontSizes.last!)
    }

    /// Point size of the message box. Setting it saves immediately.
    var fontSize: CGFloat {
        get { textView.font?.pointSize ?? Self.defaultFontSize }
        set {
            let size = min(max(newValue, Self.fontSizes.first!), Self.fontSizes.last!)
            textView.font = NSFont.systemFont(ofSize: size)
            UserDefaults.standard.set(Double(size), forKey: Self.fontSizeKey)
        }
    }

    @objc func increaseFontSize() {
        fontSize = Self.fontSizes.first { $0 > fontSize + 0.01 } ?? Self.fontSizes.last!
    }

    @objc func decreaseFontSize() {
        fontSize = Self.fontSizes.last { $0 < fontSize - 0.01 } ?? Self.fontSizes.first!
    }

    @objc func resetFontSize() {
        fontSize = Self.defaultFontSize
    }

    // MARK: Speed

    /// Below this the synthesizer is too sluggish to be useful, so the slider
    /// does not go there even though the API allows 0.
    private static let slowestRate: Float = 0.2

    private static var savedRate: Float {
        guard UserDefaults.standard.object(forKey: rateKey) != nil else {
            return AVSpeechUtteranceDefaultSpeechRate
        }
        return clampRate(UserDefaults.standard.float(forKey: rateKey))
    }

    private static func clampRate(_ rate: Float) -> Float {
        min(max(rate, slowestRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// Speaking speed, as the slider shows it. Setting it saves immediately.
    var rate: Float {
        get { Float(rateSlider.doubleValue) }
        set {
            let rate = Self.clampRate(newValue)
            rateSlider.doubleValue = Double(rate)
            UserDefaults.standard.set(rate, forKey: Self.rateKey)
        }
    }

    /// Back to the synthesizer's own speed, and forget the saved one.
    @objc func resetRate() {
        UserDefaults.standard.removeObject(forKey: Self.rateKey)
        rateSlider.doubleValue = Double(AVSpeechUtteranceDefaultSpeechRate)
    }

    @objc private func rateChanged() {
        UserDefaults.standard.set(Float(rateSlider.doubleValue), forKey: Self.rateKey)
    }

    // MARK: Actions

    @objc func speak() {
        window.makeFirstResponder(textView)
        speaker.speak(pronunciations.apply(to: textView.string), voice: selectedVoice, rate: rate)
    }

    @objc func editPronunciations() {
        pronunciationWindow.show()
    }

    /// Asks for Personal Voice, then re-reads the voice list. `explain` is for
    /// the menu item, where the user asked for it and deserves an answer;
    /// at launch we ask quietly and say nothing if the answer is no.
    func requestPersonalVoice(explainResult explain: Bool) {
        Voices.requestPersonalVoiceAccess { [weak self] access in
            guard let self else { return }
            self.buildVoiceMenu()
            guard explain else { return }

            let alert = NSAlert()
            switch access {
            case .granted where !Voices.grouped().personal.isEmpty:
                alert.messageText = "Personal Voice is available"
                alert.informativeText = "Your Personal Voice is now in the voice menu."
            case .granted:
                alert.messageText = "No Personal Voice found"
                alert.informativeText = "jtalk2 has access, but this Mac has no Personal Voice recorded. "
                    + "You can record one in System Settings ▸ Accessibility ▸ Personal Voice."
            case .denied:
                alert.messageText = "Personal Voice access was refused"
                alert.informativeText = "Turn on System Settings ▸ Accessibility ▸ Personal Voice ▸ "
                    + "Allow Apps to Request to Use, then try again."
            case .unsupported:
                alert.messageText = "Personal Voice is not available on this Mac"
                alert.informativeText = "It needs macOS 14 or later on supported hardware."
            }
            alert.beginSheetModal(for: self.window)
        }
    }

    @objc func askForPersonalVoice() {
        requestPersonalVoice(explainResult: true)
    }

    @objc func stop() {
        speaker.stop()
    }

    /// Highlight every word so the next keystroke replaces the message.
    private func selectAll() {
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
    }
}
