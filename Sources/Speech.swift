// Speech synthesis and voice enumeration for jtalk2.

import Foundation
import AVFoundation

// MARK: - Speech

final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private nonisolated(unsafe) let synth = AVSpeechSynthesizer()

    /// The utterance we still expect to hear out. Cleared on stop, so a
    /// cancelled utterance can be told apart from one that ran to the end —
    /// macOS reports both through `didFinish`.
    private nonisolated(unsafe) var pending: AVSpeechUtterance?

    /// Called on the main thread when an utterance finishes on its own.
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: NSAttributedString, voice: AVSpeechSynthesisVoice?, rate: Float) {
        stop()
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(attributedString: text)
        utterance.voice = voice
        utterance.rate = rate
        pending = utterance
        synth.speak(utterance)
    }

    /// Returns true if speech was actually interrupted.
    @discardableResult
    func stop() -> Bool {
        pending = nil
        guard synth.isSpeaking || synth.isPaused else { return false }
        synth.stopSpeaking(at: .immediate)
        return true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === pending else { return }
        pending = nil
        DispatchQueue.main.async { [weak self] in self?.onFinish?() }
    }
}

// MARK: - Voices

enum Voices {
    /// Whether this Mac will hand over the user's Personal Voice.
    enum PersonalVoiceAccess {
        case granted
        case denied
        case unsupported
    }

    struct Groups {
        /// Voices the user recorded themselves. Empty until access is granted.
        var personal: [AVSpeechSynthesisVoice]
        /// Voices in the languages the user reads.
        var mine: [AVSpeechSynthesisVoice]
        var rest: [AVSpeechSynthesisVoice]
    }

    /// Personal voices first, then the user's languages, then everything else.
    /// Each group is sorted by name; the groups are separated in the menu.
    static func grouped() -> Groups {
        let mineCodes = Set(Locale.preferredLanguages.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        })
        let byName = AVSpeechSynthesisVoice.speechVoices().sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let isMine = { (v: AVSpeechSynthesisVoice) in
            mineCodes.contains(Locale(identifier: v.language).language.languageCode?.identifier ?? v.language)
        }
        let personal = byName.filter(isPersonal)
        let others = byName.filter { !isPersonal($0) }
        return Groups(personal: personal,
                      mine: others.filter(isMine),
                      rest: others.filter { !isMine($0) })
    }

    static func isPersonal(_ voice: AVSpeechSynthesisVoice) -> Bool {
        guard #available(macOS 14.0, *) else { return false }
        return voice.voiceTraits.contains(.isPersonalVoice)
    }

    /// Asks for access to the user's Personal Voice. The first call puts up the
    /// system prompt; later calls just report what was decided. Personal voices
    /// do not appear in `grouped()` until this returns `.granted`.
    /// The completion runs on the main thread.
    static func requestPersonalVoiceAccess(_ completion: @escaping (PersonalVoiceAccess) -> Void) {
        guard #available(macOS 14.0, *) else {
            DispatchQueue.main.async { completion(.unsupported) }
            return
        }
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            let access: PersonalVoiceAccess
            switch status {
            case .authorized: access = .granted
            case .unsupported: access = .unsupported
            case .denied, .notDetermined: access = .denied
            @unknown default: access = .denied
            }
            DispatchQueue.main.async { completion(access) }
        }
    }

    static func title(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) — \(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)"
    }

    static var systemDefault: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: nil)
    }
}
