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
| `body` | string | none | Inline Markdown. In the banner, if no subtitle is given, its first line is the preview. |
| `duration` | number | `4` | Seconds the banner stays. |
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
| `413` | `{"error":"too_large"}` | Body over 64 KiB. |
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
