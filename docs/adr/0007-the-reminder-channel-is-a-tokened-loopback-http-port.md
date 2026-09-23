# 0007. The Reminder Channel Is a Tokened Loopback HTTP Port

## Context

External processes need to raise a Reminder in the notch — an agent hook reporting that a
build finished, a console reporting that a session needs attention. The notch is a sandboxed
app (`com.apple.security.app-sandbox`), so it can neither read a file the sender names nor be
reached through a shared directory the sender chooses. Four transports were on the table: a
loopback HTTP port, an HTTP-over-Unix-socket, a `notboringnotch://` URL scheme, and a Darwin
distributed notification (the app already carries a dead half of that last one — a decoder
with nothing registered to call it).

Two facts about the environment decided most of this. A loopback listener needs no entitlement
the app does not already hold (`network.server`), and **any web page the user has open can
POST to `127.0.0.1`**: a `no-cors` POST with a safelisted content type is a "simple request",
so it is sent without a preflight and without the page's JavaScript being able to read the
reply. "It is only reachable from this machine" is not a security boundary.

## Decision

The Reminder Channel is **HTTP on `127.0.0.1`**, bound to loopback only, on a configurable
port, with a few rules that are not negotiable:

- **A Channel Token is required**, sent as `Authorization: Bearer`. The app publishes the port
  and token in a discovery file inside its own sandbox container, and shows both (with a copy
  button) in Settings.
- **`Content-Type: application/json` is required.** A browser sending that type must preflight,
  and the channel does not answer preflights.
- **Any request carrying a non-empty `Origin` is refused.** Cheap, and it costs no real client
  anything.
- **Icons are never paths.** A sender inlines PNG bytes (base64) or names an SF Symbol, because
  the app cannot read the sender's file. A bundle identifier may be sent instead, for the app's
  own icon, pending a sandbox spike.
- **The channel is one-way.** A sender is told the Reminder was accepted, never what the user
  did about it.

## Considered Options

- **Darwin distributed notification** (the vestigial `sneakPeekEvent` decoder). Rejected: not
  answerable — no response body to grow into — and its payload ceiling is too low to carry an
  icon.
- **A `notboringnotch://` URL scheme.** Rejected: payloads are mangled by URL escaping and image
  bytes cannot ride along, and `open` costs a launch round trip per Reminder.
- **HTTP over a Unix socket.** Rejected on discoverability: the socket would still live inside
  the sandbox container, so it has the same reachability problem as the discovery file while
  losing the one thing that makes the port cheap — `curl` with no arguments beyond a URL.
- **No token, trusting anything local.** Rejected: it cannot distinguish a shell from a web page.
  `Origin` checking alone has the same hole in reverse — any local process can set that header.
- **Blocking permission prompts in the same channel** (as ClaudeNotch does). Rejected for now:
  it makes an external agent's progress depend on the notch's UI, and turns a notification
  surface into a permission broker. The payload carries an id and a shape that a response could
  be added to later without a wire break.

## Consequences

- A **sandboxed** third-party app cannot read the discovery file, so it cannot discover the port
  and token automatically; the user must paste both in. That is the price of not being open to
  every web page, and it is the reason the Settings pane shows them.
- The port can be occupied by something else. The app reports the failure in Settings rather
  than silently listening nowhere, and the port is configurable.
- The token is readable by any unsandboxed process running as the user. It is a boundary against
  browser pages and sandboxed apps, not against a process that is already the user.
- The reminder payload is a public interface from the moment it ships. Adding fields is safe
  (unknown fields are ignored); changing the meaning of an existing one is not.
