// jtalk2 — a minimal AAC speech box for macOS, in the spirit of jtalk.
//
// Type, press Return to speak, Esc to cancel. When an utterance finishes the
// whole text is selected so the next keystroke starts a fresh message.

import AppKit

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TalkWindowController?
    private var escMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = TalkWindowController()
        self.controller = controller
        NSApp.mainMenu = Self.buildMenu(target: controller)
        controller.show()
        NSApp.activate(ignoringOtherApps: true)

        // Personal voices are withheld until the user allows it, so ask right
        // away; the voice menu refills itself if the answer is yes.
        controller.requestPersonalVoice(explainResult: false)

        if let problem = controller.pronunciations.loadFailure {
            let alert = NSAlert()
            alert.messageText = "Pronunciation dictionary could not be loaded"
            alert.informativeText = problem + " Starting with an empty dictionary."
            alert.alertStyle = .warning
            alert.runModal()
        }

        // Esc stops speech no matter which control has focus.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            controller.stop()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func buildMenu(target: TalkWindowController) -> NSMenu {
        let main = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        for (title, selector, key) in [
            ("Bigger Text", #selector(TalkWindowController.increaseFontSize), "+"),
            ("Smaller Text", #selector(TalkWindowController.decreaseFontSize), "-"),
            ("Default Text Size", #selector(TalkWindowController.resetFontSize), "0"),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command]
            item.target = target
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())
        let fonts = NSMenuItem(title: "Show Fonts…",
                               action: #selector(TalkWindowController.showFontPanel),
                               keyEquivalent: "t")
        fonts.keyEquivalentModifierMask = [.command]
        fonts.target = target
        viewMenu.addItem(fonts)
        let defaultFont = NSMenuItem(title: "Default Font",
                                     action: #selector(TalkWindowController.resetFont),
                                     keyEquivalent: "")
        defaultFont.target = target
        viewMenu.addItem(defaultFont)
        viewMenu.addItem(.separator())
        for (title, selector) in [
            ("Text Color…", #selector(TalkWindowController.chooseTextColor)),
            ("Background Color…", #selector(TalkWindowController.chooseBackgroundColor)),
            ("Default Colors", #selector(TalkWindowController.resetColors)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = target
            viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let speechItem = NSMenuItem()
        let speechMenu = NSMenu(title: "Speech")
        let speak = NSMenuItem(title: "Speak", action: #selector(TalkWindowController.speak), keyEquivalent: "\r")
        speak.keyEquivalentModifierMask = [.command]
        speak.target = target
        speechMenu.addItem(speak)
        let stop = NSMenuItem(title: "Stop Speaking", action: #selector(TalkWindowController.stop), keyEquivalent: ".")
        stop.keyEquivalentModifierMask = [.command]
        stop.target = target
        speechMenu.addItem(stop)
        speechMenu.addItem(.separator())
        let personal = NSMenuItem(title: "Use Personal Voice…",
                                  action: #selector(TalkWindowController.askForPersonalVoice),
                                  keyEquivalent: "")
        personal.target = target
        speechMenu.addItem(personal)
        let dictionary = NSMenuItem(title: "Pronunciations…",
                                    action: #selector(TalkWindowController.editPronunciations),
                                    keyEquivalent: "d")
        dictionary.keyEquivalentModifierMask = [.command]
        dictionary.target = target
        speechMenu.addItem(dictionary)
        speechMenu.addItem(.separator())
        let defaultRate = NSMenuItem(title: "Default Speed",
                                     action: #selector(TalkWindowController.resetRate),
                                     keyEquivalent: "0")
        defaultRate.keyEquivalentModifierMask = [.command, .option]
        defaultRate.target = target
        speechMenu.addItem(defaultRate)
        speechMenu.addItem(.separator())
        let click = NSMenuItem(title: "Click on Key Press",
                               action: #selector(TalkWindowController.toggleKeyClick),
                               keyEquivalent: "")
        click.target = target
        speechMenu.addItem(click)
        speechItem.submenu = speechMenu
        main.addItem(speechItem)

        return main
    }
}

// `jtalk2.app/Contents/MacOS/jtalk2 --voices` prints what the synthesizer
// offers this app, including whether Personal Voice came through.
if CommandLine.arguments.contains("--voices") {
    var answered = false
    Voices.requestPersonalVoiceAccess { access in
        print("Personal Voice access: \(access)")
        let groups = Voices.grouped()
        for (label, voices) in [("Personal", groups.personal),
                                ("Your languages", groups.mine),
                                ("Other languages", groups.rest)] {
            print("\n\(label) (\(voices.count)):")
            for voice in voices {
                print("  \(Voices.title(voice))")
            }
        }
        answered = true
    }
    let deadline = Date().addingTimeInterval(30)
    while !answered && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    exit(answered ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
