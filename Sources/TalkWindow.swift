// The main jtalk2 window: the message box, the voice pop-up and the speed
// slider.

import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Text view

/// The parts of the font panel jtalk2 accepts. Its colour and effect controls
/// would fight with View ▸ Text Color, which owns the colours here. The panel
/// asks whichever of the first responder and the font manager's target answers
/// first, so both of them do.
private let fontPanelModes: NSFontPanel.ModeMask = [.collection, .face, .size]

final class TalkTextView: NSTextView, NSFontChanging {
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

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        fontPanelModes
    }
}

// MARK: - Controller

final class TalkWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation, NSFontChanging {
    private static let voiceKey = "VoiceIdentifier"
    private static let rateKey = "SpeechRate"
    private static let fontSizeKey = "FontSize"
    private static let fontNameKey = "FontName"
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

    /// Untitled messages show this, so the window is never nameless.
    private static let untitled = "JTalk2"

    /// The file the message was last read from or written to. ⌘S writes back
    /// to it; until there is one, ⌘S asks where to put the text.
    private(set) var documentURL: URL? {
        didSet {
            window.representedURL = documentURL
            window.title = documentURL?.lastPathComponent ?? Self.untitled
        }
    }

    /// What the title bar says. Exposed for tests.
    var title: String { window.title }

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

        window.title = Self.untitled
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
        textView.font = Self.savedFont
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

    // MARK: Font

    private static let defaultFontSize: CGFloat = 24

    /// The sizes ⌘+ and ⌘- step through. Coarser as they get bigger, so going
    /// from readable to very large does not take twenty keystrokes.
    private static let fontSizes: [CGFloat] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64, 80, 96, 144, 288]

    private static func clampFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, fontSizes.first!), fontSizes.last!)
    }

    private static var savedFontSize: CGFloat {
        guard UserDefaults.standard.object(forKey: fontSizeKey) != nil else { return defaultFontSize }
        return clampFontSize(CGFloat(UserDefaults.standard.double(forKey: fontSizeKey)))
    }

    /// The system fonts name themselves with a leading dot — ".AppleSystemUIFont",
    /// ".SFNS-Regular" — and macOS will not hand those back through
    /// NSFont(name:): asking gives Times New Roman. Such a name is therefore
    /// kept as "no typeface chosen" rather than saved.
    private static func isSystemFontName(_ name: String) -> Bool { name.hasPrefix(".") }

    /// The typeface and size the message box opens in. A saved name that no
    /// longer resolves — a font the user has since removed — falls back to the
    /// system font rather than leaving the window unreadable.
    private static var savedFont: NSFont {
        let size = savedFontSize
        guard let name = UserDefaults.standard.string(forKey: fontNameKey),
              !isSystemFontName(name),
              let font = NSFont(name: name, size: size)
        else { return .systemFont(ofSize: size) }
        return font
    }

    /// The same typeface at another size.
    private static func resize(_ font: NSFont, to size: CGFloat) -> NSFont {
        guard size != font.pointSize else { return font }
        return NSFont(descriptor: font.fontDescriptor, size: size) ?? .systemFont(ofSize: size)
    }

    /// Typeface and size together, as the font panel hands them over. Setting
    /// it saves immediately.
    var font: NSFont {
        get { textView.font ?? .systemFont(ofSize: Self.defaultFontSize) }
        set {
            let size = Self.clampFontSize(newValue.pointSize)
            let font = Self.resize(newValue, to: size)
            textView.font = font
            UserDefaults.standard.set(Double(size), forKey: Self.fontSizeKey)
            if Self.isSystemFontName(font.fontName) {
                UserDefaults.standard.removeObject(forKey: Self.fontNameKey)
            } else {
                UserDefaults.standard.set(font.fontName, forKey: Self.fontNameKey)
            }
        }
    }

    /// Point size of the message box, keeping whatever typeface is in use.
    /// Setting it saves immediately.
    var fontSize: CGFloat {
        get { font.pointSize }
        set { font = Self.resize(font, to: Self.clampFontSize(newValue)) }
    }

    /// The standard font panel, opened on the font in use.
    @objc func showFontPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    /// The panel reports its choice here rather than to the text view, so the
    /// choice can be saved and clamped to the size ladder.
    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        font = sender.convert(font)
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        fontPanelModes
    }

    /// Back to the system typeface, at whatever size is in use.
    @objc func resetFont() {
        font = .systemFont(ofSize: fontSize)
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

    // MARK: Files

    /// Text files come in more than one encoding: what almost everything is
    /// written in now, then whatever macOS can work out from the bytes, then
    /// the old Western default, which reads a plain Latin-1 file that the
    /// guess gives up on. Anything that is none of those — a binary file
    /// picked by mistake — is refused rather than shown as mojibake.
    private static func readText(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            var encoding = String.Encoding.utf8
            if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
            if let text = try? String(contentsOf: url, encoding: .windowsCP1252) { return text }
            throw error
        }
    }

    /// Replaces the message with a file's contents. Returns what went wrong,
    /// or nil if the file was read.
    @discardableResult
    func load(from url: URL) -> String? {
        let text: String
        do {
            text = try Self.readText(at: url)
        } catch {
            return error.localizedDescription
        }
        message = text
        let end = NSRange(location: (text as NSString).length, length: 0)
        textView.setSelectedRange(end)
        textView.scrollRangeToVisible(end)
        documentURL = url
        window.makeFirstResponder(textView)
        return nil
    }

    /// Writes the message out as UTF-8. Returns what went wrong, or nil if it
    /// was written.
    @discardableResult
    func save(to url: URL) -> String? {
        do {
            try message.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return error.localizedDescription
        }
        documentURL = url
        return nil
    }

    /// An empty, untitled message. The old text is gone, as it is when you
    /// type over a spoken message.
    @objc func newDocument(_ sender: Any?) {
        message = ""
        documentURL = nil
        window.makeFirstResponder(textView)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let problem = self.load(from: url) {
                self.report("Could not open \(url.lastPathComponent)", problem)
            }
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let url = documentURL else { return saveDocumentAs(sender) }
        if let problem = save(to: url) {
            report("Could not save \(url.lastPathComponent)", problem)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "Message.txt"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let problem = self.save(to: url) {
                self.report("Could not save \(url.lastPathComponent)", problem)
            }
        }
    }

    private func report(_ what: String, _ problem: String) {
        let alert = NSAlert()
        alert.messageText = what
        alert.informativeText = problem
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
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
