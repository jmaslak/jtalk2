import Foundation
import AVFoundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "PASS" : "FAIL"): \(what)")
    if !ok { failures += 1 }
}

let ipaKey = NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute)
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("jtalk2-test-\(UUID().uuidString)/pronunciations.json")

// ---------- voices ----------
var groups = Voices.grouped()
check(!groups.mine.isEmpty, "preferred-language voices found (\(groups.mine.count))")
check(!groups.rest.isEmpty, "other-language voices found (\(groups.rest.count))")
let ids = [groups.personal, groups.mine, groups.rest].map { Set($0.map(\.identifier)) }
check(ids[0].isDisjoint(with: ids[1]) && ids[0].isDisjoint(with: ids[2]) && ids[1].isDisjoint(with: ids[2]),
      "voice groups do not overlap")
check(ids.reduce(0) { $0 + $1.count } == AVSpeechSynthesisVoice.speechVoices().count,
      "every voice lands in exactly one group")
check(!groups.personal.contains { !Voices.isPersonal($0) }, "personal group holds only personal voices")
check(!groups.mine.contains(where: Voices.isPersonal) && !groups.rest.contains(where: Voices.isPersonal),
      "personal voices are not duplicated into the language groups")
check(Voices.systemDefault != nil, "system default voice resolves")

// Personal Voice access. The result depends on this Mac and on what the user
// has allowed, so all three outcomes are legitimate; only a missing answer or a
// claim of access without any voice behind it is a failure.
var access: Voices.PersonalVoiceAccess?
Voices.requestPersonalVoiceAccess { access = $0 }
let accessDeadline = Date().addingTimeInterval(30)
while access == nil && Date() < accessDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
check(access != nil, "Personal Voice request answered (\(access.map(String.init(describing:)) ?? "no answer"))")
groups = Voices.grouped()
if access == .granted && !groups.personal.isEmpty {
    print("       personal voices: \(groups.personal.map(\.name))")
    check(groups.personal.allSatisfy { Voices.isPersonal($0) }, "granted personal voices are flagged personal")
} else {
    print("       no personal voice available to exercise (access: \(access.map(String.init(describing:)) ?? "?"))")
}

// ---------- pronunciation dictionary ----------
let store = PronunciationStore(fileURL: tmp)
check(store.entries.isEmpty && store.loadFailure == nil, "fresh store is empty with no error")
check(store.apply(to: "plain text").string == "plain text", "empty dictionary passes text through")

check(store.replaceAll([
    Pronunciation(word: "jmaslak", say: "jay maslak"),
    Pronunciation(word: "New York", say: "new york city"),
    Pronunciation(word: "New York City", say: "the big apple"),
    Pronunciation(word: "C++", say: "see plus plus"),
    Pronunciation(word: "tomato", say: "təˈmɑtoʊ", isIPA: true),
    Pronunciation(word: "  ", say: "ignored"),
    Pronunciation(word: "alsoignored", say: "   "),
]) == nil, "dictionary saved without error")

// The list is kept in alphabetical order, whatever order it arrived in.
let order = store.entries.map(\.word)
check(order == ["  ", "alsoignored", "C++", "jmaslak", "New York", "New York City", "tomato"],
      "entries are sorted by word, ignoring case (got \(order))")
check(store.entries.count == 7, "sorting keeps every entry (\(store.entries.count))")

// Case is not a sort key of its own: entries that differ only in case land
// next to each other rather than in two separate runs of the alphabet.
let cased = PronunciationStore(fileURL: tmp.deletingLastPathComponent()
    .appendingPathComponent("cased.json"))
cased.replaceAll([
    Pronunciation(word: "ok", say: "okay"),
    Pronunciation(word: "Zebra", say: "zeb ra"),
    Pronunciation(word: "OK", say: "all right"),
    Pronunciation(word: "apple", say: "ay pull"),
])
check(cased.entries.map(\.word) == ["apple", "ok", "OK", "Zebra"],
      "case sorts together, not apart (got \(cased.entries.map(\.word)))")

// The same word written the same way twice is ordered by what it says, so the
// order does not depend on which one arrived first.
cased.replaceAll([
    Pronunciation(word: "ok", say: "okay"),
    Pronunciation(word: "ok", say: "all right"),
])
check(cased.entries.map(\.say) == ["all right", "okay"],
      "duplicate words are ordered by what they say (got \(cased.entries.map(\.say)))")

check(store.apply(to: "hi jmaslak").string == "hi jay maslak", "plain substitution")
check(store.apply(to: "hi JMASLAK!").string == "hi jay maslak!", "substitution is case-insensitive")
check(store.apply(to: "jmaslakson stays").string == "jmaslakson stays", "only whole words match")
check(store.apply(to: "I love New York City ok").string == "I love the big apple ok", "longest entry wins")
check(store.apply(to: "I love New York ok").string == "I love new york city ok", "shorter entry still matches")
check(store.apply(to: "I write C++ daily").string == "I write see plus plus daily", "regex-special word matches")
check(store.apply(to: "   ").string == "   ", "blank-word entries are ignored")
check(store.apply(to: "alsoignored").string == "alsoignored", "blank-pronunciation entries are ignored")

let ipaResult = store.apply(to: "a tomato here")
var ipaRange = NSRange()
let ipaValue = ipaResult.attribute(ipaKey, at: 2, effectiveRange: &ipaRange) as? String
check(ipaResult.string == "a tomato here", "IPA entry leaves the spoken text alone")
check(ipaValue == "təˈmɑtoʊ", "IPA attribute attached (\(ipaValue ?? "nil"))")
check(ipaRange == NSRange(location: 2, length: 6), "IPA attribute covers exactly the word")

