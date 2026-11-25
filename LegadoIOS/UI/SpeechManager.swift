import Foundation
import AVFoundation

/// 简单朗读（系统 TTS）
final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureSession()
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        stop()
        self.completion = completion
        let cleaned = TextCleaner.normalize(text)
        guard !cleaned.isEmpty else { return }
        // 分段落朗读，避免单条过长被系统截断
        let chunks = Self.chunk(cleaned, size: 400)
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.48
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {
            let block = completion
            completion = nil
            DispatchQueue.main.async { block?() }
        }
    }

    private static func chunk(_ text: String, size: Int) -> [String] {
        guard text.count > size else { return [text] }
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.count >= size {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
