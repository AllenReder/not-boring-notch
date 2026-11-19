//
//  AgentHookScript.swift
//  NotBoringNotch
//
//  The hook bridge that Claude Code and Codex run. It is a `sh` script, not a Swift target, so
//  that a change in an agent's payload is handled by the app (which parses the body) and never by
//  a reinstall. The script only forwards the hook's stdin to the Notch Channel and adds the facts
//  that only its own process can see: which process is the agent, and where it runs.
//
//  The sandboxed app cannot write to ~/.not-boring-notch, so the text travels over XPC to the
//  helper, which installs it and decides where. See NotBoringNotchXPCHelper/AgentHooks/.
//

import Foundation

enum AgentHookScript {
    /// Bump whenever `source` changes, so an installed copy can be told apart from the bundled
    /// one. The number is written into the script as its second line.
    static let version = 1

    /// Usage: `notch-agent-hook <claude-code|codex>`, with the hook's JSON on stdin.
    ///
    /// Never prints, always exits 0 and gives up after about a second, because it runs on the
    /// agent's critical path. The token goes to curl through a private config file rather than
    /// the command line, where any process could read it with `ps`.
    static let source = #"""
    #!/bin/sh
    # notch-agent-hook-version: \#(version)
    # Forwards a Claude Code / Codex hook to Not Boring Notch. Usage: notch-agent-hook <claude-code|codex>
    exec 2>/dev/null
    agent="$1"
    discovery="$HOME/Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/notch-channel.json"
    case "$agent" in claude-code|codex) ;; *) cat >/dev/null; exit 0 ;; esac
    if [ ! -f "$discovery" ]; then cat >/dev/null; exit 0; fi
    port=$(plutil -extract port raw -o - "$discovery")
    token=$(plutil -extract token raw -o - "$discovery")
    if [ -z "$port" ] || [ -z "$token" ]; then cat >/dev/null; exit 0; fi

    # The agent is the nearest ancestor named claude or codex; the hook's parent is usually a shell.
    pid=$PPID
    found=
    hops=0
    while [ "$hops" -lt 6 ] && [ "$pid" -gt 1 ]; do
      name=$(ps -o comm= -p "$pid")
      case "${name##*/}" in claude|claude.exe|codex) found=1; break ;; esac
      pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
      [ -z "$pid" ] && break
      hops=$((hops + 1))
    done
    [ -z "$found" ] && pid=

    env_id=
    if [ -n "$T3CODE_THREAD_ID" ]; then
      read -r env_id < "${T3CODE_HOME:-$HOME/.t3}/userdata/environment-id"
    fi

    cfg=$(mktemp "${TMPDIR:-/tmp}/notch-hook.XXXXXX") || { cat >/dev/null; exit 0; }
    trap 'rm -f "$cfg"' EXIT
    nl='
    '
    cr=$(printf '\r')
    # One header per line of a curl config. An empty value, or one that could break out of the
    # quoted string, is left out.
    header() {
      case "$2" in ""|*'"'*|*'\'*|*"$nl"*|*"$cr"*) return ;; esac
      printf 'header = "%s: %s"\n' "$1" "$2" >> "$cfg"
    }
    header Authorization "Bearer $token"
    header Content-Type application/json
    header X-Agent-Pid "$pid"
    header X-Agent-Host-Bundle "$__CFBundleIdentifier"
    header X-Agent-Term-Program "$TERM_PROGRAM"
    header X-Agent-Tmux-Pane "$TMUX_PANE"
    header X-Agent-T3-Thread "$T3CODE_THREAD_ID"
    header X-Agent-T3-Environment "$env_id"

    curl -s -m 1 -o /dev/null -X POST -K "$cfg" --data-binary @- "http://127.0.0.1:$port/v2/agents/$agent/events"
    cat >/dev/null
    exit 0
    """#
}
