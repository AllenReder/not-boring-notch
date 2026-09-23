//
//  ReminderDetailView.swift
//  NotBoringNotch
//
//  A Reminder with the notch open: the icon and title from the closed slot, plus the body the
//  sender wrote, which the closed notch has no room for.
//

import SwiftUI

struct ReminderDetailView: View {
    let reminder: Reminder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ReminderIconView(icon: reminder.icon)
                    .padding(6)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(reminder.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = reminder.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                if let action = reminder.action {
                    Button(action.title) {
                        ReminderChannel.shared.performAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Dismiss") {
                    ReminderChannel.shared.dismissVisible()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let body = reminder.body {
                ScrollView {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reminderClock(reminder)
    }
}
