//
//  NotBoringNotchXPCHelperProtocol.swift
//  NotBoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol NotBoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Agent hooks: install and check them, trust them in Codex, and ask whether an agent's
    // process is still running. The structured replies are JSON (see AgentHooksModels.swift).
    /// pid -> start time in seconds since 1970. A pid that is not running is left out.
    func agentProcessStartTimes(_ pids: [NSNumber], with reply: @escaping ([NSNumber: NSNumber]) -> Void)
    func agentHooksStatus(hookScript: String, with reply: @escaping (Data) -> Void)
    func installAgentHooks(_ agents: [String], hookScript: String, with reply: @escaping (Data) -> Void)
    func uninstallAgentHooks(_ agents: [String], hookScript: String, with reply: @escaping (Data) -> Void)
    func trustCodexHooks(with reply: @escaping (Data) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "com.allenreder.notboringnotch.NotBoringNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any NotBoringNotchXPCHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? NotBoringNotchXPCHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/
