#!/usr/bin/env python3
"""Cuts the OpenCode capture Tests/Fixtures/opencode/serve-capture.jsonl out of a raw capture.

The raw capture is the JSONL a logging plugin wrote while real `opencode serve` (v2.3.2) runs
happened: every event, tool hook and `session.get` answer, per plugin instance. This keeps only
what the notch plugin listens to, scrubs the paths and the T3 thread id, and writes one line per
step for Tests/OpenCodePlugin/replay.mjs:

    {"op":"setup","inst":...,"directory":...}      a plugin copy starts, for that directory
    {"op":"session","info":{...}}                  what `session.get` answers for that session, throughout
    {"op":"event","inst":...,"event":{...}}        an event that copy hears
    {"op":"hook","inst":...,"name":...,"input":{}} a tool hook that copy is called for
    {"op":"dispose","inst":...}                    that copy is torn down

Usage: make-fixture.py <raw-capture.jsonl> > serve-capture.jsonl
"""
import json, re, sys

WANTED = {
    "session.created", "session.deleted", "session.text.ended", "session.execution.started",
    "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted",
    "permission.asked", "permission.replied", "form.created", "form.replied", "form.cancelled",
}
PREFIX = re.compile(r"/private/tmp/claude-501/[^\"]*?/scratchpad")
THREAD = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

def scrub(value):
    text = PREFIX.sub("/work", json.dumps(value))
    return json.loads(THREAD.sub("thread-1", text))

out, seen = [], set()
def emit(line):
    out.append(json.dumps(scrub(line), separators=(",", ":")))

for raw in open(sys.argv[1]):
    r = json.loads(raw)
    kind, data, inst = r["kind"], r["data"], r.get("inst") or "first"
    if kind == "setup":
        emit({"op": "setup", "inst": inst, "directory": data["location"]["directory"]})
    elif kind == "dispose":
        emit({"op": "dispose", "inst": inst})
    elif kind == "probe.session.get":
        # The probe kept only some fields; those are the ones the plugin reads.
        info = {k: data[k] for k in ("id", "location", "permissions", "parentID") if k in data}
        if info["id"] not in seen:
            seen.add(info["id"]); emit({"op": "session", "info": info})
    elif kind.startswith("tool.hook:"):
        emit({"op": "hook", "inst": inst, "name": kind.split(":")[1],
              "input": {k: data[k] for k in ("tool", "sessionID")}})
    elif kind == "event" and data["type"] in WANTED:
        d = data["data"]
        sid = d.get("sessionID") or d.get("form", {}).get("sessionID")
        if data["type"] == "session.created" and sid not in seen:
            seen.add(sid)
            info = {"id": sid, "location": d["location"]}
            if "parentID" in d: info["parentID"] = d["parentID"]
            emit({"op": "session", "info": info})
        keep = {k: data[k] for k in ("type", "location", "data") if k in data}
        emit({"op": "event", "inst": inst, "event": keep})
print("\n".join(out))
