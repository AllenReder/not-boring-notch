//
//  ReminderPayloadTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/models/Reminder.swift
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

func checkReminderDecodeFails(_ json: String, _ expected: ReminderPayloadError, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
    do {
        let reminder = try Reminder.decode(Data(json.utf8))
        print("❌ Assertion Failed: decoded [\(reminder.title)] instead of failing with [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    } catch let error as ReminderPayloadError {
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
struct ReminderPayloadTestsRunner {
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
        print("✅ ReminderPayloadTests: all passed")
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
        guard let reminder = try? Reminder.decode(Data(json.utf8)) else {
            print("❌ Assertion Failed: a well-formed payload failed to decode")
            exit(1)
        }

        checkReminder(reminder.id == "awen:session-42:build", "the sender's id is kept")
        checkReminder(reminder.icon == .symbol("hammer"), "the icon is an SF Symbol")
        checkReminder(reminder.title == "Build finished", "the title")
        checkReminder(reminder.subtitle == "awen · session-42", "the subtitle")
        checkReminder(reminder.body == "12 files typechecked, 0 errors.", "the body")
        checkReminder(reminder.duration == 9, "the sender's duration wins over the default")
        checkReminder(reminder.isSticky, "sticky is honoured")
        checkReminder(reminder.sound == .standard, "sound is honoured")
        checkReminder(reminder.action?.title == "Back to session", "the action's title")
        checkReminder(reminder.action?.url.absoluteString == "awen://session/42", "the action's url")
    }

    /// The four fields a sender may omit, and what they fall back to.
    static func testOmittedOptionalFieldsTakeTheirDefaults() {
        let json = #"{ "title": "Just a title" }"#
        guard let reminder = try? Reminder.decode(Data(json.utf8)) else {
            print("❌ Assertion Failed: a title-only payload failed to decode")
            exit(1)
        }

        checkReminder(reminder.title == "Just a title", "the title")
        checkReminder(reminder.subtitle == nil, "no subtitle")
        checkReminder(reminder.body == nil, "no body")
        checkReminder(reminder.icon == nil, "no icon, so the notch draws its own")
        checkReminder(reminder.action == nil, "no action")
        checkReminder(reminder.duration == 4, "the default duration is four seconds")
        checkReminder(!reminder.isSticky, "a reminder is transient unless it says otherwise")
        checkReminder(reminder.sound == .none, "silence unless it says otherwise")
        checkReminder(!reminder.id.isEmpty, "a sender that omits an id still gets a usable one")
    }

    /// Two reminders with no sender-supplied id must not collide in the queue.
    static func testOmittedIDsAreDistinct() {
        let json = #"{ "title": "No id here" }"#
        guard let first = try? Reminder.decode(Data(json.utf8)),
              let second = try? Reminder.decode(Data(json.utf8)) else {
            print("❌ Assertion Failed: a title-only payload failed to decode")
            exit(1)
        }
        checkReminder(first.id != second.id, "generated ids are unique")
    }

    /// All three ways of naming an icon.
    static func testTheThreeIconKindsDecode() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])

        guard let symbol = try? Reminder.decode(Data(#"{ "title": "t", "icon": { "kind": "sf_symbol", "value": "terminal" } }"#.utf8)),
              let image = try? Reminder.decode(Data(#"{ "title": "t", "icon": { "kind": "png_base64", "value": "iVBORw==" } }"#.utf8)),
              let bundle = try? Reminder.decode(Data(#"{ "title": "t", "icon": { "kind": "app_bundle", "value": "com.apple.Terminal" } }"#.utf8))
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
        guard let reminder = try? Reminder.decode(Data(json.utf8)) else {
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
        guard let reminder = try? Reminder.decode(Data(json.utf8)) else {
            print("❌ Assertion Failed: a long body should be kept, not rejected")
            exit(1)
        }
        checkReminder(reminder.body?.count == 20_000, "the whole body survives decoding")
    }

    /// The one size limit: the request body itself.
    static func testAnOversizedPayloadIsRejected() {
        let body = String(repeating: "x", count: Reminder.maximumPayloadBytes)
        let json = #"{ "title": "t", "body": "\#(body)" }"#
        checkReminderDecodeFails(json, .tooLarge, "a payload over the cap is refused before parsing")
    }
}
