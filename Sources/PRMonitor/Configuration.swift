import Foundation

struct Configuration {
    let webURL: URL
    let apiURL: URL
    let graphQLURL: URL
    let token: String
    let username: String

    var identity: String {
        "\(webURL.absoluteString.lowercased())|\(username.lowercased())"
    }

    static func load() throws -> Configuration {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultFile = home.appendingPathComponent(".config/pr-monitor/.env")
        let localFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".env")
        let bundle = Bundle.main.bundleURL
        let bundledProjectFile: URL? = bundle.pathExtension == "app"
            && bundle.deletingLastPathComponent().lastPathComponent == "dist"
            ? bundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env")
            : nil
        let candidates = [defaultFile, bundledProjectFile, localFile].compactMap { $0 }
        let file: URL?

        if let override = environment["PR_MONITOR_ENV_FILE"], !override.isEmpty {
            file = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            file = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        }

        guard let file, FileManager.default.fileExists(atPath: file.path) else {
            let checkedPaths = candidates.map(\.path).joined(separator: ", ")
            throw ConfigurationError.message("No .env file found. Checked: \(checkedPaths)")
        }

        let contents = try String(contentsOf: file, encoding: .utf8)
        var values: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let assignment = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)) : trimmed
            let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.first == "\"" && value.last == "\"" || value.first == "'" && value.last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }

        guard let rawURL = values["GHE_URL"],
              let url = URL(string: rawURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw ConfigurationError.message("GHE_URL must be an HTTPS GitHub Enterprise host in \(file.path)")
        }
        guard let token = values["GHE_TOKEN"], !token.isEmpty else {
            throw ConfigurationError.message("Set GHE_TOKEN in \(file.path)")
        }
        guard let username = values["GHE_USERNAME"],
              !username.isEmpty,
              username.range(of: "^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$", options: .regularExpression) != nil else {
            throw ConfigurationError.message("Set a valid GHE_USERNAME in \(file.path)")
        }

        var base = components
        base.path = ""
        guard let webURL = base.url else {
            throw ConfigurationError.message("Invalid GHE_URL in \(file.path)")
        }
        let isGitHubCloud = host.lowercased() == "github.com"
        let apiURL = isGitHubCloud
            ? URL(string: "https://api.github.com")!
            : webURL.appendingPathComponent("api").appendingPathComponent("v3")
        let graphQLURL = isGitHubCloud
            ? URL(string: "https://api.github.com/graphql")!
            : webURL.appendingPathComponent("api").appendingPathComponent("graphql")
        return Configuration(
            webURL: webURL,
            apiURL: apiURL,
            graphQLURL: graphQLURL,
            token: token,
            username: username
        )
    }
}

enum ConfigurationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}
