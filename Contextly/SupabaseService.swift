import Foundation

enum SupabaseServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Add a Supabase URL and publishable key to connect the app."
        case .invalidResponse:
            return "Supabase returned an unexpected response."
        case .requestFailed(let statusCode, let message):
            return "Supabase request failed (\(statusCode)): \(message)"
        }
    }
}

struct SupabaseConfiguration: Equatable, Sendable {
    var projectURL: String
    var publishableKey: String

    var isConfigured: Bool {
        URL(string: projectURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil &&
        !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var baseURL: URL? {
        URL(string: projectURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

final class SupabaseService {
    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            return DateParser.parse(value) ?? Date()
        }
        encoder.dateEncodingStrategy = .iso8601
    }

    func fetchUsers() async throws -> [ContextlyUser] {
        guard configuration.isConfigured else { return DemoData.users }
        let request = try makeRequest(path: "/rest/v1/contextly_users", queryItems: [
            URLQueryItem(name: "select", value: "id,username,display_name"),
            URLQueryItem(name: "order", value: "display_name.asc")
        ])
        return try await send(request)
    }

    func fetchMessages(conversationId: UUID) async throws -> [ContextlyMessage] {
        guard configuration.isConfigured else { return DemoData.messages }
        let request = try makeRequest(path: "/rest/v1/contextly_messages", queryItems: [
            URLQueryItem(name: "conversation_id", value: "eq.\(conversationId.uuidString)"),
            URLQueryItem(name: "select", value: "id,conversation_id,sender_id,content,created_at"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        return try await send(request)
    }

    func sendMessage(conversationId: UUID, senderId: UUID, content: String) async throws -> ContextlyMessage {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw SupabaseServiceError.invalidResponse
        }

        guard configuration.isConfigured else {
            return ContextlyMessage(
                id: UUID(),
                conversationId: conversationId,
                senderId: senderId,
                content: trimmedContent,
                createdAt: Date()
            )
        }

        let body = NewMessage(conversationId: conversationId, senderId: senderId, content: trimmedContent)
        var request = try makeRequest(path: "/rest/v1/contextly_messages", method: "POST")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        let created: [ContextlyMessage] = try await send(request)
        guard let message = created.first else { throw SupabaseServiceError.invalidResponse }
        return message
    }

    func searchMessages(conversationId: UUID, query: String) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        guard configuration.isConfigured else {
            let terms = semanticDemoTerms(for: trimmedQuery)
            let ranked = DemoData.messages
                .map { message in
                    let score = terms.reduce(0) { partialResult, term in
                        message.content.localizedCaseInsensitiveContains(term) ? partialResult + 1 : partialResult
                    }
                    return (message: message, score: score)
                }
                .sorted { left, right in
                    if left.score == right.score {
                        return left.message.createdAt > right.message.createdAt
                    }
                    return left.score > right.score
                }

            let matches = ranked.filter { $0.score > 0 }
            let visibleResults = matches.isEmpty ? Array(ranked.prefix(3)) : Array(matches.prefix(5))
            return visibleResults.map {
                SearchResult(id: UUID(), message: $0.message, score: Double(max($0.score, 1)) / Double(max(terms.count, 1)))
            }
        }

        let body = SearchRequest(conversationId: conversationId, query: trimmedQuery, limit: 8)
        var request = try makeRequest(path: "/functions/v1/contextly-search", method: "POST", useRestHeaders: false)
        request.httpBody = try encoder.encode(body)
        let response: [SearchResponse] = try await send(request)
        return response.map { SearchResult(id: $0.id, message: $0.message, score: $0.score) }
    }

    private func semanticDemoTerms(for query: String) -> [String] {
        let lowercased = query.lowercased()
        var terms = lowercased.split(separator: " ").map(String.init)
        if lowercased.contains("db") || lowercased.contains("database") {
            terms.append("database")
        }
        if lowercased.contains("meet") || lowercased.contains("when") || lowercased.contains("where") {
            terms.append(contentsOf: ["meet", "klaus", "tomorrow"])
        }
        if lowercased.contains("backend") {
            terms.append("backend")
        }
        return Array(Set(terms.filter { $0.count > 2 }))
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        useRestHeaders: Bool = true
    ) throws -> URLRequest {
        guard let baseURL = configuration.baseURL else { throw SupabaseServiceError.missingConfiguration }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SupabaseServiceError.invalidResponse
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw SupabaseServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if useRestHeaders {
            request.setValue("public", forHTTPHeaderField: "Content-Profile")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode, message)
        }

        return try decoder.decode(T.self, from: data)
    }
}

private struct NewMessage: Encodable, Sendable {
    let conversationId: UUID
    let senderId: UUID
    let content: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content
    }
}

private struct SearchRequest: Encodable, Sendable {
    let conversationId: UUID
    let query: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case query
        case limit
    }
}

private struct SearchResponse: Decodable, Sendable {
    let id: UUID
    let message: ContextlyMessage
    let score: Double?
}

private enum DateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
