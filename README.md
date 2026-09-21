# jtalk2

A minimal AAC speech box for macOS, in the spirit of jtalk: one text box, one
voice menu, one speed slider. Type, press Return, it speaks.

## Build

    make          # builds build/jtalk2.app
    make run      # builds and launches it
    make install  # copies it to ~/Applications
    make test     # runs the test suites (speaks out loud, takes about a minute)

The icon is drawn by `Tools/makeicon.swift` rather than checked in as a binary:
`make icon` regenerates `build/jtalk2.icns`, and the normal build copies it into
the bundle. Edit the drawing code to change it.

No Xcode project — `swiftc` compiles `Sources/*.swift` and the Makefile wraps
the binary in a bundle. `Package.swift` is there only so editors understand the
sources as one module.

## Using it

| Key | Action |
| --- | --- |
| Return | Speak the message |
| Shift-Return or Option-Return | Insert a line break instead |
| Esc | Stop speaking immediately |
| ⌘. | Stop speaking |
| ⌘Return | Speak |
| ⌘D | Open the pronunciation dictionary |
| ⌘+ / ⌘- | Bigger / smaller text |
| ⌘0 | Back to the default text size |
| ⌘T | Open the font panel |
| ⌥⌘0 | Back to the default speaking speed |

When an utterance finishes, the whole message is highlighted, so the next
keystroke replaces it. Cancelling with Esc leaves the text alone.

The pop-up at the top picks the voice; personal voices come first, then voices
in your own languages, then the rest. The slider next to it sets the speaking
speed; **Speech ▸ Default Speed** (⌥⌘0) puts it back where the synthesizer
started, which is the way out of a slider nudged by accident. The text size follows ⌘+ and ⌘- through a ladder of sizes from 10 to 288
points.

**View ▸ Show Fonts…** (⌘T) opens the standard macOS font panel on whatever
font the message box is using; picking a typeface or a size there changes the
box at once. Only the collection, typeface and size parts of the panel apply —
its colour and effect controls are switched off, because the colours belong to
the menu items below. **View ▸ Default Font** puts the typeface back to the
system font and leaves the size where it is.

A typeface is remembered by name, so a font that is later uninstalled falls back
to the system font instead of leaving the box unreadable. The system font itself
is not stored by name — macOS does not hand its private names back — so choosing
a system-font variant such as bold lasts for the session but not past a relaunch.

**View ▸ Text Color…** and **View ▸ Background Color…** open the colour picker;
the message box follows the picker as you drag. **View ▸ Default Colors** goes
back to the system colours, which track light and dark mode. The post-speech
highlight is drawn as inverse video — background in the text colour, text in the
background colour — so it stays readable whatever pair you pick.

Voice, speed, typeface, text size and colours are all saved the moment they
change and come back next launch.

**Speech ▸ Click on Key Press** makes each keystroke click, for typists who want
the feedback. Off unless you turn it on, and remembered.

The sound is the opening 120ms of the system `Tink`, faded out — the whole sound
rings for over half a second, which drones when you type. `Sources/KeyClick.swift`
holds the source file, the length and the volume, one constant each. Clicks play
through the app's own audio engine, so they do **not** depend on System Settings ▸
Sound ▸ *Play user interface sound effects*. The engine only starts once you turn
clicks on. If the sound cannot be loaded the menu item is disabled rather than
quietly doing nothing.

## Personal Voice

jtalk2 asks for access to your Personal Voice at launch. macOS only hands
personal voices to an app that has been allowed, and only after
System Settings ▸ Accessibility ▸ Personal Voice ▸ *Allow Apps to Request to
Use* is on. If you say no, or turn it on later, use **Speech ▸ Use Personal
Voice…** to ask again; it reports what happened.

To see what the app can actually reach:

    build/jtalk2.app/Contents/MacOS/jtalk2 --voices

## Pronunciation dictionary

**Speech ▸ Pronunciations…** (⌘D) opens a table of words and how to say them.

* Leave **IPA** unticked to respell a word: `jmaslak` → `jay maslak`. The
  replacement text is spoken in place of the word.
* Tick **IPA** to give a phonetic spelling instead: `tomato` → `təˈmɑtoʊ`. The
  word itself is unchanged; the pronunciation rides along as a hint to the
  synthesizer. Unparseable IPA is ignored by macOS rather than breaking the
  utterance.

Matching is case-insensitive and whole-word only, so `cat` does not fire inside
`category`. When entries overlap, the longest wins: with both `New York` and
`New York City` in the table, "New York City" uses the longer entry.

Entries are stored as JSON, editable by hand:

    ~/Library/Application Support/jtalk2/pronunciations.json

If that file is ever unreadable, jtalk2 says so at launch, keeps the bad file
under a `pronunciations-unreadable-*.json` name, and starts empty rather than
overwriting it.

## Tests

`Tests/speech` covers the dictionary, the voice grouping, Personal Voice access
and the synthesizer callbacks. `Tests/ui` builds the real windows and checks
that speaking highlights the message and that cancelling does not. Both link the
shipping sources.
