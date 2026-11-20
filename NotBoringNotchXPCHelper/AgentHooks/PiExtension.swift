//
//  PiExtension.swift
//  NotBoringNotchXPCHelper
//
//  The pi extension that reports a pi session to the notch. pi has no command hooks; it loads
//  TypeScript extensions from ~/.pi/agent/extensions/ and calls them on its events, so the bridge
//  is an extension rather than `notch-agent-hook`. Like the script, it only forwards: it names
//  the event and passes on the few fields the app reads, and `AgentAdapter` decides what they
//  mean. It adds the same facts in the same headers, so a pi session is found and clicked through
//  to like any other.
//
//  It reports interactive sessions only: the terminal (`tui`) and T3 Code, which runs pi with
//  `--mode rpc`. `pi -p`, `--mode json`, the sessions pi binds for in-process sub-agents (always
//  `print`), and the child processes of pi-subagents (`PI_SUBAGENT_CHILD=1`) are left out, so a
//  sub-agent is never counted as a session of its own.
//

import Foundation

enum PiExtension {
    static let file = AgentPluginFile(
        path: ".pi/agent/extensions/not-boring-notch.ts", label: "pi extension",
        versionMarker: versionMarker, version: version, source: source)

    /// Bump whenever `source` changes, so an installed copy can be told apart from this one.
    private static let version = 1

    private static let versionMarker = "// not-boring-notch-pi-extension-version: "

    /// Posts in order, one at a time: a `tool_execution_end` that overtook its start, or an
    /// `agent_settled` that overtook the last tool, would leave the session working for good.
    /// Each post gives up after a second and never throws into pi.
    private static let source = #"""
    \#(versionMarker)\#(version)
    // Reports this pi session to Not Boring Notch. Installed by Not Boring Notch, which rewrites or
    // removes this file from its settings; edit it there, not here.
    import { readFileSync } from "node:fs";
    import { homedir } from "node:os";
    import { join } from "node:path";

    const discovery = join(homedir(),
      "Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/notch-channel.json");
    const reported = new Set(["tui", "rpc"]);
    const subagentChild = process.env.PI_SUBAGENT_CHILD === "1";

    function endpoint() {
      try {
        const { port, token } = JSON.parse(readFileSync(discovery, "utf8"));
        return port && token ? { port, token } : null;
      } catch {
        return null;
      }
    }

    function t3Environment() {
      if (!process.env.T3CODE_THREAD_ID) return undefined;
      try {
        const home = process.env.T3CODE_HOME || join(homedir(), ".t3");
        return readFileSync(join(home, "userdata/environment-id"), "utf8").trim();
      } catch {
        return undefined;
      }
    }

    const facts = {
      "X-Agent-Pid": String(process.pid),
      "X-Agent-Host-Bundle": process.env.__CFBundleIdentifier,
      "X-Agent-Term-Program": process.env.TERM_PROGRAM,
      "X-Agent-Tmux-Pane": process.env.TMUX_PANE,
      "X-Agent-T3-Thread": process.env.T3CODE_THREAD_ID,
      "X-Agent-T3-Environment": t3Environment(),
    };

    let queue = Promise.resolve();

    async function send(body) {
      const target = endpoint();
      if (!target) return;
      const headers = { "Authorization": `Bearer ${target.token}`, "Content-Type": "application/json" };
      for (const [name, value] of Object.entries(facts)) if (value) headers[name] = value;
      await fetch(`http://127.0.0.1:${target.port}/v2/agents/pi/events`, {
        method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(1000),
      });
    }

    function lastAssistant(messages) {
      for (let i = (messages ?? []).length - 1; i >= 0; i--) {
        const message = messages[i];
        if (message?.role !== "assistant") continue;
        const text = (message.content ?? []).filter((part) => part.type === "text").map((part) => part.text).join("\n");
        return { text, stopReason: message.stopReason, error: message.errorMessage };
      }
      return undefined;
    }

    export default function (pi) {
      let running = false;
      let pendingTool;
      let last;

      function post(ctx, event, fields = {}) {
        if (subagentChild || !reported.has(ctx.mode)) return queue;
        const body = { hook_event_name: event, session_id: ctx.sessionManager.getSessionId(), cwd: ctx.cwd, ...fields };
        queue = queue.then(() => send(body)).catch(() => {});
        return queue;
      }

      pi.on("session_start", (_event, ctx) => { post(ctx, "session_start"); });
      pi.on("agent_start", (_event, ctx) => {
        running = true;
        last = undefined;
        post(ctx, "agent_start");
      });
      // Before any other extension's tool_call handler: T3 Code asks for approval in its own.
      pi.on("tool_call", (event) => { pendingTool = event.toolName; });
      pi.on("tool_execution_start", (event, ctx) => { post(ctx, "tool_execution_start", { tool_name: event.toolName }); });
      pi.on("tool_execution_end", (event, ctx) => { post(ctx, "tool_execution_end", { tool_name: event.toolName }); });
      // A prompt outside a run is one the user opened themselves.
      pi.on("ui_prompt_start", (event, ctx) => {
        if (running) post(ctx, "ui_prompt_start", { tool_name: pendingTool, prompt_kind: event.kind });
      });
      pi.on("ui_prompt_end", (event, ctx) => {
        if (running) post(ctx, "ui_prompt_end", { prompt_kind: event.kind });
      });
      pi.on("agent_end", (event) => { last = lastAssistant(event.messages); });
      pi.on("agent_settled", (event, ctx) => {
        running = false;
        post(ctx, "agent_settled", {
          aborted: event.aborted,
          stop_reason: last?.stopReason,
          last_assistant_message: last?.text,
          error: last?.error,
        });
      });
      // Waited for, so the notch hears of it before pi exits.
      pi.on("session_shutdown", (_event, ctx) => post(ctx, "session_shutdown"));
    }
    """#
}
