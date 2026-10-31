import Combine
import Foundation

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var events: [MonitorEvent] = []
    @Published private(set) var lastPoll: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var notificationWarning: String?
    @Published private(set) var isPolling = false

    private let store = StateStore()
    private let notifications = NotificationService()
    private var state: SavedState

    init() {
        do {
            state = try store.load()
            events = state.events
        } catch {
            state = SavedState()
            lastError = "Could not read saved state: \(error.localizedDescription)"
        }

        Task {
            await notifications.requestPermission()
            notificationWarning = await notifications.deliveryWarning()
        }
        Task {
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        do {
            let configuration = try Configuration.load()
            let client = GitHubClient(configuration: configuration)
            var nextState = state
            if nextState.identity != configuration.identity {
                nextState = SavedState()
                nextState.identity = configuration.identity
            }

            var keys = try await client.matchingPullKeys()
            for (id, snapshot) in nextState.pulls where snapshot.closedAt == nil {
                if let key = PullKey(id: id) { keys.insert(key) }
            }

            var pulls: [(PullKey, PullRequest)] = []
            var errors: [String] = []
            for key in keys.sorted(by: { $0.id < $1.id }) {
                do {
                    let pull = try await client.pullRequest(for: key)
                    if pull.belongs(to: configuration.username) {
                        pulls.append((key, pull))
                    } else {
                        nextState.pulls.removeValue(forKey: key.id)
                    }
                } catch {
                    errors.append("\(key.label): \(error.localizedDescription)")
                }
            }

            var queueMembership: [String: Bool]?
            do {
                queueMembership = try await client.queueMembership(for: pulls.map { $0.1 })
            } catch {
                errors.append(error.localizedDescription)
            }

            var newEvents: [MonitorEvent] = []
            for (key, pull) in pulls {
                var snapshot = nextState.pulls[key.id] ?? PullSnapshot()
                let merged = pull.mergedAt != nil

                if let queued = queueMembership?[pull.nodeID] {
                    if snapshot.queued == true && !queued && !merged && nextState.initialized {
                        newEvents.append(MonitorEvent(kind: .removedFromQueue, key: key, pull: pull))
                    }
                    snapshot.queued = queued
                }

                if merged && !snapshot.mergedNotified {
                    if nextState.initialized {
                        newEvents.append(MonitorEvent(kind: .merged, key: key, pull: pull))
                    }
                    snapshot.mergedNotified = true
                }

                if pull.state == "open" {
                    do {
                        let checks = try await client.checks(for: key, sha: pull.head.sha)
                        if snapshot.headSHA != pull.head.sha {
                            snapshot.headSHA = pull.head.sha
                            snapshot.checksNotified = false
                        }
                        if checks.isPending {
                            snapshot.checksNotified = false
                        } else if checks.hasChecks && !snapshot.checksNotified {
                            if nextState.initialized {
                                newEvents.append(MonitorEvent(
                                    kind: checks.failed ? .checksFailed : .checksPassed,
                                    key: key,
                                    pull: pull
                                ))
                            }
                            snapshot.checksNotified = true
                        }
                    } catch {
                        errors.append("\(key.label) checks: \(error.localizedDescription)")
                    }
                    snapshot.closedAt = nil
                } else {
                    snapshot.closedAt = snapshot.closedAt ?? Date()
                }
                nextState.pulls[key.id] = snapshot
            }

            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            nextState.pulls = nextState.pulls.filter { $0.value.closedAt.map { $0 >= cutoff } ?? true }
            nextState.events = Array((Array(newEvents.reversed()) + nextState.events).prefix(30))
            nextState.initialized = true
            try store.save(nextState)

            state = nextState
            events = nextState.events
            lastPoll = Date()
            for event in newEvents {
                do {
                    try await notifications.send(event)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            notificationWarning = await notifications.deliveryWarning()
            lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        } catch {
            lastError = error.localizedDescription
        }
    }
}
