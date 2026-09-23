//
//  IntegrationsSettings.swift
//  NotBoringNotch
//
//  Settings for the Reminder Channel: the port and token a client needs, where they are
//  published, and the one curl command that proves it works.
//

import AppKit
import Defaults
import SwiftUI

struct IntegrationsSettings: View {
    @ObservedObject var channel = ReminderChannel.shared
    @Default(.reminderChannelEnabled) private var isEnabled
    @Default(.reminderChannelPort) private var port

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminder Channel")
                            .font(.headline)
                        Text("Let another app or a script raise a reminder in the notch. The channel listens on 127.0.0.1, so nothing on your network can reach it, and it needs the token below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .reminderChannelEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }

                statusRow
            } header: {
                Text("Channel")
            }

            if isEnabled {
                Section {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $port, format: .number)
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
                        Text(channel.token)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180, alignment: .trailing)
                        HStack(spacing: 6) {
                            Button("Copy") { copy(channel.token) }
                            Button("Regenerate") { channel.regenerateToken() }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discovery file")
                            Text(channel.discoveryPath ?? "Written once the channel is listening.")
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

                Section {
                    Text(example)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Copy example") { copy(example) }
                        Button("Send test reminder") { channel.sendTestReminder() }
                    }
                } header: {
                    Text("Try it")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch channel.status {
        case .off:
            EmptyView()
        case let .listening(port):
            Label("Listening on 127.0.0.1:\(port)", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var example: String {
        """
        curl -X POST \(channel.endpoint) \\
          -H "Authorization: Bearer \(channel.token)" \\
          -H "Content-Type: application/json" \\
          -d '{"icon":{"kind":"sf_symbol","value":"hammer"},
               "title":"Build finished",
               "subtitle":"awen · session-42",
               "body":"12 files typechecked, 0 errors.",
               "duration":6}'
        """
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealDiscoveryFile() {
        guard let path = channel.discoveryPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
