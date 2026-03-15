import Foundation

class MultimodalService {

    private func log(_ msg: String) {
        let message = "[MultimodalService] \(msg)"
        NSLog("%@", message)
        DispatchQueue.main.async { DebugLogger.shared.log(message) }
    }

    /// Stream transcription from raw audio samples using a multimodal model.
    func stream(audioSamples: [Float], systemPrompt: String?, config: MultimodalConfig) -> AsyncThrowingStream<String, Error> {
        let audioBase64 = Self.encodeAudioToBase64WAV(samples: audioSamples)
        log("Encoded audio: \(audioSamples.count) samples → \(audioBase64.count / 1024)KB base64 WAV")

        if config.provider.usesGeminiFormat {
            return streamGemini(audioBase64: audioBase64, systemPrompt: systemPrompt, config: config)
        } else {
            return streamOpenAICompatible(audioBase64: audioBase64, systemPrompt: systemPrompt, config: config)
        }
    }

    /// Non-streaming text completion (used for context profiling).
    func completeText(message: String, systemPrompt: String, config: MultimodalConfig) async throws -> String {
        if config.provider.usesGeminiFormat {
            return try await completeTextGemini(message: message, systemPrompt: systemPrompt, config: config)
        } else {
            return try await completeTextOpenAI(message: message, systemPrompt: systemPrompt, config: config)
        }
    }

    // MARK: - Audio Encoding

    static func encodeAudioToBase64WAV(samples: [Float]) -> String {
        let sampleRate: Double = 16000
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(bitsPerSample / 8))

        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)

        data.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize)
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels
        data.append(Data(bytes: &channels, count: 2))
        var sRate = UInt32(sampleRate)
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = byteRate
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign
        data.append(Data(bytes: &bAlign, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))

        data.append(contentsOf: "data".utf8)
        var dSize = dataSize
        data.append(Data(bytes: &dSize, count: 4))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clamped * 32767.0)
            data.append(Data(bytes: &int16Sample, count: 2))
        }

        return data.base64EncodedString()
    }

    // MARK: - Gemini Native API

    private func streamGemini(audioBase64: String, systemPrompt: String?, config: MultimodalConfig) -> AsyncThrowingStream<String, Error> {
        let modelId = config.effectiveModelId
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(endpoint)/models/\(modelId):streamGenerateContent?key=\(config.apiKey)&alt=sse"

        log("Starting Gemini stream: model=\(modelId)")
        let logFn = self.log

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: urlString) else {
                        throw MultimodalServiceError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var body: [String: Any] = [:]

                    if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                        body["systemInstruction"] = [
                            "parts": [["text": systemPrompt]]
                        ]
                    }

                    body["contents"] = [[
                        "role": "user",
                        "parts": [
                            ["text": "请将以下语音内容准确转写为文字，直接输出转写结果，不要添加任何解释。"],
                            ["inlineData": [
                                "mimeType": "audio/wav",
                                "data": audioBase64
                            ]]
                        ]
                    ]]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    logFn("Sending POST to Gemini (\(modelId))")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse {
                        logFn("HTTP response: \(http.statusCode)")
                        if !(200...299).contains(http.statusCode) {
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                                if errorBody.count > 500 { break }
                            }
                            throw MultimodalServiceError.httpError(http.statusCode, String(errorBody.prefix(300)))
                        }
                    }

                    var chunkCount = 0
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else {
                            continue
                        }

                        for part in parts {
                            if let text = part["text"] as? String {
                                chunkCount += 1
                                continuation.yield(text)
                            }
                        }
                    }

                    logFn("Gemini stream finished, total chunks: \(chunkCount)")
                    continuation.finish()
                } catch {
                    logFn("Gemini stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - OpenAI-Compatible API

    private func streamOpenAICompatible(audioBase64: String, systemPrompt: String?, config: MultimodalConfig) -> AsyncThrowingStream<String, Error> {
        let modelId = config.effectiveModelId
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(endpoint)/chat/completions"

        log("Starting OpenAI-compatible stream: model=\(modelId)")
        let logFn = self.log

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: urlString) else {
                        throw MultimodalServiceError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

                    var messages: [[String: Any]] = []

                    if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                        messages.append(["role": "system", "content": systemPrompt])
                    }

                    // DashScope models require data URI prefix for base64 audio
                    let audioData: String
                    if config.provider == .dashscope {
                        audioData = "data:;base64,\(audioBase64)"
                    } else {
                        audioData = audioBase64
                    }

                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "input_audio",
                                "input_audio": [
                                    "data": audioData,
                                    "format": "wav"
                                ]
                            ] as [String: Any],
                            [
                                "type": "text",
                                "text": "请将以上语音内容准确转写为文字，直接输出转写结果，不要添加任何解释。"
                            ] as [String: Any]
                        ]
                    ])

                    var body: [String: Any] = [
                        "model": modelId,
                        "messages": messages,
                        "stream": true,
                        "modalities": ["text"]
                    ]

                    if config.provider == .dashscope {
                        body["stream_options"] = ["include_usage": true]
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    logFn("Sending POST to \(config.provider.displayName) (\(modelId))")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse {
                        logFn("HTTP response: \(http.statusCode)")
                        if !(200...299).contains(http.statusCode) {
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                                if errorBody.count > 500 { break }
                            }
                            throw MultimodalServiceError.httpError(http.statusCode, String(errorBody.prefix(300)))
                        }
                    }

                    var chunkCount = 0
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        chunkCount += 1
                        continuation.yield(content)
                    }

                    logFn("OpenAI-compatible stream finished, total chunks: \(chunkCount)")
                    continuation.finish()
                } catch {
                    logFn("OpenAI-compatible stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Text-Only Completions (for context profiling)

    private func completeTextGemini(message: String, systemPrompt: String, config: MultimodalConfig) async throws -> String {
        let modelId = config.effectiveModelId
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(endpoint)/models/\(modelId):generateContent?key=\(config.apiKey)"

        guard let url = URL(string: urlString) else {
            throw MultimodalServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": message]]]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw MultimodalServiceError.httpError(http.statusCode, String(errorBody.prefix(300)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw MultimodalServiceError.invalidResponse
        }

        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private func completeTextOpenAI(message: String, systemPrompt: String, config: MultimodalConfig) async throws -> String {
        let modelId = config.effectiveModelId
        let endpoint = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(endpoint)/chat/completions"

        guard let url = URL(string: urlString) else {
            throw MultimodalServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": message]
            ],
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw MultimodalServiceError.httpError(http.statusCode, String(errorBody.prefix(300)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw MultimodalServiceError.invalidResponse
        }

        return content
    }
}

enum MultimodalServiceError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .httpError(let code, let body): return "API 返回 HTTP \(code): \(body)"
        case .invalidResponse: return "API 返回无效响应"
        }
    }
}
