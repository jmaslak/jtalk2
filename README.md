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
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘N | Start a new, empty message |
| ⌘O | Open a text file |
| ⌘S | Save the message |
| ⇧⌘S | Save the message as a new file |
| ⌘D | Open the pronunciation dictionary |
| ⌘+ / ⌘- | Bigger / smaller text |
| ⌘0 | Back to the default text size |
| ⌘T | Open the font panel |
| ⌥⌘0 | Back to the default speaking speed |

When an utterance finishes, the whole message is highlighted, so the next
keystroke replaces it. Cancelling with Esc leaves the text alone.

⌘Z takes back whatever last changed the message box — typing, including
typing over the message speaking left highlighted, opening a file, or emptying
the box with ⌘N — and ⇧⌘Z puts it back. Opening a file and ⌘N each count as one step, and take
the window's title with them, so undoing an Open leaves ⌘S writing back to the
file the text actually came from. Edit ▸ Undo names the step it would take
back. The font, colours and speaking speed are settings rather than edits, and
are not on the undo stack; **View ▸ Default Font** and the other defaults are
the way back from those.

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

## Files

**File ▸ Open…** (⌘O) reads a text file into the message box and leaves the
caret at the end of the text, ready to carry on typing. **File ▸ Save**
(⌘S) writes it back out as UTF-8. ⌘S on a message that has never been saved asks
where to put it, as **File ▸ Save As…** (⇧⌘S) always does. The title bar names
the file the message came from; **File ▸ New Message** (⌘N) empties the box and
forgets it.

A file is read as UTF-8 first, then in whatever encoding macOS can work out from
the bytes, then as Windows-1252, which covers an older Western text file the
guess gives up on. A file that is none of those — something that is not text at
all — is refused rather than poured into the box as mojibake.

There is no prompt about unsaved text: opening another file, starting a new
message or quitting throws the current one away.

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

The table is listed alphabetically by word, and so is the file on disk. A row
you add or rename stays where it is until you close and reopen the window, so
the row you are typing in does not move out from under you mid-edit.

The − button deletes without asking and writes the change straight to disk, so
⌘Z is the way back: adding a row, removing rows and ticking IPA all undo.
Text typed into a cell is undone by ⌘Z while the cell is still open, as in any
text field.

That history belongs to this window and lasts as long as it is open. ⌘Z in the
message box never reaches into the dictionary, and closing the editor throws its
history away, so reopening it starts with nothing to undo. The dictionary itself
is on disk either way.

Entries are stored as JSON, editable by hand:

    ~/Library/Application Support/jtalk2/pronunciations.json

If that file is ever unreadable, jtalk2 says so at launch, keeps the bad file
under a `pronunciations-unreadable-*.json` name, and starts empty rather than
overwriting it.

## Tests

`Tests/speech` covers the dictionary, its ordering, the voice grouping, Personal
Voice access and the synthesizer callbacks. `Tests/ui` builds the real windows
and checks that speaking highlights the message, that cancelling does not, and
that undo and redo take back typing, opened files and a cleared box. Both link
the shipping sources.
