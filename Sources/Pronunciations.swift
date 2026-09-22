// User pronunciation dictionary: word -> how to say it.
//
// An entry is either a respelling ("jmaslak" -> "jay maslak"), which is
// substituted into the text, or IPA, which is attached to the original word as
// a speech-synthesis attribute. Stored as JSON in Application Support so it can
// be edited or backed up by hand.

import Foundation
import AVFoundation

struct Pronunciation: Codable, Equatable {
    var word: String
    var say: String
    var isIPA: Bool

    init(word: String = "", say: String = "", isIPA: Bool = false) {
        self.word = word
        self.say = say
        self.isIPA = isIPA
    }
}

final class PronunciationStore {
    private(set) var entries: [Pronunciation] = []

    /// Set when the file existed but could not be read; the bad file is kept
    /// under a new name so nothing is lost. Surfaced to the user at launch.
    private(set) var loadFailure: String?

    private var matcher: NSRegularExpression?
    private var lookup: [String: Pronunciation] = [:]

    private static let ipaKey = NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute)

    static let defaultFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("jtalk2/pronunciations.json")
    }()

    let fileURL: URL

    init(fileURL: URL = PronunciationStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: Storage

    private func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            rebuild()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            entries = Self.sorted(try JSONDecoder().decode([Pronunciation].self, from: data))
        } catch {
            entries = []
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let saved = url.deletingLastPathComponent()
                .appendingPathComponent("pronunciations-unreadable-\(stamp).json")
            let moved = (try? FileManager.default.moveItem(at: url, to: saved)) != nil
            loadFailure = "Could not read \(url.path): \(error.localizedDescription)."
                + (moved ? " The existing file was kept as \(saved.lastPathComponent)." : "")
        }
        rebuild()
    }

    /// Replaces the dictionary and writes it to disk. Returns an error message
    /// on failure so the caller can show it.
    @discardableResult
    func replaceAll(_ newEntries: [Pronunciation]) -> String? {
        entries = Self.sorted(newEntries)
        rebuild()

        let url = fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
            return nil
        } catch {
            return "Could not save \(url.path): \(error.localizedDescription)"
        }
    }

    /// The dictionary is kept in alphabetical order, so both the editor and
    /// the file on disk read as a list you can find a word in. Sorting is the
    /// same as the Finder's, so case does not split a word from its other
    /// spelling; a word listed twice is ordered by what it says, rather than
    /// by which copy happened to be saved first.
    private static func sorted(_ unsorted: [Pronunciation]) -> [Pronunciation] {
        unsorted.sorted {
            switch $0.word.localizedStandardCompare($1.word) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.say.localizedStandardCompare($1.say) == .orderedAscending
            }
        }
    }

    // MARK: Matching

    private func rebuild() {
        lookup = [:]
        for entry in entries where !entry.word.trimmingCharacters(in: .whitespaces).isEmpty
            && !entry.say.trimmingCharacters(in: .whitespaces).isEmpty {
            lookup[entry.word.lowercased()] = entry
        }
        guard !lookup.isEmpty else {
            matcher = nil
            return
        }
        // Longest first so "New York City" wins over "New York".
        let alternatives = lookup.keys
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let wordChar = "[\\p{L}\\p{N}_]"
        matcher = try? NSRegularExpression(
            pattern: "(?<!\(wordChar))(?:\(alternatives))(?!\(wordChar))",
            options: [.caseInsensitive])
    }

    /// Rewrites `text` for the synthesizer, applying every matching entry.
    func apply(to text: String) -> NSAttributedString {
        guard let matcher else { return NSAttributedString(string: text) }

        let source = text as NSString
        let result = NSMutableAttributedString()
        var cursor = 0

        for match in matcher.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor {
                let gap = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: source.substring(with: gap)))
            }
            let matched = source.substring(with: match.range)
            switch lookup[matched.lowercased()] {
            case let entry? where entry.isIPA:
                result.append(NSAttributedString(string: matched, attributes: [Self.ipaKey: entry.say]))
            case let entry?:
                result.append(NSAttributedString(string: entry.say))
            case nil:
                result.append(NSAttributedString(string: matched))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length {
            let tail = NSRange(location: cursor, length: source.length - cursor)
            result.append(NSAttributedString(string: source.substring(with: tail)))
        }
        return result
    }
}
