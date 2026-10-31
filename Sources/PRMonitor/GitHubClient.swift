import Foundation

struct GitHubClient {
    let configuration: Configuration
    private let session = URLSession.shared

    func matchingPullKeys() async throws -> Set<PullKey> {
        let authorQuery = "is:pr is:open author:\(configuration.username)"
        let mentionQuery = "is:pr is:open \(configuration.username) in:body"
        let authored = try await search(query: authorQuery)
        let mentioned = try await search(query: mentionQuery)
        let issues = authored + mentioned
        return Set(issues.compactMap { PullKey(apiURL: $0.pullRequest.url) })
    }

    func pullRequest(for key: PullKey) async throws -> PullRequest {
        let url = repositoryURL(for: key)
            .appendingPathComponent("pulls")
            .appendingPathComponent(String(key.number))
        return try await get(url)
    }

    func checks(for key: PullKey, sha: String) async throws -> CheckSummary {
        let base = repositoryURL(for: key)
            .appendingPathComponent("commits")
            .appendingPathComponent(sha)
        var runs: [CheckRun] = []
        var page = 1
        while true {
            var components = URLComponents(url: base.appendingPathComponent("check-runs"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            let result: CheckRunsResponse = try await get(components.url!)
            runs.append(contentsOf: result.checkRuns)
            if runs.count >= result.totalCount || result.checkRuns.isEmpty { break }
            page += 1
        }
        let statuses: CommitStatusResponse = try await get(base.appendingPathComponent("status"))
        return CheckSummary(runs: runs, statuses: statuses.statuses)
    }

    func queueMembership(for pulls: [PullRequest]) async throws -> [String: Bool] {
        if pulls.isEmpty { return [:] }
        var result: [String: Bool] = [:]
        for offset in stride(from: 0, to: pulls.count, by: 50) {
            let batch = Array(pulls[offset..<min(offset + 50, pulls.count)])
            let ids = batch.map(\.nodeID)
            let query = "query($ids: [ID!]!) { nodes(ids: $ids) { ... on PullRequest { id mergeQueueEntry { id } } } }"
            let body = try JSONSerialization.data(withJSONObject: [
                "query": query,
                "variables": ["ids": ids]
            ])
            let response: QueueResponse = try await request(
                configuration.graphQLURL,
                method: "POST",
                body: body
            )
            if let errors = response.errors, !errors.isEmpty {
                throw GitHubError.message("Merge queue query: \(errors.map(\.message).joined(separator: "; "))")
            }
            guard let nodes = response.data?.nodes, nodes.count == batch.count else {
                throw GitHubError.message("Merge queue query returned incomplete data")
            }
            for node in nodes {
                guard let node else {
                    throw GitHubError.message("A PR was unavailable to the merge queue query")
                }
                result[node.id] = node.mergeQueueEntry != nil
            }
        }
        return result
    }

    private func search(query: String) async throws -> [SearchIssue] {
        var issues: [SearchIssue] = []
        var page = 1
        while true {
            var components = URLComponents(
                url: configuration.apiURL.appendingPathComponent("search").appendingPathComponent("issues"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            let response: SearchResponse = try await get(components.url!)
            if response.incompleteResults {
                throw GitHubError.message("GitHub returned incomplete search results")
            }
            if response.totalCount > 1000 {
                throw GitHubError.message("Search has over 1,000 results; narrow the account scope")
            }
            issues.append(contentsOf: response.items)
            if issues.count >= response.totalCount || response.items.isEmpty { break }
            page += 1
        }
        return issues
    }

    private func repositoryURL(for key: PullKey) -> URL {
        configuration.apiURL
            .appendingPathComponent("repos")
            .appendingPathComponent(key.owner)
            .appendingPathComponent(key.repository)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        try await request(url, method: "GET", body: nil)
    }

    private func request<T: Decodable>(_ url: URL, method: String, body: Data?) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PRMonitor/1.0", forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.message("GitHub returned a non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw GitHubError.message("GitHub HTTP \(http.statusCode): \(detail)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct APIErrorResponse: Decodable {
    let message: String
}

private struct QueueResponse: Decodable {
    let data: QueueData?
    let errors: [QueueError]?
}

private struct QueueData: Decodable {
    let nodes: [QueueNode?]
}

private struct QueueNode: Decodable {
    let id: String
    let mergeQueueEntry: QueueEntry?
}

private struct QueueEntry: Decodable {
    let id: String
}

private struct QueueError: Decodable {
    let message: String
}

enum GitHubError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}
