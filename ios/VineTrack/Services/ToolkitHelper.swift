import Foundation

nonisolated enum ToolkitError: Error, Sendable, LocalizedError {
    case invalidURL
    case noResponse
    case httpError(Int)
    case decodingError(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid toolkit URL"
        case .noResponse: return "No response from AI"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        }
    }
}

nonisolated struct ToolkitTextPart: Codable, Sendable {
    let type: String
    let text: String
}

nonisolated struct ToolkitMessageWithParts: Codable, Sendable {
    let role: String
    let content: [ToolkitTextPart]
}

nonisolated struct ToolkitLLMRequest: Codable, Sendable {
    let messages: [ToolkitMessageWithParts]
}

nonisolated struct ToolkitLLMResponse: Codable, Sendable {
    let completion: String?
    let text: String?
    let content: String?
    let result: String?
    let response: String?
    let message: ToolkitResponseMessage?

    var extractedText: String? {
        completion ?? text ?? content ?? result ?? response ?? message?.content
    }
}

nonisolated struct ToolkitResponseMessage: Codable, Sendable {
    let content: String?
}

enum ToolkitHelper {
    private static let maxRetries = 3

    static func sendChat(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let baseURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/llm/text") else {
            throw ToolkitError.invalidURL
        }

        var combinedPrompt = ""
        if let sys = systemPrompt, !sys.isEmpty {
            combinedPrompt = "\(sys)\n\n\(prompt)"
        } else {
            combinedPrompt = prompt
        }

        let messages = [ToolkitMessageWithParts(
            role: "user",
            content: [ToolkitTextPart(type: "text", text: combinedPrompt)]
        )]

        let requestBody = ToolkitLLMRequest(messages: messages)

        let bodyData = try JSONEncoder().encode(requestBody)

        var lastError: Error = ToolkitError.noResponse

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = Double(1 << attempt)
                try await Task.sleep(for: .seconds(delay))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let secretKey = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
            if !secretKey.isEmpty {
                request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = bodyData
            request.timeoutInterval = 60

            print("[ToolkitHelper] Attempt \(attempt + 1) → \(url.absoluteString)")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 500 {
                        let bodyString = String(data: data, encoding: .utf8) ?? "no body"
                        print("[ToolkitHelper] HTTP \(httpResponse.statusCode): \(bodyString.prefix(500))")
                        lastError = ToolkitError.httpError(httpResponse.statusCode)
                        continue
                    }

                    if httpResponse.statusCode != 200 {
                        let bodyString = String(data: data, encoding: .utf8) ?? "no body"
                        print("[ToolkitHelper] HTTP \(httpResponse.statusCode): \(bodyString.prefix(500))")
                        throw ToolkitError.httpError(httpResponse.statusCode)
                    }
                }

                if let decoded = try? JSONDecoder().decode(ToolkitLLMResponse.self, from: data),
                   let text = decoded.extractedText, !text.isEmpty {
                    return text
                }

                if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
                    return rawString
                }

                lastError = ToolkitError.noResponse
            } catch let error as ToolkitError {
                if case .httpError(let code) = error, code >= 500 {
                    lastError = error
                    continue
                }
                throw error
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }
}
