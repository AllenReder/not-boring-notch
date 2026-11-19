//
//  IntegrationsSettings.swift
//  NotBoringNotch
//
//  Settings for the Notch Channel: the port and token a client needs, where they are published,
//  a way to see a notification without writing a client, and what the Inbox and
//  the closed notch do with what arrives.
//

import AppKit
import Defaults
import SwiftUI

struct IntegrationsSettings: View {
    @ObservedObject var channel = NotchChannel.shared
    @Default(.notchChannelEnabled) private var isEnabled
    @Default(.notchChannelPort) private var port

    /// The token is a secret that ends up in screenshots. It is shown only when asked for; copying
    /// it, or the example, never needs it on screen.
    @State private var revealsToken = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notch Channel")
                            .font(.headline)
                        Text("Let a script, a hook or an agent show notifications in the notch. The channel listens on 127.0.0.1, so nothing on your network can reach it, and it needs the token below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .notchChannelEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }

                statusRow
            } header: {
                Text("Channel")
            }

            if isEnabled {
                connectionSection
                tryItSection
                inboxSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Integrations")
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Port")
                Spacer()
                // A port is an identifier, not a quantity: no thousands separator. The row already
                // says "Port", so the field's own label stays hidden.
                TextField("Port", value: $port, format: .number.grouping(.never))
                    .labelsHidden()
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: port) { _, newValue in
                        port = min(max(newValue, 1024), 65535)
                    }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token")
                    Text("Any process running as you can read this. It keeps web pages and sandboxed apps out, which is what it is for.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                Text(revealsToken ? channel.token : String(repeating: "•", count: 12))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .trailing)
                Button {
                    revealsToken.toggle()
                } label: {
                    Image(systemName: revealsToken ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealsToken ? Text("Hide Token") : Text("Show Token"))
                HStack(spacing: 6) {
                    Button("Copy") { copy(channel.token) }
                    Button("Regenerate") { channel.regenerateToken() }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discovery file")
                    Text(channel.discoveryPath ?? String(localized: "Written once the channel is listening."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                if channel.discoveryPath != nil {
                    Button("Show in Finder") { revealDiscoveryFile() }
                }
            }
        } header: {
            Text("Connection")
        }
    }

    private var tryItSection: some View {
        Section {
            Text(example(token: "$TOKEN"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                // The copy carries the real token, so it runs as pasted.
                Button("Copy Example") { copy(example(token: channel.token)) }
                Spacer()
                Button("Send Test Notification") { channel.deliver(testNotification) }
            }
        } header: {
            Text("Try it")
        } footer: {
            Text("The full protocol is in docs/notch-channel.md.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inboxSection: some View {
        Section {
            Defaults.Toggle(key: .notchChannelKeepsHistory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep notifications across restarts")
                    Text("The Inbox keeps the 50 most recent notifications you have not cleared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Notifications in the Inbox: \(channel.inbox.items.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Inbox") { channel.clearInbox() }
                    .disabled(channel.inbox.isEmpty)
            }
        } header: {
            Text("Inbox")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch channel.status {
        case .off:
            EmptyView()
        case let .listening(port):
            // Interpolated as text: as a number it would be formatted for the locale, "45,999".
            Label("Listening on 127.0.0.1:\(String(port))", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Try it

    /// The example as shown — `$TOKEN` — and as copied, with the real token in its place.
    private func example(token: String) -> String {
        """
        curl -X POST \(channel.endpoint) \\
          -H "Authorization: Bearer \(token)" \\
          -H "Content-Type: application/json" \\
          -d '{"source":"make",
               "icon":{"kind":"sf_symbol","value":"hammer"},
               "title":"Build finished",
               "subtitle":"12s · main",
               "body":"12 files typechecked, `0` errors.",
               "open":{"app":"com.apple.Terminal"}}'
        """
    }

    /// A fixture rather than a feature: the pane's own notification, so the shape can be seen
    /// without wiring up a client first.
    private var testNotification: ChannelNotification {
        ChannelNotification(
            id: UUID().uuidString,
            source: "settings",
            thread: nil,
            level: .active,
            icon: .symbol("bell.badge"),
            title: String(localized: "Test notification"),
            subtitle: String(localized: "From the Integrations settings"),
            body: String(localized: "This is what a notification looks like. Hover the notch to find it in the Inbox, where it stays until you clear it."),
            duration: 8,
            banner: .temporary,
            sound: .none,
            open: nil,
            actions: [],
            deliveredAt: Date()
        )
    }

    // MARK: - Helpers

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealDiscoveryFile() {
        guard let path = channel.discoveryPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
