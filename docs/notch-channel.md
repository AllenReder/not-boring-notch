# Notch Channel

The Notch Channel lets another app, a script, or an agent hook send a notification to the notch.
It is a loopback HTTP port: `curl` is the whole client.

It was called the Reminder Channel until v2. Everything written against that name still works —
see [v1](#v1-post-reminder) at the end.

The design and the reasons behind the security rules are in the doc comments of
`NotBoringNotch/Channel/`. This file is the practical guide.

## How the notch presents a notification

The model is iOS's: the sender supplies content and intent, the notch decides how to show it.

- **Banner** — a notification first appears in the closed notch, icon and title on the left wing,
  subtitle on the right, for its `duration`. One at a time; up to five more wait their turn.
- **Inbox** — every notification is filed in the Inbox the moment it arrives, and stays there
  until the user clears it, clicks it, or the sender withdraws it. The open notch reaches it
  through a bell beside Settings, shown whenever the Inbox has something in it, with a dot while
  anything is unread. It keeps the
  50 most recent, across restarts unless that is turned off in Settings.
- **Hovering a banner** opens the notch on the Inbox with that notification in view. Once the
  notch closes again, the banner has been seen and gives way.
- **Clicking** a notification in the Inbox does its default action (`open`), and the notification
  is done: it leaves the Inbox. One without an `open` whose icon is an app opens that app; one
  with nowhere to go expands to show its whole body instead.

## Turning it on

**Settings → Integrations.** The channel is on by default and listens on port `45999`
(configurable). Nothing on your network can reach it: it binds `127.0.0.1` only.

- **Port** — change it if something else already holds `45999`. If the port cannot be taken, the
  pane says so instead of failing quietly.
- **Token** — a shared secret required on every request. Regenerate it to lock out a client that
  already has it.
- **Discovery file** — the app publishes `{port, token, endpoint, base_url}` to
  `Application Support/NotBoringNotch/notch-channel.json` inside its sandbox container, and the
  pane can reveal it in Finder. The same content is also written to `reminder-channel.json`, the
  name v1 clients read.

> **If your client is sandboxed** (for example a Mac App Store app), it cannot read that file —
> sandbox containers are private to their app. Copy the port and token into the client's own
> settings instead. That is the deliberate cost of the token: it is also what keeps a web page
> in your browser from posting notifications.

## Sending one

```bash
DISCOVERY="$HOME/Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/notch-channel.json"
TOKEN=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['token'])" "$DISCOVERY")

curl -X POST http://127.0.0.1:45999/v2/notifications \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "id": "build:main",
        "source": "make",
        "icon": { "kind": "sf_symbol", "value": "hammer" },
        "title": "Build finished",
        "subtitle": "12s · main",
        "body": "12 files typechecked, `0` errors.",
        "open": { "app": "com.apple.Terminal" },
        "actions": [ { "title": "Copy SHA", "copy": "0ae0b60" } ]
      }'
```

An accepted notification answers `202` with the id it was filed under:

```json
{ "id": "build:main", "status": "queued" }
```

Reusing that `id` later replaces the notification wherever it stands — on screen, waiting, or in
the Inbox — which is how a sender reports "building" and then "done" as one notification rather
than two.

### Trying it by hand

`tools/channel-playground/` is a local web page for exercising the channel: a form for every v2
and v1 field, scripted scenarios (queue overflow, sticky giving way, time-sensitive cutting in,
click targets, withdrawal, fullscreen), and a protocol check that runs every route and refusal
against its expected status.

```bash
python3 tools/channel-playground/server.py   # opens http://127.0.0.1:8765
```

A browser cannot talk to the channel itself — it sends an `Origin` header, which the channel
refuses — so the page goes through that small server, which reads the discovery file for you.

## Withdrawing one

```bash
curl -X DELETE http://127.0.0.1:45999/v2/notifications/build:main \
  -H "Authorization: Bearer $TOKEN"
```

The notification leaves the banner and the Inbox alike. Withdrawing an id that is already gone —
because the user cleared it, say — is not an error: the answer is `200` either way. Percent-encode
an id that contains `/`.

## The payload

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `id` | string | generated | Reusing an id replaces that notification in place. |
| `source` | string | none | Who is sending: `"claude-code"`, `"ci"`. Free-form. |
| `thread` | string | none | Notifications from one source that belong together, such as one session. |
| `level` | string | `"active"` | `"passive"`, `"active"`, or `"time-sensitive"` — see below. |
| `icon` | object | the notch's bell | `{ "kind": …, "value": … }` — see below. |
| `title` | string | **required** | The line the banner shows. Cannot be empty. |
| `subtitle` | string | none | Shown beside the title, in grey. |
| `body` | string | none | Inline Markdown. In the banner, its first line is the preview on the right wing when there is no subtitle, and otherwise a line under the notch, scrolling if it is long. |
| `duration` | number | `4` | Seconds the banner stays, from `1` to `60`. Values outside that are moved to the nearer end. |
| `sound` | string | `"none"` | `"none"` or `"default"` (the notch's own alert). |
| `open` | object | none | What a click does: `{ "url": … }` or `{ "app": "<bundle id>" }`, exactly one. |
| `actions` | array | none | Up to three buttons: `{ "title": …, "url": … }` or `{ "title": …, "copy": … }`. |

Fields the channel does not know are ignored, so a newer sender does not break an older notch.

### Levels

| `level` | Banner | In fullscreen | Queue |
| --- | --- | --- | --- |
| `passive` | none — straight to the Inbox | — | — |
| `active` | yes | waits until the notch can be seen | in arrival order |
| `time-sensitive` | yes | shown anyway | ahead of every `active` banner |

There is no way for a sender to make a banner stay until dismissed. How long banners stay is the
notch's decision, as it is the system's on iOS.

### Icons

| `kind` | `value` | Example |
| --- | --- | --- |
| `sf_symbol` | An SF Symbol name | `{"kind":"sf_symbol","value":"terminal"}` |
| `png_base64` | Base64 PNG bytes | `{"kind":"png_base64","value":"iVBORw0KGgo…"}` |
| `app_bundle` | A bundle identifier | `{"kind":"app_bundle","value":"com.apple.Terminal"}` |

`png_base64` exists because the notch is sandboxed and **cannot read a path you give it**. A
shell sender inlines the bytes instead:

```bash
ICON=$(base64 -i ~/icon.png)
curl -X POST http://127.0.0.1:45999/v2/notifications \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"title\":\"Deploy finished\",\"icon\":{\"kind\":\"png_base64\",\"value\":\"$ICON\"}}"
```

An SF Symbol name the notch does not recognise, or PNG bytes that are not valid base64, draw the
notch's own bell rather than an empty square. An `app_bundle` icon also makes the app a click
target when the notification has no `open` of its own.

### Opening the right place

`open` is how a notification gets the user back to where it came from:

- an editor window: `{ "url": "vscode://file/Users/me/code/app" }` (or `cursor://file/…`)
- a terminal app: `{ "app": "com.googlecode.iterm2" }`, `{ "app": "com.mitchellh.ghostty" }`,
  `{ "app": "com.apple.Terminal" }`
- a page: `{ "url": "https://github.com/me/app/pull/42" }`

A terminal is brought forward, not a particular tab in it: reaching a tab would take scripting each
terminal separately, which the sandbox does not allow.

## Agents

The channel also knows what Claude Code, Codex and pi sessions are doing. A hook in the agent posts
each event it fires, as the agent wrote it, and the notch works out the rest: how many sessions are
working or waiting for you, when a turn has ended, and where a click should take you.

```bash
curl -X POST http://127.0.0.1:45999/v2/agents/claude-code/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Agent-Pid: $PPID" \
  -H "X-Agent-Host-Bundle: $__CFBundleIdentifier" \
  --data-binary @hook-event.json
```

| Route | Answer | Does |
| --- | --- | --- |
| `POST /v2/agents/claude-code/events` | `202 {"status":"accepted"}` | A Claude Code hook event. |
| `POST /v2/agents/codex/events` | `202 {"status":"accepted"}` | A Codex hook event. |
| `POST /v2/agents/pi/events` | `202 {"status":"accepted"}` | A pi extension event. |

The body is the hook's JSON, untouched: the notch reads `hook_event_name`, `session_id`, `cwd`,
`tool_name`, `notification_type` and `last_assistant_message` from it, and nothing else. A hook it
does not know gets `202 {"status":"ignored"}`, not an error, so a newer agent version that adds
hooks does not break an older notch. A body that is not a JSON object gets `400 malformed`, and
one without a `session_id` gets `400 missing_session_id`. The same token, origin and content-type
rules apply as for notifications. This route takes bodies up to 4 MiB, because a hook carries the
tool call it reports; every other route stays at 64 KiB.

pi has no command hooks, so the notch installs an extension instead,
`~/.pi/agent/extensions/not-boring-notch.ts`. It posts pi's own event names (`session_start`,
`agent_start`, `tool_execution_start`, `tool_execution_end`, `ui_prompt_start`, `ui_prompt_end`,
`agent_settled`, `session_shutdown`) with `session_id`, `cwd`, `tool_name`, `prompt_kind`,
`aborted`, `stop_reason`, `error` and `last_assistant_message`, and sends the same headers as the
hook script. A `confirm` prompt is an approval, any other prompt a question. It reports pi in a
terminal and pi in T3 Code (`--mode rpc`), and leaves out `pi -p`, `--mode json` and pi's
sub-agents, so a sub-agent is never counted as a session of its own.

Everything the notch cannot read from the body, the hook script reports in headers. Empty values
are left out.

| Header | Value |
| --- | --- |
| `X-Agent-Pid` | The agent's process id, so the notch can tell when it has gone. |
| `X-Agent-Host-Bundle` | `$__CFBundleIdentifier`: the app the agent runs in. A click brings it forward. |
| `X-Agent-Term-Program` | `$TERM_PROGRAM`. |
| `X-Agent-Tmux-Pane` | `$TMUX_PANE`. |
| `X-Agent-T3-Thread` | `$T3CODE_THREAD_ID`. A click on a session inside a T3 Code thread opens that thread. Two agents in one thread, such as a Claude session that runs `codex exec`, are still two sessions. |
| `X-Agent-T3-Environment` | The T3 Code environment id, only with a thread. With it a click opens `t3code://threads/<environment>/<thread>`; without it, T3 Code is brought forward. |

### On the notch

- **Closed notch.** The agents are a resident, like the music. The left wing shows the mark of
  each kind of agent at work, stacked, slowly dimming and brightening while any of them works.
  The right wing shows how many sessions are working, in grey. When one is waiting for you, the
  marks hold still with an amber dot, and the right wing reads `! 1 | 2`: one waiting, in amber,
  then a light rule, then two working, in grey. Agents waiting
  for you always go ahead of the music; agents that are only working go ahead of it too, unless
  the music has been put first for good (the `musicAheadOfAgents` default). When the music holds
  the wings, the agents shrink to the right one: the spinner with the count inside it.
- **A turn ends.** A banner titled with the project's name (the last segment of `cwd`), with the
  first line of the agent's last message as its body. A turn shorter than 10 seconds goes to the
  Inbox without a banner. A turn that failed says so.
- **It needs you.** A permission request or a question raises a time-sensitive banner, which stays
  until seen and is taken back as soon as the session carries on, ends, or is interrupted.
- **The Inbox.** An *Agents* section at the top lists every session with its name, what it is
  doing, and how long. Clicking a row, or a notification about it, goes to its T3 thread or its
  app.
- **Names.** A session is named after the last folder of its working directory. A session in a T3
  Code thread is named after the thread, with the folder after it in grey: `Agent通知功能 ·
  notch-channel-v2`. The helper reads the title with T3 Code's own CLI, `~/.t3/bin/t3 thread show
  --json`. It reads it when the thread is first seen, and again at most every 30 seconds while a
  session in the thread is in a turn. A banner keeps the name it was delivered with.

The notifications are ordinary ones: `agent-wait:<session>` for a wait and `agent-done:<session>`
for a finished turn, with the session as their `thread`. A newer one replaces the older in place.

Sessions are not kept across restarts; the next hook from a running session brings it back. A
session whose process has gone is removed. One that is working but has sent nothing for 15 minutes,
with no sign that its process is still there, is settled as idle without a notification.

## Responses

| Status | Body | When |
| --- | --- | --- |
| `200` | `{"id":…,"status":"withdrawn"}` | A `DELETE` was accepted. |
| `202` | `{"id":…,"status":"queued"}` | A notification was accepted. |
| `400` | `{"error":"missing_title"}` and friends | The payload was there but wrong. |
| `401` | `{"error":"unauthorized"}` | Missing or wrong token. |
| `403` | `{"error":"forbidden_origin"}` | The request carried an `Origin` header, so it came from a browser. |
| `404` | `{"error":"not_found"}` | A path the channel does not serve. |
| `405` | `{"error":"method_not_allowed"}` | A path it serves, with the wrong method. |
| `411` | `{"error":"length_required"}` | A `POST` without `Content-Length`. |
| `413` | `{"error":"too_large"}` | Body over 64 KiB (4 MiB for agent events). |
| `415` | `{"error":"unsupported_media_type"}` | A `POST` whose `Content-Type` was not `application/json`. |

The `400` error codes are `malformed`, `missing_title`, `unknown_icon_kind`, `invalid_icon_data`,
`unknown_sound`, `unknown_level`, `invalid_open`, `invalid_action`, and `too_many_actions`. The
ones about a value name it: `{"error":"unknown_level","level":"critical"}`.

A long `body` is **not** an error: the channel keeps it whole, and the Inbox shows two lines of it
until the notification is clicked open. The 64 KiB cap bounds memory, not what you are allowed to
say.

## v1: `POST /reminder`

The Reminder Channel's one route keeps working unchanged, so nothing written against it has to
move. A v1 Reminder becomes an `active` notification:

| v1 field | becomes |
| --- | --- |
| `id`, `icon`, `title`, `subtitle`, `body`, `duration`, `sound` | the same v2 field |
| `action` `{title, url}` | one entry in `actions` |
| `sticky: true` | a banner that, past its duration, stays until the user has seen it — but only while nothing else is waiting, so it can no longer hold up every reminder behind it |

New senders should use `/v2/notifications`.
