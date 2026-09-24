//
//  Reminder.swift
//  NotBoringNotch
//
//  One message delivered to the notch through the Reminder Channel: an icon, a title, an
//  optional subtitle, a body, and how long it is meant to stay. Decoding lives here, off
//  AppKit and off the network, so the payload contract can be exercised on its own.
//

import Foundation

struct Reminder: Equatable, Hashable, Identifiable {
    /// The largest request body the channel accepts. It bounds memory, not content: a long
    /// body is kept whole and truncated when drawn, never at the door.
    static let maximumPayloadBytes = 64 * 1024

    /// How long a Reminder stays on screen when its sender does not say.
    static let defaultDuration: TimeInterval = 4

    let id: String
    let icon: ReminderIcon?
    let title: String
    let subtitle: String?
    let body: String?
    let duration: TimeInterval
    let isSticky: Bool
    let sound: ReminderSound
    let action: ReminderAction?

    /// Decodes a Reminder Channel request body.
    ///
    /// Fields the sender omits take their defaults; fields we do not know are ignored, so a
    /// newer sender does not break an older notch. Anything we would have to guess at — an
    /// icon kind we cannot draw, a sound we do not have — is refused rather than drawn blank.
    static func decode(_ data: Data) throws -> Reminder {
        guard data.count <= maximumPayloadBytes else { throw ReminderPayloadError.tooLarge }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ReminderPayloadError.malformed
        }

        guard let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw ReminderPayloadError.missingTitle
        }

        return Reminder(
            id: payload.id.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString,
            icon: try payload.icon.map(decodeIcon),
            title: title,
            subtitle: nonEmpty(payload.subtitle),
            body: nonEmpty(payload.body),
            duration: payload.duration ?? defaultDuration,
            isSticky: payload.sticky ?? false,
            sound: try decodeSound(payload.sound),
            action: try payload.action.map(decodeAction)
        )
    }

    private static func decodeIcon(_ icon: Payload.Icon) throws -> ReminderIcon {
        switch icon.kind {
        case "sf_symbol":
            return .symbol(icon.value)
        case "png_base64":
            guard let data = Data(base64Encoded: icon.value), !data.isEmpty else {
                throw ReminderPayloadError.invalidIconData
            }
            return .image(data)
        case "app_bundle":
            return .appBundle(icon.value)
        case let kind:
            throw ReminderPayloadError.unknownIconKind(kind)
        }
    }

    private static func decodeSound(_ sound: String?) throws -> ReminderSound {
        switch sound {
        case nil, "none":
            return .none
        case "default":
            return .standard
        case let sound?:
            throw ReminderPayloadError.unknownSound(sound)
        }
    }

    private static func decodeAction(_ action: Payload.Action) throws -> ReminderAction {
        guard !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: action.url),
              let scheme = url.scheme,
              // `URL(string: "://nope")` is not nil, it is a URL with an empty scheme.
              !scheme.isEmpty else {
            throw ReminderPayloadError.invalidAction
        }
        return ReminderAction(title: action.title, url: url)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private struct Payload: Decodable {
        struct Icon: Decodable {
            let kind: String
            let value: String
        }

        struct Action: Decodable {
            let title: String
            let url: String
        }

        let id: String?
        let icon: Icon?
        let title: String?
        let subtitle: String?
        let body: String?
        let duration: TimeInterval?
        let sticky: Bool?
        let sound: String?
        let action: Action?
    }
}

enum ReminderPayloadError: Error, Equatable {
    /// The request body is larger than `Reminder.maximumPayloadBytes`.
    case tooLarge
    /// The body is not JSON, or a known field has the wrong type.
    case malformed
    /// No non-empty title, which is the one field a Reminder cannot do without.
    case missingTitle
    case unknownIconKind(String)
    /// A `png_base64` icon whose value is not decodable base64.
    case invalidIconData
    case unknownSound(String)
    /// An action missing a title or a usable URL.
    case invalidAction
}

enum ReminderIcon: Equatable, Hashable {
    /// An SF Symbol name. An unresolvable name falls back to the notch's own bell.
    case symbol(String)
    /// PNG bytes carried in the request, because a sandboxed notch cannot read the sender's path.
    case image(Data)
    /// An installed application's bundle identifier, whose icon the notch looks up itself.
    case appBundle(String)
}

enum ReminderSound: String, Equatable {
    case none
    /// The notch's own alert sound, `notch.m4a`.
    case standard
}

struct ReminderAction: Equatable, Hashable {
    let title: String
    let url: URL
}
