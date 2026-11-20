//
//  OpenCodePlugin.swift
//  NotBoringNotchXPCHelper
//
//  The OpenCode plugin that reports OpenCode sessions to the notch. OpenCode has no command
//  hooks; it loads plugins from ~/.config/opencode/plugins/. Like the script and the pi
//  extension, it only forwards: it names the event with OpenCode's own name and passes on the few
//  fields the app reads, and `AgentAdapter` decides what they mean.
//
//  Where OpenCode runs a session decides what the plugin can say about it:
//
//  - The TUI and `opencode run` run sessions in one shared background `opencode serve --service`.
//    Its pid and environment belong to whoever started it first, so the plugin reports neither.
//    The sessions arrive without a process, and the notch lets go of one that has gone quiet.
//  - `--standalone`, `opencode acp` and the like run a private `serve --stdio` child. The process
//    whose exit ends the session is its parent (the one the user sees), whose environment the
//    child inherited.
//  - T3 Code runs one `opencode serve --port` for all its threads, and does not name the thread
//    in the environment. A thread's sessions carry a permission rule `t3-code-<thread>_*`, which
//    is read from the root session.
//
//  A sub-agent is a session of its own with a `parentID`. Its events are posted under the root
//  session's id, with `agent_id` set to its own, the way a sub-agent of Claude Code is reported.
//
//  Every directory OpenCode serves loads its own copy of this plugin, and each copy hears every
//  directory's events. A copy posts only for the sessions of its own directory.
//

import Foundation

enum OpenCodePlugin {
    static let file = AgentPluginFile(
        path: ".config/opencode/plugins/not-boring-notch.js", label: "OpenCode plugin",
        versionMarker: versionMarker, version: version, source: source)

    /// Bump whenever `source` changes, so an installed copy can be told apart from this one.
    private static let version = 1

    private static let versionMarker = "// not-boring-notch-opencode-plugin-version: "

    /// Everything goes through one queue, resolution of the session included, so posts leave in
    /// the order OpenCode produced them: an `execute.after` that overtook its `execute.before`, or
    /// a `succeeded` that overtook the last tool, would leave the session working for good. A hook
    /// returns at once, so none of this slows a tool down. Each post gives up after a second and
    /// nothing throws into OpenCode.
    private static let source = #"""
    \#(versionMarker)\#(version)
    // Reports OpenCode sessions to Not Boring Notch. Installed by Not Boring Notch, which rewrites or
    // removes this file from its settings; edit it there, not here.
    import { readFileSync } from "node:fs";
    import { homedir } from "node:os";
    import { join } from "node:path";

    const discovery = join(homedir(),
      "Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/notch-channel.json");
    const t3Rule = /^t3-code-(.+)_\*$/;
    const events = [
      "session.created", "session.deleted", "session.text.ended",
      "session.execution.started", "session.execution.succeeded",
      "session.execution.failed", "session.execution.interrupted",
      "permission.asked", "permission.replied",
      "form.created", "form.replied", "form.cancelled",
    ];

    function endpoint() {
      try {
        const { port, token } = JSON.parse(readFileSync(discovery, "utf8"));
        return port && token ? { port, token } : null;
      } catch {
        return null;
      }
    }

    let t3Environment;
    function readT3Environment() {
      if (t3Environment === undefined) {
        try {
          const home = process.env.T3CODE_HOME || join(homedir(), ".t3");
          t3Environment = readFileSync(join(home, "userdata/environment-id"), "utf8").trim();
        } catch {
          t3Environment = null;
        }
      }
      return t3Environment || undefined;
    }

    // The shared `serve --service` belongs to nobody in particular. A private `serve --stdio` child
    // is watched through its parent, unless that has already gone and left it to init.
    const service = process.argv.includes("--service");
    const watched = process.argv.includes("--stdio") && process.ppid > 1 ? process.ppid : process.pid;
    const facts = service ? {} : {
      "X-Agent-Pid": String(watched),
      "X-Agent-Host-Bundle": process.env.__CFBundleIdentifier,
      "X-Agent-Term-Program": process.env.TERM_PROGRAM,
      "X-Agent-Tmux-Pane": process.env.TMUX_PANE,
    };

    async function send(body, thread) {
      const target = endpoint();
      if (!target) return;
      const headers = { "Authorization": `Bearer ${target.token}`, "Content-Type": "application/json", ...facts };
      if (thread) {
        headers["X-Agent-T3-Thread"] = thread;
        headers["X-Agent-T3-Environment"] = readT3Environment();
      }
      for (const name of Object.keys(headers)) if (!headers[name]) delete headers[name];
      await fetch(`http://127.0.0.1:${target.port}/v2/agents/opencode/events`, {
        method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(1000),
      });
    }

