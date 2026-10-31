import AppKit
import SwiftUI

@main
struct PRMonitorApp: App {
    @StateObject private var model = MonitorModel()

    private var maximumListHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return max(100, (screen?.visibleFrame.height ?? 800) - 190)
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent notifications")
                        .font(.headline)
                    Spacer()
                    if model.isPolling { ProgressView().controlSize(.small) }
                }

                if model.events.isEmpty {
                    Text("No notifications yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.events) { event in
                                Button {
                                    NSWorkspace.shared.open(event.url)
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: event.kind.symbol)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.kind.title).fontWeight(.medium)
                                            Text(event.body).lineLimit(2)
                                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: maximumListHeight)
                }

                Divider()
                if let warning = model.notificationWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastPoll = model.lastPoll {
                    Text("Last checked \(lastPoll.formatted(date: .omitted, time: .shortened)) · Every 5 min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Check now") { Task { await model.poll() } }
                        .disabled(model.isPolling)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
            }
            .padding(14)
            .frame(width: 360)
        } label: {
            Image(systemName: model.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                .accessibilityLabel("PR Monitor")
        }
        .menuBarExtraStyle(.window)
    }
}
