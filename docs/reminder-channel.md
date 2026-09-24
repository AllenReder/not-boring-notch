# Reminder Channel

The Reminder Channel lets another app, a script, or an agent hook raise a reminder in the
notch. It is a loopback HTTP port: `curl` is the whole client.

The design and the reasons behind the security rules are in
[ADR-0007](adr/0007-the-reminder-channel-is-a-tokened-loopback-http-port.md). This file is the
practical guide.

## Turning it on

**Settings → Integrations.** The channel is on by default and listens on port `45999`
(configurable). Nothing on your network can reach it: it binds `127.0.0.1` only.

Three things live in that pane:

- **Port** — change it if something else already holds `45999`. If the port cannot be taken, the
  pane says so instead of failing quietly.
- **Token** — a shared secret required on every request. Regenerate it to lock out a client that
  already has it.
- **Discovery file** — the app publishes `{port, token, endpoint}` to
  `Application Support/NotBoringNotch/reminder-channel.json` inside its sandbox container, and the
  pane can reveal it in Finder.

> **If your client is sandboxed** (for example a Mac App Store app), it cannot read that file —
> sandbox containers are private to their app. Copy the port and token into the client's own
> settings instead. That is the deliberate cost of the token: it is also what keeps a web page
> in your browser from posting reminders.

## Sending one

```bash
TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/reminder-channel.json')))['token'])")

curl -X POST http://127.0.0.1:45999/reminder \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "id": "awen:session-42:build",
        "icon": { "kind": "sf_symbol", "value": "hammer" },
        "title": "Build finished",
        "subtitle": "awen · session-42",
        "body": "12 files typechecked, 0 errors.",
        "duration": 6
      }'
```

An accepted Reminder answers `202` with the id it was filed under:

```json
{ "id": "awen:session-42:build", "status": "queued" }
```

Reusing that `id` later replaces the Reminder wherever it stands — on screen or waiting — which
is how a sender reports "session 42: building" and then "session 42: done" as one card rather
than two.

## The payload

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `id` | string | generated | Reusing an id replaces that Reminder in place. |
| `icon` | object | the notch's bell | `{ "kind": …, "value": … }` — see below. |
| `title` | string | **required** | The line the closed notch shows. Cannot be empty. |
| `subtitle` | string | none | Shown beside the title, in grey. |
| `body` | string | none | Shown in full when the notch is open. In the closed notch, if no subtitle is given, the first non-empty line of the body is shown as a preview on the right wing. |
| `duration` | number | `4` | Seconds on screen. Ignored when `sticky` is true. |
| `sticky` | boolean | `false` | Stays until dismissed. |
| `sound` | string | `"none"` | `"none"` or `"default"` (the notch's own alert). |
| `action` | object | none | `{ "title": …, "url": … }` — a button that opens the URL. |

Fields the channel does not know are ignored, so a newer sender does not break an older notch.

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
curl -X POST http://127.0.0.1:45999/reminder \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"title\":\"Deploy finished\",\"icon\":{\"kind\":\"png_base64\",\"value\":\"$ICON\"}}"
```

An SF Symbol name the notch does not recognise, or PNG bytes that are not valid base64, draw the
notch's own bell rather than an empty square.

## Responses

| Status | Body | When |
| --- | --- | --- |
| `202` | `{"id":…,"status":"queued"}` | Accepted. |
| `400` | `{"error":"missing_title"}` and friends | The payload was there but wrong. |
| `401` | `{"error":"unauthorized"}` | Missing or wrong token. |
| `403` | `{"error":"forbidden_origin"}` | The request carried an `Origin` header, so it came from a browser. |
| `404` | `{"error":"not_found"}` | Wrong path. Only `POST /reminder` exists. |
| `405` | `{"error":"method_not_allowed"}` | Wrong method. |
| `411` | `{"error":"length_required"}` | No `Content-Length`. |
| `413` | `{"error":"too_large"}` | Body over 64 KiB. |
| `415` | `{"error":"unsupported_media_type"}` | `Content-Type` was not `application/json`. |

The `400` error codes are `malformed`, `missing_title`, `unknown_icon_kind`, `invalid_icon_data`,
`unknown_sound`, and `invalid_action`.

A long `body` is **not** an error: the channel keeps it whole and the notch scrolls it. The 64 KiB
cap bounds memory, not what you are allowed to say.

## What the user sees

- **Closed notch** — the icon, title, and subtitle slide out beside the camera housing,
  dynamically adapting to text length. A title or subtitle too long for the slot smoothly
  scrolls as a marquee ticker after a brief pause, rather than truncating with an ellipsis; the
  body is shown in full in the open notch, with its first line previewed in the closed slot if no
  subtitle was given.
- **Hover** — the notch opens onto the full body, the action button if there is one, and Dismiss.
- **One at a time** — a further five Reminders wait their turn; past that the oldest waiter is
  dropped, so a sender in a loop cannot flood the notch.
- **Only on the chosen display** — the same screen every other notch feature uses.
- **Hidden notch** — a Reminder that arrives while the notch is hidden by fullscreen detection
  waits, and gets its full duration once it can be seen.
