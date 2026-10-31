import Foundation

struct PullKey: Hashable {
    let owner: String
    let repository: String
    let number: Int

    var id: String { "\(owner.lowercased())/\(repository.lowercased())#\(number)" }
    var label: String { "\(owner)/\(repository)#\(number)" }

    init(owner: String, repository: String, number: Int) {
        self.owner = owner
        self.repository = repository
        self.number = number
    }

    init?(id: String) {
        let halves = id.split(separator: "#", omittingEmptySubsequences: false)
        guard halves.count == 2, let number = Int(halves[1]) else { return nil }
        let repositoryParts = halves[0].split(separator: "/", omittingEmptySubsequences: false)
        guard repositoryParts.count == 2 else { return nil }
        self.init(owner: String(repositoryParts[0]), repository: String(repositoryParts[1]), number: number)
    }

    init?(apiURL: URL) {
        let parts = apiURL.pathComponents
        guard let index = parts.firstIndex(of: "repos"),
              parts.count > index + 4,
              parts[index + 3] == "pulls",
              let number = Int(parts[index + 4]) else { return nil }
        self.init(owner: parts[index + 1], repository: parts[index + 2], number: number)
    }
}

struct SearchResponse: Decodable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [SearchIssue]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case incompleteResults = "incomplete_results"
        case items
    }
}

struct SearchIssue: Decodable {
    let pullRequest: SearchPullLink

    enum CodingKeys: String, CodingKey {
        case pullRequest = "pull_request"
    }
}

struct SearchPullLink: Decodable {
    let url: URL
}

struct PullRequest: Decodable {
    let title: String
    let htmlURL: URL
    let body: String?
    let user: GitHubUser
    let head: PullHead
    let state: String
    let mergedAt: String?
    let nodeID: String

    enum CodingKeys: String, CodingKey {
        case title, body, user, head, state
        case htmlURL = "html_url"
        case mergedAt = "merged_at"
        case nodeID = "node_id"
    }

    func belongs(to username: String) -> Bool {
        if user.login.caseInsensitiveCompare(username) == .orderedSame { return true }
        guard let body else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: username)
        let pattern = "(?<![A-Za-z0-9-])@\(escaped)(?![A-Za-z0-9-])"
        return body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

struct GitHubUser: Decodable {
    let login: String
}

struct PullHead: Decodable {
    let sha: String
}

struct CheckRunsResponse: Decodable {
    let totalCount: Int
    let checkRuns: [CheckRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }
}

struct CheckRun: Decodable {
    let status: String
    let conclusion: String?
}

struct CommitStatusResponse: Decodable {
    let statuses: [CommitStatus]
}

struct CommitStatus: Decodable {
    let state: String
}

struct CheckSummary {
    let hasChecks: Bool
    let isPending: Bool
    let failed: Bool

    init(runs: [CheckRun], statuses: [CommitStatus]) {
        hasChecks = !runs.isEmpty || !statuses.isEmpty
        isPending = runs.contains { $0.status != "completed" }
            || statuses.contains { $0.state == "pending" }
        failed = runs.contains {
            $0.status == "completed"
                && !["success", "neutral", "skipped"].contains($0.conclusion ?? "")
        } || statuses.contains { $0.state != "success" && $0.state != "pending" }
    }
}

struct PullSnapshot: Codable {
    var headSHA: String?
    var checksNotified = false
    var queued: Bool?
    var mergedNotified = false
    var closedAt: Date?
}

enum EventKind: String, Codable {
    case checksPassed
    case checksFailed
    case merged
    case removedFromQueue

    var title: String {
        switch self {
        case .checksPassed: return "✅ PR checks passed"
        case .checksFailed: return "❌ PR checks failed"
        case .merged: return "PR merged"
        case .removedFromQueue: return "PR removed from merge queue"
        }
    }

    var symbol: String {
        switch self {
        case .checksPassed: return "checkmark.circle.fill"
        case .checksFailed: return "xmark.circle.fill"
        case .merged: return "arrow.triangle.merge"
        case .removedFromQueue: return "arrow.uturn.backward.circle.fill"
        }
    }
}

struct MonitorEvent: Codable, Identifiable {
    let id: UUID
    let kind: EventKind
    let pullLabel: String
    let pullTitle: String
    let url: URL
    let date: Date

    init(kind: EventKind, key: PullKey, pull: PullRequest) {
        id = UUID()
        self.kind = kind
        pullLabel = key.label
        pullTitle = pull.title
        url = pull.htmlURL
        date = Date()
    }

    var body: String { "\(pullLabel): \(pullTitle)" }
}

struct SavedState: Codable {
    var identity = ""
    var initialized = false
    var pulls: [String: PullSnapshot] = [:]
    var events: [MonitorEvent] = []
}
