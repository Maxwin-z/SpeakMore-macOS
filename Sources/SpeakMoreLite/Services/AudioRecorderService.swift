import AVFoundation

enum TranscriptionError: LocalizedError {
    case audioFormatError(String)

    var errorDescription: String? {
        switch self {
        case .audioFormatError(let msg): return msg
        }
    }
}

class AudioRecorderService {
    private var audioEngine: AVAudioEngine?
    private let targetSampleRate: Double = 16000.0

    var onAudioSamples: (([Float]) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    func startRecording() throws {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.audioFormatError("无法创建目标音频格式")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TranscriptionError.audioFormatError(
                "无法创建从 \(inputFormat.sampleRate)Hz 到 \(targetSampleRate)Hz 的转换器"
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.floatChannelData {
                let frameLength = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(
                    start: channelData[0],
                    count: frameLength
                ))
                self.onAudioSamples?(samples)

                var sumOfSquares: Float = 0
                for i in 0..<frameLength {
                    let s = channelData[0][i]
                    sumOfSquares += s * s
                }
                let rms = sqrtf(sumOfSquares / Float(max(frameLength, 1)))
                self.onAudioLevel?(rms)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}