// persistence round trip
let reloaded = PronunciationStore(fileURL: tmp)
check(reloaded.entries.count == 7, "entries survive a reload (\(reloaded.entries.count))")
check(reloaded.entries.map(\.word) == order, "a reloaded dictionary is in the same order")
check(reloaded.apply(to: "hi jmaslak").string == "hi jay maslak", "reloaded dictionary still applies")

// corrupt file handling
try! "not json".write(to: tmp, atomically: true, encoding: .utf8)
let broken = PronunciationStore(fileURL: tmp)
check(broken.loadFailure != nil, "unreadable file reports a failure")
check(broken.entries.isEmpty, "unreadable file yields an empty dictionary")
let siblings = (try? FileManager.default.contentsOfDirectory(atPath: tmp.deletingLastPathComponent().path)) ?? []
check(siblings.contains { $0.hasPrefix("pronunciations-unreadable-") }, "bad file was kept aside")

// ---------- key clicks ----------
let clickerStart = Date()
let clicker = KeyClicker()
let clickerSetup = Date().timeIntervalSince(clickerStart)
check(clickerSetup < 0.5, "clicker warms up quickly at launch (\(String(format: "%.3f", clickerSetup))s)")
check(clicker.isAvailable, "click sound loaded from \(KeyClicker.defaultSoundURL.lastPathComponent)")
check(!clicker.isReady, "the audio engine stays idle until clicks are switched on")
check(clicker.prepare() && clicker.isReady, "switching clicks on starts the audio engine")

// Not just "the call returned" — sound has to actually reach the output. An
// earlier AudioServices version passed a timing check while being silenced by
// System Settings ▸ Sound ▸ Play user interface sound effects, so this taps the
// mixer and looks for real signal.
var peak: Float = 0
clicker.engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { tapped, _ in
    guard let samples = tapped.floatChannelData else { return }
    for channel in 0..<Int(tapped.format.channelCount) {
        for frame in 0..<Int(tapped.frameLength) {
            peak = max(peak, abs(samples[channel][frame]))
        }
    }
}
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
check(peak == 0, "silence before any click (peak \(peak))")
check(clicker.click(), "click() reports it started a sound")
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
check(peak > 0.01, "the click genuinely reaches the audio output (peak \(String(format: "%.3f", peak)))")
clicker.engine.mainMixerNode.removeTap(onBus: 0)

var worstClick = 0.0
var started = 0
for _ in 0..<12 {
    let t0 = Date()
    if clicker.click() { started += 1 }
    worstClick = max(worstClick, Date().timeIntervalSince(t0))
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
check(started == 12, "every rapid keystroke started a click (got \(started))")
// Typing must not wait on audio; NSSound blocks for ~0.12s here.
check(worstClick < 0.02, "clicks do not block the typist (worst \(String(format: "%.4f", worstClick))s)")
RunLoop.main.run(until: Date().addingTimeInterval(1))

let missing = KeyClicker(soundURL: URL(fileURLWithPath: "/System/Library/Sounds/NoSuchSound.aiff"))
check(!missing.isAvailable, "a missing sound file reports unavailable")
check(!missing.click(), "clicking an unavailable clicker is a safe no-op")

// ---------- speaking ----------
let speaker = Speaker()
var finished = 0
speaker.onFinish = { finished += 1 }
let voice = Voices.systemDefault

speaker.speak(store.apply(to: "one two"), voice: voice, rate: AVSpeechUtteranceDefaultSpeechRate)
RunLoop.main.run(until: Date().addingTimeInterval(4))
check(finished == 1, "completed utterance fired onFinish (got \(finished))")

speaker.speak(store.apply(to: "a much longer sentence that gets interrupted before it ends"),
              voice: voice, rate: AVSpeechUtteranceDefaultSpeechRate)
RunLoop.main.run(until: Date().addingTimeInterval(1))
check(speaker.stop(), "stop() reports it interrupted speech")
RunLoop.main.run(until: Date().addingTimeInterval(2))
check(finished == 1, "cancelled utterance did not fire onFinish (got \(finished))")

speaker.speak(store.apply(to: "a long first sentence that will be replaced part way through"),
              voice: voice, rate: AVSpeechUtteranceDefaultSpeechRate)
RunLoop.main.run(until: Date().addingTimeInterval(1))
speaker.speak(store.apply(to: "second"), voice: voice, rate: AVSpeechUtteranceDefaultSpeechRate)
RunLoop.main.run(until: Date().addingTimeInterval(4))
check(finished == 2, "interrupt-and-respeak fired onFinish once (got \(finished - 1))")

speaker.speak(store.apply(to: "  \n "), voice: voice, rate: AVSpeechUtteranceDefaultSpeechRate)
RunLoop.main.run(until: Date().addingTimeInterval(1))
check(finished == 2, "blank text produced no utterance")
check(!speaker.stop(), "stop() reports nothing to interrupt when idle")

// rate extremes and an IPA word both speak to completion
for rate in [Float(0.2), AVSpeechUtteranceMaximumSpeechRate] {
    let before = finished
    speaker.speak(store.apply(to: "a tomato"), voice: voice, rate: rate)
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    check(finished == before + 1, "speech at rate \(rate) completed")
}

try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
