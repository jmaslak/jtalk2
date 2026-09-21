// The optional click played on each keystroke.
//
// Three earlier approaches were wrong, each for its own reason:
//
//   NSSound             blocks ~0.12s on first play and refuses to restart while
//                       still sounding, so fast typing stutters and drops clicks.
//   AudioServices       fast, but gated by System Settings ▸ Sound ▸ "Play user
//                       interface sound effects" and reports nothing when that
//                       is off, so the click silently never happens.
//   AVAudioPlayer pool  rewinding with `currentTime = 0` is a synchronous seek
//                       costing 12-32ms — landing on every keystroke.
//
// So: one audio engine, the sound decoded once into a buffer, and a handful of
// player nodes taking turns. Scheduling a buffer costs well under a millisecond
// and separate nodes mix, so overlapping clicks overlap instead of queueing.

import AVFoundation
import Foundation

final class KeyClicker {
    /// The stock system click. A different .aiff here changes the sound.
    static let defaultSoundURL = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")

    /// Quieter than a full-volume alert: this fires on every keystroke.
    static let volume: Float = 0.6

    /// Tink rings for over half a second, which drones when you are typing.
    /// Only the opening transient is kept, faded out so the cut does not pop.
    static let clickLength: TimeInterval = 0.12

    /// Exposed so tests can tap the output and confirm sound really comes out.
    let engine = AVAudioEngine()

    /// False when the sound or the audio engine could not be set up, in which
    /// case the option is disabled rather than silently doing nothing.
    var isAvailable: Bool { buffer != nil }

    /// True once the audio engine is running and ready to click.
    var isReady: Bool { buffer != nil && engine.isRunning }

    private var buffer: AVAudioPCMBuffer?
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0

    init(soundURL: URL = KeyClicker.defaultSoundURL, overlapping: Int = 6) {
        guard let file = try? AVAudioFile(forReading: soundURL),
              let whole = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: whole)) != nil,
              let clip = Self.opening(of: whole, seconds: Self.clickLength) else { return }

        for _ in 0..<max(1, overlapping) {
            let node = AVAudioPlayerNode()
            node.volume = Self.volume
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: clip.format)
            nodes.append(node)
        }
        buffer = clip
    }

    /// Starts the audio engine. Called when the user switches key clicks on, so
    /// that the first keystroke does not pay for it — and so that the audio
    /// device is left alone entirely for anyone who never turns clicks on.
    @discardableResult
    func prepare() -> Bool {
        guard buffer != nil else { return false }
        guard !engine.isRunning else { return true }
        guard (try? engine.start()) != nil else { return false }
        nodes.forEach { $0.play() }
        return true
    }

    deinit {
        if engine.isRunning {
            engine.stop()
        }
    }

    /// Starts a click. Returns false if there was no sound to play.
    @discardableResult
    func click() -> Bool {
        guard prepare(), let buffer, !nodes.isEmpty else { return false }
        let node = nodes[next]
        next = (next + 1) % nodes.count
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    /// The opening `seconds` of a buffer, with the tail faded out so that
    /// cutting the sound short does not pop.
    private static func opening(of source: AVAudioPCMBuffer, seconds: TimeInterval) -> AVAudioPCMBuffer? {
        let frames = min(AVAudioFrameCount(seconds * source.format.sampleRate), source.frameLength)
        guard frames > 0,
              let input = source.floatChannelData,
              let clip = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frames),
              let output = clip.floatChannelData else { return nil }

        clip.frameLength = frames
        let fadeFrames = max(1, Int(Double(frames) * 0.35))
        let fadeStart = Int(frames) - fadeFrames
        for channel in 0..<Int(source.format.channelCount) {
            for frame in 0..<Int(frames) {
                let sample = input[channel][frame]
                let gain = frame < fadeStart ? 1 : 1 - Float(frame - fadeStart) / Float(fadeFrames)
                output[channel][frame] = sample * gain
            }
        }
        return clip
    }
}
