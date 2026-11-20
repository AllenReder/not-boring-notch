// Replays a capture of real OpenCode runs (Tests/Fixtures/opencode, cut by make-fixture.py)
// through the notch plugin, and prints what the plugin posted to a stand-in for the notch, one
// JSON object per post: {"path", "auth", "headers": {x-agent-*}, "body": {...}}, after a first
// line {"process": {"pid", "ppid"}} naming this process and its parent.
//
//   node replay.mjs <plugin.mjs> <capture.jsonl> [--service | --stdio]
//
// Each `setup` line starts a copy of the plugin with a fake `ctx`, as OpenCode does for each
// directory; `event` lines are heard only by the copy they name, `hook` lines call that copy's
// tool hooks, and `session.get` answers from the `session` lines. HOME is a scratch directory
// holding the notch's discovery file, so nothing outside it is read or written. The flags are for
// the plugin to see in process.argv, like OpenCode's own.
import http from "node:http";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [pluginPath, capturePath] = process.argv.slice(2);

const home = mkdtempSync(join(tmpdir(), "oc-replay-"));
process.env.HOME = home;
delete process.env.T3CODE_HOME;
process.env.TERM_PROGRAM = "replay-term";
process.env.__CFBundleIdentifier = "com.example.host";
delete process.env.TMUX_PANE;
mkdirSync(join(home, ".t3/userdata"), { recursive: true });
writeFileSync(join(home, ".t3/userdata/environment-id"), "env-1\n");

const posts = [];
const server = http.createServer((request, response) => {
  let body = "";
  request.on("data", (chunk) => { body += chunk; });
  request.on("end", () => {
    const headers = Object.fromEntries(Object.entries(request.headers).filter(([name]) => name.startsWith("x-agent-")));
    posts.push({ path: request.url, auth: request.headers.authorization, headers, body: JSON.parse(body) });
    response.writeHead(202).end('{"status":"accepted"}');
  });
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const discoveryDirectory = join(home, "Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch");
mkdirSync(discoveryDirectory, { recursive: true });
writeFileSync(join(discoveryDirectory, "notch-channel.json"), JSON.stringify({ port: server.address().port, token: "tok" }));

const plugin = (await import(pathToFileURL(pluginPath).href)).default;
const lines = readFileSync(capturePath, "utf8").split("\n").filter(Boolean).map((line) => JSON.parse(line));
const sessions = new Map(lines.filter((line) => line.op === "session").map((line) => [line.info.id, line.info]));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function fakeContext(directory) {
  const hooks = new Map();
  const feeds = new Set();
  return {
    hooks,
    deliver(event) { for (const feed of feeds) feed(event); },
    ctx: {
      location: { directory },
      session: {
        async get({ sessionID }) {
          const info = sessions.get(sessionID);
          if (!info) throw new Error(`no session ${sessionID}`);
          return structuredClone(info);
        },
      },
      tool: {
        async hook(name, handler) {
          hooks.set(name, handler);
          return { dispose() { hooks.delete(name); } };
        },
      },
      event: {
        subscribe({ types, signal }) {
          const pending = [];
          let wake;
          const feed = (event) => {
            if (types && !types.includes(event.type)) return;
            pending.push(event);
            wake?.();
          };
          feeds.add(feed);
          signal?.addEventListener("abort", () => { feeds.delete(feed); wake?.(); });
          return {
            async *[Symbol.asyncIterator]() {
              while (!signal?.aborted) {
                if (!pending.length) await new Promise((resolve) => { wake = resolve; });
                while (pending.length) yield pending.shift();
              }
            },
          };
        },
      },
    },
  };
}

const copies = new Map();
for (const line of lines) {
  if (line.op === "setup") {
    const copy = fakeContext(line.directory);
    copy.dispose = await plugin.setup(copy.ctx);
    copies.set(line.inst, copy);
  } else if (line.op === "event") {
    copies.get(line.inst).deliver(line.event);
  } else if (line.op === "hook") {
    copies.get(line.inst).hooks.get(line.name)?.(line.input);
  } else if (line.op === "dispose") {
    await copies.get(line.inst).dispose();
    copies.delete(line.inst);
  }
  await sleep(15);
}
await sleep(300);

// First line: the processes the plugin may report as the one to watch.
console.log(JSON.stringify({ process: { pid: process.pid, ppid: process.ppid } }));
for (const post of posts) console.log(JSON.stringify(post));
server.close();
process.exit(0);
