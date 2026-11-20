#!/usr/bin/env bash
#
# The helper and the app each hold a copy of AgentHooksModels.swift, because they are separate
# targets and the reports in it travel between them as JSON. A copy that drifts decodes wrongly
# at run time and nowhere sooner, so the two must be identical.
#
set -euo pipefail

helper="NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift"
app="NotBoringNotch/Agents/Hooks/AgentHooksModels.swift"

if ! diff -u "$helper" "$app"; then
  printf '❌ %s and %s differ; change both\n' "$helper" "$app"
  exit 1
fi
printf '✅ the two copies of AgentHooksModels.swift are identical\n'