    function bounded(promise) {
      return Promise.race([promise, new Promise((_, reject) => {
        AbortSignal.timeout(1000).addEventListener("abort", () => reject(new Error("timeout")));
      })]);
    }

    export default {
      id: "not-boring-notch",
      async setup(ctx) {
        const directory = ctx.location.directory;
        const controller = new AbortController();
        const records = new Map();   // session id -> Promise of { directory, root, child, thread }
        const texts = new Map();     // session id -> the last thing it said
        const asked = new Map();     // permission or form id -> session id, while unanswered
        let queue = Promise.resolve();

        // A session's directory and its root, from OpenCode. A failed lookup is not remembered.
        function record(sessionID, depth = 0) {
          let found = records.get(sessionID);
          if (!found) {
            found = lookup(sessionID, depth).catch((error) => { records.delete(sessionID); throw error; });
            records.set(sessionID, found);
          }
          return found;
        }

        async function lookup(sessionID, depth) {
          const info = await bounded(ctx.session.get({ sessionID }));
          const parent = info.parentID && depth < 8 ? await record(info.parentID, depth + 1) : undefined;
          const rule = (info.permissions ?? []).map((p) => t3Rule.exec(p.action ?? "")?.[1]).find(Boolean);
          return {
            directory: info.location?.directory,
            root: parent ? parent.root : sessionID,
            child: parent ? sessionID : undefined,
            thread: parent ? parent.thread : rule,
          };
        }

        // Runs `job` after everything queued before it, and only for a session of this directory.
        function act(sessionID, job) {
          if (!sessionID) return;
          queue = queue.then(async () => {
            const session = await record(sessionID);
            if (session.directory === directory) await job(session);
          }).catch(() => {});
        }

        function post(session, name, fields = {}) {
          return send({
            hook_event_name: name, session_id: session.root, agent_id: session.child, cwd: directory, ...fields,
          }, session.thread);
        }

        function report(sessionID, name, fields) {
          act(sessionID, (session) => post(session, name, fields));
        }

        // The end of a turn forgets what it left: what the session said, and what it still asked.
        function end(sessionID, name, fields) {
          act(sessionID, (session) => {
            const text = texts.get(sessionID);
            texts.delete(sessionID);
            for (const [id, owner] of asked) if (owner === sessionID) asked.delete(id);
            return post(session, name, fields(text));
          });
        }

        function onEvent(event) {
          const data = event.data ?? {};
          const sessionID = data.sessionID ?? data.form?.sessionID;
          // Something the user is asked, and later answers.
          const ask = (id, fields) => act(sessionID, (session) => {
            asked.set(id, sessionID);
            return post(session, event.type, fields);
          });
          // An answer to something this plugin reported, and to nothing else.
          const answered = (id) => act(sessionID, (session) => asked.delete(id) ? post(session, event.type) : undefined);

          switch (event.type) {
            case "session.created":
              return report(sessionID, event.type);
            case "session.deleted":
              return act(sessionID, async (session) => {
                await post(session, event.type);
                records.delete(sessionID);
              });
            case "session.text.ended":
              // The last one before the turn ends is what the banner says.
              return act(sessionID, () => { texts.set(sessionID, data.text); });
            case "session.execution.started":
              return act(sessionID, (session) => {
                texts.delete(sessionID);
                return post(session, event.type);
              });
            case "session.execution.succeeded":
              return end(sessionID, event.type, (text) => ({ last_assistant_message: text }));
            case "session.execution.failed":
              return end(sessionID, event.type, () => ({ error: data.error?.message }));
            case "session.execution.interrupted":
              return end(sessionID, event.type, () => ({}));
            case "permission.asked":
              return ask(data.id, { tool_name: data.action });
            case "form.created":
              // Only a question is the user's to answer; other forms are not about this turn.
              return data.form?.metadata?.kind === "question" ? ask(data.form.id, { form_kind: "question" }) : undefined;
            case "permission.replied":
              return answered(data.requestID);
            case "form.replied":
            case "form.cancelled":
              return answered(data.id);
          }
        }

        const registrations = [];
        for (const name of ["execute.before", "execute.after"]) {
          try {
            registrations.push(await ctx.tool.hook(name, (input) => {
              report(input?.sessionID, `tool.${name}`, { tool_name: input?.tool });
            }));
          } catch {}
        }

        (async () => {
          try {
            for await (const event of ctx.event.subscribe({ types: events, signal: controller.signal })) {
              try { onEvent(event); } catch {}
            }
          } catch {}
        })();

        return async () => {
          controller.abort();
          for (const registration of registrations) {
            try { await registration?.dispose?.(); } catch {}
          }
        };
      },
    };
    """#
}
