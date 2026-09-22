# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Which repo

**`AllenReder/not-boring-notch`** — this clone's `origin`, and the tracker the skills read from and write to.

This is a fork of `TheBoredTeam/boring.notch`. `gh` infers the repo from `git remote -v`, which resolves to the fork, so the commands below also pass `--repo AllenReder/not-boring-notch` explicitly. That pin is deliberate: it keeps issue operations on the fork even if a remote is added for upstream, and it means an unqualified `gh issue create` can never land in `TheBoredTeam/boring.notch` by surprise.

Upstream issues (`TheBoredTeam/boring.notch`) are reference material, not this repo's tracker. Read them with an explicit `--repo TheBoredTeam/boring.notch` when a ticket cites one.

## Conventions

- **Create an issue**: `gh issue create --repo AllenReder/not-boring-notch --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --repo AllenReder/not-boring-notch --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --repo AllenReder/not-boring-notch --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --repo AllenReder/not-boring-notch --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --repo AllenReder/not-boring-notch --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --repo AllenReder/not-boring-notch --comment "..."`

## Note: issue templates are bypassed

`.github/ISSUE_TEMPLATE/config.yml` sets `blank_issues_enabled: false`, and the templates are YAML issue forms (`bug-report.yml`, `feature-request.yml`). `gh issue create` does not fill those forms — it posts a blank-body issue, which the web UI would have blocked. That is fine for agent-created tickets, but include the fields the forms would have asked for (macOS version, app version, reproduction steps) in the body so the result is as complete as a filed form.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`. A number cited from upstream `TheBoredTeam/boring.notch` may not correspond to the same object in this fork.

## When a skill says "publish to the issue tracker"

Create a GitHub issue on `AllenReder/not-boring-notch`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --repo AllenReder/not-boring-notch --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --repo AllenReder/not-boring-notch --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/AllenReder/not-boring-notch/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/AllenReder/not-boring-notch/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --repo AllenReder/not-boring-notch --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --repo AllenReder/not-boring-notch --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
