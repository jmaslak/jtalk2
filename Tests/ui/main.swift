// Smoke test for the windows: builds and displays the real UI off to the side,
// speaks through it, and checks that the message ends up highlighted.
//
// Runs as a background (accessory) app so it does not steal focus.

import AppKit
import AVFoundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "PASS" : "FAIL"): \(what)")
    if !ok { failures += 1 }
}

func pump(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        guard let event = NSApp.nextEvent(matching: .any, until: deadline,
                                          inMode: .default, dequeue: true) else { break }
        NSApp.sendEvent(event)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("jtalk2-uitest-\(UUID().uuidString)/pronunciations.json")
let store = PronunciationStore(fileURL: tmp)
store.replaceAll([
    Pronunciation(word: "jmaslak", say: "jay maslak"),
    Pronunciation(word: "tomato", say: "təˈmɑtoʊ", isIPA: true),
])

// Main window
let controller = TalkWindowController(pronunciations: store)
controller.show()
pump(0.5)
check(true, "main window built and shown")

controller.message = "hello jmaslak"
check(controller.message == "hello jmaslak", "message box round-trips text")
check(controller.highlightedRange.length == 0, "nothing highlighted before speaking")

controller.speak()
pump(6)
check(controller.highlightedRange == NSRange(location: 0, length: 13),
      "whole message highlighted after speaking (got \(controller.highlightedRange))")

// Esc-equivalent: stopping mid-utterance must leave the text unhighlighted
controller.message = "a considerably longer sentence that will be cut off part way through"
pump(0.2)
check(controller.highlightedRange.length == 0, "typing clears the highlight")
controller.speak()
pump(1)
controller.stop()
pump(2)
check(controller.highlightedRange.length == 0, "cancelled speech does not highlight")

// Font size: steps through a ladder, clamps, and saves at once
UserDefaults.standard.removeObject(forKey: "FontSize")
let sized = TalkWindowController(pronunciations: store)
sized.show()
pump(0.3)
check(sized.fontSize == 24, "default font size is 24 (got \(sized.fontSize))")

sized.increaseFontSize()
check(sized.fontSize == 28, "⌘+ steps up the ladder (got \(sized.fontSize))")
sized.decreaseFontSize()
sized.decreaseFontSize()
check(sized.fontSize == 20, "⌘- steps down the ladder (got \(sized.fontSize))")

sized.fontSize = 13
check(sized.fontSize == 13, "an off-ladder size is kept as given (got \(sized.fontSize))")
sized.increaseFontSize()
check(sized.fontSize == 14, "stepping up from off-ladder lands on the next rung (got \(sized.fontSize))")
sized.decreaseFontSize()
check(sized.fontSize == 12, "stepping down from a rung lands on the one below (got \(sized.fontSize))")

sized.fontSize = 500
check(sized.fontSize == 288, "oversized value clamps to the largest rung (got \(sized.fontSize))")
sized.increaseFontSize()
check(sized.fontSize == 288, "⌘+ at the top stays put (got \(sized.fontSize))")
sized.fontSize = 1
check(sized.fontSize == 10, "undersized value clamps to the smallest rung (got \(sized.fontSize))")
sized.decreaseFontSize()
check(sized.fontSize == 10, "⌘- at the bottom stays put (got \(sized.fontSize))")

sized.fontSize = 36
check(UserDefaults.standard.double(forKey: "FontSize") == 36, "font size saved without being asked")
let reopened = TalkWindowController(pronunciations: store)
check(reopened.fontSize == 36, "a new window opens at the saved size (got \(reopened.fontSize))")
sized.resetFontSize()
check(sized.fontSize == 24 && UserDefaults.standard.double(forKey: "FontSize") == 24,
      "⌘0 returns to the default and saves it")
UserDefaults.standard.removeObject(forKey: "FontSize")

// Typeface: chosen, saved at once, restored on reopen, resettable
UserDefaults.standard.removeObject(forKey: "FontName")
let styled = TalkWindowController(pronunciations: store)
styled.show()
pump(0.3)
check(styled.font.fontName == NSFont.systemFont(ofSize: styled.fontSize).fontName,
      "the message box starts in the system font (got \(styled.font.fontName))")

styled.font = NSFont(name: "Courier", size: 18)!
check(styled.font.fontName == "Courier" && styled.fontSize == 18,
      "a chosen font is applied, size and all (got \(styled.font.fontName) at \(styled.fontSize))")
check(UserDefaults.standard.string(forKey: "FontName") == "Courier",
      "the typeface is saved without being asked")

let restyled = TalkWindowController(pronunciations: store)
check(restyled.font.fontName == "Courier" && restyled.fontSize == 18,
      "a new window opens in the saved font (got \(restyled.font.fontName) at \(restyled.fontSize))")

styled.increaseFontSize()
check(styled.font.fontName == "Courier" && styled.fontSize == 20,
      "⌘+ keeps the typeface (got \(styled.font.fontName) at \(styled.fontSize))")

styled.font = NSFont(name: "Courier", size: 500)!
check(styled.fontSize == 288 && styled.font.fontName == "Courier",
      "an oversized font clamps to the top rung, typeface intact "
        + "(got \(styled.font.fontName) at \(styled.fontSize))")

// The font panel is the dialog itself: it must open on the font in use and
// send its changes back to the window rather than straight to the text view.
styled.showFontPanel()
pump(0.3)
check(NSFontManager.shared.selectedFont?.fontName == "Courier",
      "the font panel opens on the font in use (got \(NSFontManager.shared.selectedFont?.fontName ?? "none"))")
check(NSFontManager.shared.target as? TalkWindowController === styled,
      "the panel's choices come back to the window")
NSFontManager.shared.fontPanel(false)?.close()
pump(0.2)

styled.resetFont()
check(styled.font.fontName == NSFont.systemFont(ofSize: styled.fontSize).fontName,
      "Default Font restores the system typeface (got \(styled.font.fontName))")
check(UserDefaults.standard.string(forKey: "FontName") == nil, "Default Font forgets the saved typeface")
check(styled.fontSize == 288, "Default Font leaves the size alone (got \(styled.fontSize))")

styled.increaseFontSize()
check(UserDefaults.standard.string(forKey: "FontName") == nil,
      "resizing the system font saves no typeface name for it to choke on "
        + "(got \(UserDefaults.standard.string(forKey: "FontName") ?? "none"))")

// A font that is no longer installed must not leave the window unreadable.
UserDefaults.standard.set("NoSuchFontIsInstalled", forKey: "FontName")
let salvaged = TalkWindowController(pronunciations: store)
check(salvaged.font.fontName == NSFont.systemFont(ofSize: salvaged.fontSize).fontName,
      "a missing saved font falls back to the system font (got \(salvaged.font.fontName))")
UserDefaults.standard.removeObject(forKey: "FontName")
UserDefaults.standard.removeObject(forKey: "FontSize")

// Speed: saved at once, restored on reopen, resettable
UserDefaults.standard.removeObject(forKey: "SpeechRate")
let paced = TalkWindowController(pronunciations: store)
paced.show()
pump(0.3)
check(paced.rate == AVSpeechUtteranceDefaultSpeechRate,
      "speed starts at the synthesizer default (got \(paced.rate))")

paced.rate = 0.35
check(paced.rate == 0.35, "speed applied (got \(paced.rate))")
check(UserDefaults.standard.float(forKey: "SpeechRate") == 0.35, "speed saved without being asked")
let repaced = TalkWindowController(pronunciations: store)
check(repaced.rate == 0.35, "a new window opens at the saved speed (got \(repaced.rate))")

paced.rate = 0
check(paced.rate == 0.2, "too-slow speed clamps to the slowest the slider allows (got \(paced.rate))")
paced.rate = 5
check(paced.rate == AVSpeechUtteranceMaximumSpeechRate,
      "too-fast speed clamps to the maximum (got \(paced.rate))")

paced.resetRate()
check(paced.rate == AVSpeechUtteranceDefaultSpeechRate,
      "Default Speed returns to the synthesizer default (got \(paced.rate))")
check(UserDefaults.standard.object(forKey: "SpeechRate") == nil,
      "Default Speed forgets the saved speed")

// Colors: applied, saved at once, restored on reopen, resettable
UserDefaults.standard.removeObject(forKey: "TextColor")
UserDefaults.standard.removeObject(forKey: "BackgroundColor")
let colored = TalkWindowController(pronunciations: store)
colored.show()
pump(0.3)
check(colored.textColor == NSColor.textColor, "text starts at the system color")
check(colored.backgroundColor == NSColor.textBackgroundColor, "background starts at the system color")

let yellow = NSColor.systemYellow
let navy = NSColor(srgbRed: 0, green: 0, blue: 0.4, alpha: 1)
colored.textColor = yellow
colored.backgroundColor = navy
check(colored.textColor == yellow, "text color applied")
check(colored.backgroundColor == navy, "background color applied")
check(UserDefaults.standard.data(forKey: "TextColor") != nil
        && UserDefaults.standard.data(forKey: "BackgroundColor") != nil,
      "colors saved without being asked")

let recolored = TalkWindowController(pronunciations: store)
check(recolored.textColor == yellow && recolored.backgroundColor == navy,
      "a new window opens in the saved colors")

// The post-speech highlight must stay legible in whatever colors are chosen.
recolored.message = "highlight me"
recolored.speak()
pump(6)
check(recolored.highlightedRange.length == 12, "speaking still highlights with custom colors")
check(recolored.textColor == yellow,
      "replacing the message keeps the chosen text color (got \(recolored.textColor))")

colored.resetColors()
check(colored.textColor == NSColor.textColor && colored.backgroundColor == NSColor.textBackgroundColor,
      "Default Colors restores the system colors")
check(UserDefaults.standard.data(forKey: "TextColor") == nil
        && UserDefaults.standard.data(forKey: "BackgroundColor") == nil,
      "Default Colors forgets the saved colors")

// Key clicks: off by default, toggles, persists, and is wired to keyDown
UserDefaults.standard.removeObject(forKey: "KeyClick")
let clicky = TalkWindowController(pronunciations: store)
clicky.show()
pump(0.3)
check(clicky.keyClickAvailable, "click sound is available on this Mac")
check(!clicky.keyClickEnabled, "key clicks are off until asked for")
clicky.toggleKeyClick()
check(clicky.keyClickEnabled, "menu item turns key clicks on")
check(UserDefaults.standard.bool(forKey: "KeyClick"), "the choice is saved at once")
let stillClicky = TalkWindowController(pronunciations: store)
check(stillClicky.keyClickEnabled, "a new window remembers key clicks are on")
clicky.toggleKeyClick()
check(!clicky.keyClickEnabled, "menu item turns key clicks back off")
UserDefaults.standard.removeObject(forKey: "KeyClick")

// The text view must hand every keystroke to the click hook before inserting it.
let typed = TalkTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
var clicks = 0
typed.onKeyDown = { clicks += 1 }
for character in ["h", "i", " "] {
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, characters: character,
                               charactersIgnoringModifiers: character, isARepeat: false, keyCode: 4)!
    typed.keyDown(with: key)
}
check(clicks == 3, "every keystroke reaches the click hook (got \(clicks))")
check(typed.responds(to: #selector(TalkTextView.validModesForFontPanel(_:))),
      "the text view answers the font panel, so its colour and effect controls stay out")
check(typed.string == "hi ", "the keystrokes still reach the text (got \(typed.string.debugDescription))")

// Files: the message goes out to disk and comes back
let docs = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("jtalk2-files-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
let filed = TalkWindowController(pronunciations: store)
filed.show()
pump(0.3)
check(filed.documentURL == nil && filed.title == "JTalk2",
      "an untitled message has no file and the app's own title (got \(filed.title))")

let letter = docs.appendingPathComponent("letter.txt")
filed.message = "please pass the salt"
check(filed.save(to: letter) == nil, "saving reports no problem")
check((try? String(contentsOf: letter, encoding: .utf8)) == "please pass the salt",
      "the message is on disk as it was typed")
check(filed.documentURL == letter, "the window remembers the file it was saved to")
check(filed.title == "letter.txt", "the title bar names the file (got \(filed.title))")

filed.message = "please pass the pepper"
filed.saveDocument(nil)
pump(0.2)
check((try? String(contentsOf: letter, encoding: .utf8)) == "please pass the pepper",
      "⌘S writes back to the same file without asking where")

let other = docs.appendingPathComponent("other.txt")
try? "hello from a file".write(to: other, atomically: true, encoding: .utf8)
let opened = TalkWindowController(pronunciations: store)
opened.show()
pump(0.3)
check(opened.load(from: other) == nil, "loading reports no problem")
check(opened.message == "hello from a file",
      "the file's text is in the message box (got \(opened.message.debugDescription))")
check(opened.highlightedRange == NSRange(location: 17, length: 0),
      "an opened file leaves the caret after the last character, nothing highlighted")
check(opened.documentURL == other && opened.title == "other.txt",
      "the opened file names the window (got \(opened.title))")

opened.newDocument(nil)
check(opened.message.isEmpty && opened.documentURL == nil && opened.title == "JTalk2",
      "New Message empties the box and forgets the file")

// Text files are not all UTF-8; one that is not must still open.
let latin = docs.appendingPathComponent("latin1.txt")
try? "caf\u{e9} au lait".data(using: .isoLatin1)!.write(to: latin)
check(opened.load(from: latin) == nil, "a file that is not UTF-8 still opens")
check(opened.message == "café au lait", "its text comes through (got \(opened.message.debugDescription))")
check(opened.highlightedRange == NSRange(location: 12, length: 0),
      "the caret counts the accented character once (got \(opened.highlightedRange))")

// But a file that is not text at all should be refused, not shown as mojibake.
let binary = docs.appendingPathComponent("noise.bin")
try? Data((0...255).map { UInt8($0) }).write(to: binary)
check(opened.load(from: binary) != nil, "a file that is not text is refused")
check(opened.message == "café au lait", "a refused file leaves the message alone")

opened.message = "still here"
check(opened.load(from: docs.appendingPathComponent("not-here.txt")) != nil,
      "opening a file that is not there reports a problem")
check(opened.message == "still here", "a failed open leaves the message alone")

let claimed = opened.documentURL
check(opened.save(to: URL(fileURLWithPath: "/no-such-directory/message.txt")) != nil,
      "saving where it cannot write reports a problem")
check(opened.documentURL == claimed, "a failed save does not claim the file")

try? FileManager.default.removeItem(at: docs)

// Undo: typing, opening a file and clearing the box all come back.
func typeInto(_ view: NSTextView, _ text: String) {
    for character in text.map(String.init) {
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: 0, context: nil, characters: character,
                                   charactersIgnoringModifiers: character, isARepeat: false, keyCode: 4)!
        view.keyDown(with: key)
    }
}

// The Edit menu sends undo: to no particular target, so it has to find a
// handler by walking the responder chain out of the message box.
func chainHandles(_ selector: Selector, from start: NSResponder?) -> Bool {
    var responder = start
    while let current = responder {
        if current.responds(to: selector) { return true }
        if let helper = current.supplementalTarget(forAction: selector, sender: nil),
           (helper as AnyObject).responds(to: selector) { return true }
        responder = current.nextResponder
    }
    return false
}

let undoable = TalkWindowController(pronunciations: store)
undoable.show()
pump(0.3)
let undo = undoable.messageView.undoManager
check(undo != nil, "the message box has an undo manager")
check(chainHandles(Selector(("undo:")), from: undoable.messageView),
      "Edit ▸ Undo finds a handler from the message box")
check(chainHandles(Selector(("redo:")), from: undoable.messageView),
      "Edit ▸ Redo finds a handler from the message box")

typeInto(undoable.messageView, "hello")
pump(0.3)
check(undoable.message == "hello", "the keystrokes reached the box (got \(undoable.message.debugDescription))")
undo?.undo()
pump(0.2)
check(undoable.message.isEmpty, "undo takes the typing back (got \(undoable.message.debugDescription))")
undo?.redo()
pump(0.2)
check(undoable.message == "hello", "redo puts the typing back (got \(undoable.message.debugDescription))")

let undoDocs = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("jtalk2-undo-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: undoDocs, withIntermediateDirectories: true)
let note = undoDocs.appendingPathComponent("note.txt")
try? "from the file".write(to: note, atomically: true, encoding: .utf8)

// The Edit menu has to say what it would take back, and go grey when there is
// nothing left to.
let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")

check(undoable.load(from: note) == nil, "the file opened")
pump(0.2)
check(undoable.message == "from the file" && undoable.title == "note.txt",
      "the file replaced the message and named the window")
let mainWindow = undoable.messageView.window
check(mainWindow?.validateMenuItem(undoItem) == true, "Undo is live with an edit to take back")
check(undoItem.title.contains("Open note.txt"),
      "the menu names the edit it would undo (got \(undoItem.title))")
undo?.undo()
pump(0.2)
check(undoable.message == "hello", "undo puts back the text the file replaced (got \(undoable.message.debugDescription))")
check(undoable.documentURL == nil && undoable.title == "JTalk2",
      "undo forgets the file too, so ⌘S does not write over it (got \(undoable.title))")
undo?.redo()
pump(0.2)
check(undoable.message == "from the file" && undoable.title == "note.txt",
      "redo opens the file again, title and all (got \(undoable.title))")

undoable.newDocument(nil)
pump(0.2)
check(undoable.message.isEmpty && undoable.documentURL == nil, "New Message empties the box")
undo?.undo()
pump(0.2)
check(undoable.message == "from the file" && undoable.title == "note.txt",
      "undo brings back a cleared message and its file (got \(undoable.message.debugDescription))")

// Nothing to clear: New Message must not leave a step that undoes nothing.
undoable.newDocument(nil)
pump(0.2)
undoable.newDocument(nil)
pump(0.2)
undo?.undo()
pump(0.2)
check(undoable.message == "from the file",
      "a second New Message on an empty box adds no empty undo step (got \(undoable.message.debugDescription))")

// The font survives a replacement, which carries the box's own attributes.
undoable.font = NSFont.systemFont(ofSize: 24)
undoable.message = "sized text"
pump(0.2)
check(undoable.messageView.font?.pointSize == 24,
      "replacing the message keeps the chosen font (got \(undoable.messageView.font?.pointSize ?? 0))")

while undo?.canUndo == true { undo?.undo() }
pump(0.2)
check(mainWindow?.validateMenuItem(undoItem) == false,
      "Undo goes grey once everything has been taken back")
check(mainWindow?.validateMenuItem(redoItem) == true,
      "Redo is live once something has been undone")

try? FileManager.default.removeItem(at: undoDocs)

// Pronunciation editor
let editor = PronunciationWindow(store: store)
editor.show()
pump(0.5)
check(true, "pronunciation window built and shown")
editor.addRow()
pump(0.3)
check(store.entries.count == 3, "adding a row saved a new entry (\(store.entries.count))")
editor.removeSelectedRows()  // addRow() leaves the new row selected
pump(0.3)
check(store.entries.count == 2, "removing a row saved the change (\(store.entries.count))")

// The − button writes to disk on the spot, so ⌘Z has to be able to undo it.
editor.undoManager?.undo()
pump(0.3)
check(store.entries.count == 3, "undo puts a removed row back (\(store.entries.count))")
editor.undoManager?.undo()
pump(0.3)
check(store.entries.count == 2, "undo again takes back the added row (\(store.entries.count))")
editor.undoManager?.redo()
pump(0.3)
check(store.entries.count == 3, "redo adds it again (\(store.entries.count))")

// That history belongs to the editor window, not to the app: closing it throws
// the history away, so ⌘Z in a reopened editor cannot reach back over it.
check(editor.undoManager?.canUndo == true, "the editor has something to undo before closing")
check(mainWindow?.validateMenuItem(undoItem) == false,
      "the main window's Undo is untouched by the editor's history")
editor.close()
pump(0.3)
check(editor.undoManager?.canUndo == false && editor.undoManager?.canRedo == false,
      "closing the editor forgets what it could undo and redo")
editor.show()
pump(0.3)
check(editor.undoManager?.canUndo == false && editor.undoManager?.canRedo == false,
      "a reopened editor starts with an empty undo history")
check(store.entries.count == 3, "closing the editor changes nothing on disk (\(store.entries.count))")
editor.close()

try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
