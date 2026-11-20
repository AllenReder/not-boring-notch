//
//  CodexHooksConfigTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/CodexHooksConfig.swift
//
//  Turning on `features.hooks` in ~/.codex/config.toml must change that one setting and nothing
//  else in a file the user keeps by hand.
//

import Foundation

func checkToml(_ condition: Bool, _ message: String = "",
               file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
enum CodexHooksConfigTests {
    static func main() {
        let cases: [(name: String, input: String, expected: String?)] = [
            ("empty file", "", "features.hooks = true\n"),
            ("no features table", "model = \"gpt-5\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n",
             "model = \"gpt-5\"\n\nfeatures.hooks = true\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"),
            ("only root keys, no trailing newline", "model = \"x\"", "model = \"x\"\nfeatures.hooks = true\n"),
            ("a features table", "[features]\nundo = true # keep me\n\n[tui]\nx = 1\n",
             "[features]\nhooks = true\nundo = true # keep me\n\n[tui]\nx = 1\n"),
            ("already on", "[features]\nhooks = true\n", "[features]\nhooks = true\n"),
            ("turned off", "[features]\nhooks = false # no\n", "[features]\nhooks = true # no\n"),
            ("the legacy name", "[features]\ncodex_hooks = true\n", "[features]\nhooks = true\n"),
            ("CRLF", "model = \"x\"\r\n", "model = \"x\"\r\nfeatures.hooks = true\r\n"),
            ("a layout it will not guess at", "features = 5\n", nil),
            ("an unterminated string", "model = \"x\n", nil),
        ]
        for (name, input, expected) in cases {
            let actual = CodexHooksConfig.enablingHooks(in: input)
            checkToml(actual == expected, "\(name): expected \(String(describing: expected)), got \(String(describing: actual))")
            if let actual {
                checkToml(CodexHooksConfig.enablingHooks(in: actual) == actual, "\(name): enabling twice changes nothing")
            }
        }
        let off: [(name: String, input: String, expected: Bool?)] = [
            ("never mentioned", "model = \"x\"\n", false),
            ("on", "[features]\nhooks = true\n", false),
            ("off", "[features]\nhooks = false # no\n", true),
            ("off, dotted", "features.hooks = false\n", true),
            ("off, by the legacy name", "[features]\ncodex_hooks = false\n", true),
            ("a layout it will not guess at", "features = 5\n", nil),
        ]
        for (name, input, expected) in off {
            let actual = CodexHooksConfig.hooksTurnedOff(in: input)
            checkToml(actual == expected, "turned off, \(name): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
        print("✅ CodexHooksConfigTests passed")
    }
}
