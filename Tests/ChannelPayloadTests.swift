//
//  ChannelPayloadTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/Channel/Protocol/ChannelNotification.swift NotBoringNotch/Channel/Agents/AgentSession.swift
//
//  Helper names are prefixed (`checkReminder*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkReminder(_ condition: Bool, _ message: String = "",
                   file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkReminderDecodeFails(_ json: String, _ expected: ChannelPayloadError, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
    do {
        let reminder = try ChannelNotification.decodeV1(Data(json.utf8))
        print("❌ Assertion Failed: decoded [\(reminder.title)] instead of failing with [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    } catch let error as ChannelPayloadError {
        guard error == expected else {
            print("❌ Assertion Failed: [\(error)] != expected [\(expected)] - \(message) at \(file):\(line)")
            exit(1)
        }
    } catch {
        print("❌ Assertion Failed: unexpected error [\(error)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct ChannelPayloadTestsRunner {
    static func main() {
        testAFullPayloadDecodesEveryField()
        testOmittedOptionalFieldsTakeTheirDefaults()
        testOmittedIDsAreDistinct()
        testTheThreeIconKindsDecode()
        testUnknownFieldsAreIgnored()
        testMalformedJSONIsRejected()
        testATitleIsRequired()
        testAnUnknownIconKindIsRejected()
        testAnUnknownSoundIsRejected()
        testAnInvalidActionURLIsRejected()
        testALongBodyIsKeptRatherThanRejected()
        testAnOversizedPayloadIsRejected()
        testAFullV2PayloadDecodesEveryField()
        testV2DefaultsMatchV1()
        testV2LevelsDecodeAndAnUnknownOneIsRejected()
        testV2OpenIsExactlyOneTarget()
        testV2ActionsAreURLOrCopyAndAtMostThree()
        testAClickGoesToOpenThenToTheIconsApp()
        testANotificationSurvivesTheInboxFile()
        print("✅ ChannelPayloadTests: all passed")
    }

    /// Every field a sender can set survives the trip.
    static func testAFullPayloadDecodesEveryField() {
        let json = """
        {
          "id": "awen:session-42:build",
          "icon": { "kind": "sf_symbol", "value": "hammer" },
          "title": "Build finished",
          "subtitle": "awen · session-42",
          "body": "12 files typechecked, 0 errors.",
          "duration": 9,
          "sticky": true,
          "sound": "default",
          "action": { "title": "Back to session", "url": "awen://session/42" }
        }
        """
        guard let reminder = try? ChannelNotification.decodeV1(Data(json.utf8)) else {
            print("❌ Assertion Failed: a well-formed payload failed to decode")
            exit(1)
        }

        checkReminder(reminder.id == "awen:session-42:build", "the sender's id is kept")
        checkReminder(reminder.icon == .symbol("hammer"), "the icon is an SF Symbol")
        checkReminder(reminder.title == "Build finished", "the title")
        checkReminder(reminder.subtitle == "awen · session-42", "the subtitle")
        checkReminder(reminder.body == "12 files typechecked, 0 errors.", "the body")
        checkReminder(reminder.duration == 9, "the sender's duration wins over the default")
        checkReminder(reminder.banner == .untilSeen, "sticky becomes a banner that stays until seen")
        checkReminder(reminder.sound == .standard, "sound is honoured")
        checkReminder(reminder.actions.first?.title == "Back to session", "the action's title")
        checkReminder(reminder.actions.first?.kind == .url(URL(string: "awen://session/42")!), "the action's url")
        checkReminder(reminder.open == nil, "v1 has no default action")
    }

    /// The four fields a sender may omit, and what they fall back to.
    static func testOmittedOptionalFieldsTakeTheirDefaults() {
        let json = #"{ "title": "Just a title" }"#
        guard let reminder = try? ChannelNotification.decodeV1(Data(json.utf8)) else {
            print("❌ Assertion Failed: a title-only payload failed to decode")
            exit(1)
        }

        checkReminder(reminder.title == "Just a title", "the title")
        checkReminder(reminder.subtitle == nil, "no subtitle")
        checkReminder(reminder.body == nil, "no body")
        checkReminder(reminder.icon == nil, "no icon, so the notch draws its own")
        checkReminder(reminder.actions.isEmpty, "no action")
        checkReminder(reminder.duration == 4, "the default duration is four seconds")
        checkReminder(reminder.banner == .temporary, "a banner is transient unless it says otherwise")
        checkReminder(reminder.level == .active, "v1 has one interruption level")
        checkReminder(reminder.sound == .none, "silence unless it says otherwise")
        checkReminder(!reminder.id.isEmpty, "a sender that omits an id still gets a usable one")
    }

    /// Two reminders with no sender-supplied id must not collide in the queue.
    static func testOmittedIDsAreDistinct() {
        let json = #"{ "title": "No id here" }"#
        guard let first = try? ChannelNotification.decodeV1(Data(json.utf8)),
              let second = try? ChannelNotification.decodeV1(Data(json.utf8)) else {
            print("❌ Assertion Failed: a title-only payload failed to decode")
            exit(1)
        }
        checkReminder(first.id != second.id, "generated ids are unique")
    }

    /// All three ways of naming an icon.
    static func testTheThreeIconKindsDecode() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])

        guard let symbol = try? ChannelNotification.decodeV1(Data(#"{ "title": "t", "icon": { "kind": "sf_symbol", "value": "terminal" } }"#.utf8)),
              let image = try? ChannelNotification.decodeV1(Data(#"{ "title": "t", "icon": { "kind": "png_base64", "value": "iVBORw==" } }"#.utf8)),
              let bundle = try? ChannelNotification.decodeV1(Data(#"{ "title": "t", "icon": { "kind": "app_bundle", "value": "com.apple.Terminal" } }"#.utf8))
        else {
            print("❌ Assertion Failed: one of the three icon kinds failed to decode")
            exit(1)
        }

        checkReminder(symbol.icon == .symbol("terminal"), "sf_symbol")
        checkReminder(image.icon == .image(bytes), "png_base64 decodes to bytes")
        checkReminder(bundle.icon == .appBundle("com.apple.Terminal"), "app_bundle")
    }

    /// A sender that adds fields we do not know yet is not an error.
    static func testUnknownFieldsAreIgnored() {
        let json = #"{ "title": "t", "priority": "high", "nested": { "a": 1 } }"#
        guard let reminder = try? ChannelNotification.decodeV1(Data(json.utf8)) else {
            print("❌ Assertion Failed: unknown fields should be ignored, not rejected")
            exit(1)
        }
        checkReminder(reminder.title == "t", "the known fields still decode")
    }

    static func testMalformedJSONIsRejected() {
        checkReminderDecodeFails("{ not json at all", .malformed, "a truncated body")
        checkReminderDecodeFails(#"{ "title": 42 }"#, .malformed, "a title of the wrong type")
        checkReminderDecodeFails("[]", .malformed, "an array instead of an object")
    }

    static func testATitleIsRequired() {
        checkReminderDecodeFails("{}", .missingTitle, "no title key")
        checkReminderDecodeFails(#"{ "title": "" }"#, .missingTitle, "an empty title")
        checkReminderDecodeFails(#"{ "title": "   " }"#, .missingTitle, "a whitespace title")
    }

    static func testAnUnknownIconKindIsRejected() {
        checkReminderDecodeFails(#"{ "title": "t", "icon": { "kind": "emoji", "value": "🎉" } }"#,
                                 .unknownIconKind("emoji"),
                                 "an icon kind we cannot draw is an error, not a silent blank")
        checkReminderDecodeFails(#"{ "title": "t", "icon": { "kind": "png_base64", "value": "not base64!!" } }"#,
                                 .invalidIconData,
                                 "base64 that does not decode is rejected")
    }

    static func testAnUnknownSoundIsRejected() {
        checkReminderDecodeFails(#"{ "title": "t", "sound": "loud" }"#, .unknownSound("loud"))
    }

    static func testAnInvalidActionURLIsRejected() {
        checkReminderDecodeFails(#"{ "title": "t", "action": { "title": "Open", "url": "://nope" } }"#,
                                 .invalidAction)
    }

    /// The body is read in the opened notch, so it is kept whole: display truncates, the
    /// channel does not.
    static func testALongBodyIsKeptRatherThanRejected() {
        let body = String(repeating: "x", count: 20_000)
        let json = #"{ "title": "t", "body": "\#(body)" }"#
        guard let reminder = try? ChannelNotification.decodeV1(Data(json.utf8)) else {
            print("❌ Assertion Failed: a long body should be kept, not rejected")
            exit(1)
        }
        checkReminder(reminder.body?.count == 20_000, "the whole body survives decoding")
    }

    /// The one size limit: the request body itself.
    static func testAnOversizedPayloadIsRejected() {
        let body = String(repeating: "x", count: ChannelNotification.maximumPayloadBytes)
        let json = #"{ "title": "t", "body": "\#(body)" }"#
        checkReminderDecodeFails(json, .tooLarge, "a payload over the cap is refused before parsing")
    }

    // MARK: - v2

    static func decodeV2(_ json: String) -> ChannelNotification {
        do {
            return try ChannelNotification.decode(Data(json.utf8))
        } catch {
            print("❌ Assertion Failed: v2 payload failed to decode with [\(error)]: \(json)")
            exit(1)
        }
    }

    static func checkV2Fails(_ json: String, _ expected: ChannelPayloadError, _ message: String = "",
                             file: StaticString = #file, line: UInt = #line) {
        do {
            let notification = try ChannelNotification.decode(Data(json.utf8))
            print("❌ Assertion Failed: decoded [\(notification.title)] instead of failing with [\(expected)] - \(message) at \(file):\(line)")
            exit(1)
        } catch let error as ChannelPayloadError {
            guard error == expected else {
                print("❌ Assertion Failed: [\(error)] != expected [\(expected)] - \(message) at \(file):\(line)")
                exit(1)
            }
        } catch {
            print("❌ Assertion Failed: unexpected error [\(error)] - \(message) at \(file):\(line)")
            exit(1)
        }
    }

    static func testAFullV2PayloadDecodesEveryField() {
        let n = decodeV2("""
        {
          "id": "claude:42:done",
          "source": "claude-code",
          "thread": "session-42",
          "level": "time-sensitive",
          "icon": { "kind": "app_bundle", "value": "com.apple.Terminal" },
          "title": "Task complete",
          "subtitle": "not-boring-notch",
          "body": "4 files changed",
          "duration": 6,
          "sound": "default",
          "open": { "url": "vscode://file/Users/me/code/app" },
          "actions": [
            { "title": "Open PR", "url": "https://example.com/pr/1" },
            { "title": "Copy SHA", "copy": "0ae0b60" }
          ]
        }
        """)
        checkReminder(n.id == "claude:42:done", "the sender's id")
        checkReminder(n.source == "claude-code", "the source")
        checkReminder(n.thread == "session-42", "the thread")
        checkReminder(n.level == .timeSensitive, "the level")
        checkReminder(n.icon == .appBundle("com.apple.Terminal"), "the icon")
        checkReminder(n.subtitle == "not-boring-notch" && n.body == "4 files changed", "the text")
        checkReminder(n.duration == 6, "the duration")
        checkReminder(n.sound == .standard, "the sound")
        checkReminder(n.open == .url(URL(string: "vscode://file/Users/me/code/app")!), "the open target")
        checkReminder(n.actions == [
            ChannelAction(title: "Open PR", kind: .url(URL(string: "https://example.com/pr/1")!)),
            ChannelAction(title: "Copy SHA", kind: .copy("0ae0b60")),
        ], "both actions, in order")
        checkReminder(n.banner == .temporary, "v2 cannot ask for a sticky banner")
    }

    static func testV2DefaultsMatchV1() {
        let n = decodeV2(#"{ "title": "Just a title" }"#)
        checkReminder(n.level == .active, "active unless it says otherwise")
        checkReminder(n.duration == ChannelNotification.defaultDuration, "the default duration")
        checkReminder(n.source == nil && n.thread == nil && n.open == nil, "nothing else is assumed")
        checkReminder(n.actions.isEmpty && n.sound == .none, "no actions, no sound")
        checkReminder(!n.id.isEmpty, "a generated id")
    }

    static func testV2LevelsDecodeAndAnUnknownOneIsRejected() {
        checkReminder(decodeV2(#"{ "title": "t", "level": "passive" }"#).level == .passive, "passive")
        checkReminder(decodeV2(#"{ "title": "t", "level": "active" }"#).level == .active, "active")
        checkV2Fails(#"{ "title": "t", "level": "critical" }"#, .unknownLevel("critical"),
                     "critical is not a level a script can claim")
    }

    static func testV2OpenIsExactlyOneTarget() {
        checkReminder(decodeV2(#"{ "title": "t", "open": { "app": "com.apple.Terminal" } }"#).open
                      == .app("com.apple.Terminal"), "an app")
        checkV2Fails(#"{ "title": "t", "open": {} }"#, .invalidOpen, "neither")
        checkV2Fails(#"{ "title": "t", "open": { "url": "https://a.b", "app": "com.apple.Terminal" } }"#,
                     .invalidOpen, "both")
        checkV2Fails(#"{ "title": "t", "open": { "url": "://nope" } }"#, .invalidOpen, "a URL without a scheme")
    }

    static func testV2ActionsAreURLOrCopyAndAtMostThree() {
        checkV2Fails(#"{ "title": "t", "actions": [ { "title": "x" } ] }"#, .invalidAction, "neither url nor copy")
        checkV2Fails(#"{ "title": "t", "actions": [ { "title": "x", "url": "https://a.b", "copy": "y" } ] }"#,
                     .invalidAction, "both url and copy")
        checkV2Fails(#"{ "title": "t", "actions": [ { "title": " ", "copy": "y" } ] }"#, .invalidAction, "a blank title")
        let four = Array(repeating: #"{ "title": "x", "copy": "y" }"#, count: 4).joined(separator: ",")
        checkV2Fails(#"{ "title": "t", "actions": [\#(four)] }"#, .tooManyActions, "four actions")
    }

    static func testAClickGoesToOpenThenToTheIconsApp() {
        let explicit = decodeV2(#"{ "title": "t", "open": { "url": "https://a.b" }, "icon": { "kind": "app_bundle", "value": "com.x" } }"#)
        checkReminder(explicit.clickTarget == .url(URL(string: "https://a.b")!), "open wins")
        let fromIcon = decodeV2(#"{ "title": "t", "icon": { "kind": "app_bundle", "value": "com.x" } }"#)
        checkReminder(fromIcon.clickTarget == .app("com.x"), "an app icon is somewhere to go")
        let nowhere = decodeV2(#"{ "title": "t", "icon": { "kind": "sf_symbol", "value": "bell" } }"#)
        checkReminder(nowhere.clickTarget == nil, "a symbol is not")
    }

    /// The Inbox is written to disk as JSON; everything a notification carries has to come back.
    static func testANotificationSurvivesTheInboxFile() {
        let n = decodeV2("""
        { "title": "t", "level": "passive", "icon": { "kind": "png_base64", "value": "iVBORw==" },
          "open": { "app": "com.x" }, "actions": [ { "title": "c", "copy": "y" } ] }
        """)
        guard let data = try? JSONEncoder().encode(n),
              let back = try? JSONDecoder().decode(ChannelNotification.self, from: data) else {
            print("❌ Assertion Failed: a notification did not round-trip through JSON")
            exit(1)
        }
        checkReminder(back == n, "it comes back equal")
    }
}
