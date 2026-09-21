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
check(sized.fontSize == 96, "oversized value clamps to the largest rung (got \(sized.fontSize))")
sized.increaseFontSize()
check(sized.fontSize == 96, "⌘+ at the top stays put (got \(sized.fontSize))")
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
check(typed.string == "hi ", "the keystrokes still reach the text (got \(typed.string.debugDescription))")

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

try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
