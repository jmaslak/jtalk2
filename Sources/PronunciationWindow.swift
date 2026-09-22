// The pronunciation dictionary editor: a small table of word / pronunciation
// rows, listed alphabetically. Edits are written to disk as soon as a field
// loses focus.

import AppKit

final class PronunciationWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column: String {
        case word, say, ipa
    }

    private let store: PronunciationStore
    private let window: NSWindow
    private let tableView = NSTableView()
    private var rows: [Pronunciation]

    init(store: PronunciationStore) {
        self.store = store
        self.rows = store.entries
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        super.init()

        window.title = "Pronunciations"
        window.setFrameAutosaveName("PronunciationWindow")
        window.minSize = NSSize(width: 380, height: 200)
        window.contentView = buildContentView()
        window.isReleasedWhenClosed = false
    }

    /// The store hands back its entries in alphabetical order. The table is
    /// only re-ordered here, on opening: a row that jumped to its new place
    /// the moment you finished typing a word would take the next field you
    /// were tabbing to with it. A row added or renamed now is in order the
    /// next time the window opens.
    func show() {
        rows = store.entries
        tableView.reloadData()
        window.center()
        window.setFrameUsingName("PronunciationWindow")
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let root = NSView()

        for (id, title, width) in [(Column.word, "Word", 150.0),
                                   (Column.say, "Pronunciation", 240.0),
                                   (Column.ipa, "IPA", 40.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tableView

        let add = NSButton(title: "+", target: self, action: #selector(addRow))
        let remove = NSButton(title: "−", target: self, action: #selector(removeSelectedRows))
        let hint = NSTextField(labelWithString:
            "Plain text is spoken in place of the word. Tick IPA to give a phonetic spelling instead.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let buttons = NSStackView(views: [add, remove])
        buttons.spacing = 6

        for view in [scroll, buttons, hint] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),

            hint.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        return root
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let entry = rows[row]

        if column == .ipa {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(ipaToggled(_:)))
            check.state = entry.isIPA ? .on : .off
            return check
        }

        let field = NSTextField(string: column == .word ? entry.word : entry.say)
        field.isBordered = false
        field.drawsBackground = false
        field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        if column == .say && entry.isIPA {
            field.placeholderString = "IPA, e.g. təˈmɑtoʊ"
        }
        return field
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        let columnIndex = tableView.column(for: field)
        guard rows.indices.contains(row), columnIndex >= 0,
              let column = Column(rawValue: tableView.tableColumns[columnIndex].identifier.rawValue)
        else { return }

        switch column {
        case .word: rows[row].word = field.stringValue
        case .say: rows[row].say = field.stringValue
        case .ipa: return
        }
        save()
    }

    @objc private func ipaToggled(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard rows.indices.contains(row) else { return }
        rows[row].isIPA = sender.state == .on
        save()
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    /// Adds a blank row at the bottom, where it stays until the window is
    /// reopened, rather than where it will eventually sort to — an empty word
    /// sorts to the top, away from the button that made it.
    @objc func addRow() {
        // Commit any in-progress edit before the row indexes move.
        window.makeFirstResponder(tableView)
        rows.append(Pronunciation())
        save()
        tableView.reloadData()
        let row = rows.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc func removeSelectedRows() {
        window.makeFirstResponder(tableView)
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }
        rows.remove(atOffsets: IndexSet(selected))
        save()
        tableView.reloadData()
    }

    private func save() {
        if let problem = store.replaceAll(rows) {
            let alert = NSAlert()
            alert.messageText = "Pronunciations not saved"
            alert.informativeText = problem
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
    }
}
