# 0004. Hard Fork from Upstream

## Context

Not Boring Notch began as a fork of [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch) and has since been rebranded, given its own release channel, CI, and documentation. The two histories are related — this repository's early commits are upstream's — but they have diverged, and none of the inherited build machinery for upstream's release process works here: it required upstream's Developer ID signing certificates, a Sparkle private key for a Sparkle framework this project no longer ships, and a Crowdin project it does not own.

## Decision

This project is a **hard fork**. There is no regular sync from upstream, and upstream's branch policy, release pipeline, and translation pipeline do not apply here:

- Development happens on `main`; contributors branch off it and open pull requests against it.
- Releases are built locally by the maintainer and published as GitHub Releases. There is no CI signing, notarization, or appcast pipeline.
- Translations live in `NotBoringNotch/Localizable.xcstrings`. New strings are English; translation updates are welcome as pull requests that edit that file. Crowdin is not used.

Upstream remains a reference and a source of security and system-compatibility fixes. If one is needed it is taken manually, never as a scheduled merge.

## Considered Options

- **Regularly merge upstream into this fork.** Rejected: the rebranding (README, icons, CI, documentation) conflicts with every sync, and the cost of resolving those conflicts exceeds the value of the fixes pulled in.
- **Adopt upstream's `dev`-branch release model.** Rejected: that model exists to batch work for a Crowdin-keyed release pipeline this project does not have, and its enforcement workflows told contributors to target a branch that does not exist here.

## Consequences

- macOS and SDK changes, and changes to the private Media Remote API this app depends on, are this project's own responsibility.
- Inherited instructions, workflows, and services that described upstream's process have been removed or rewritten. Where a contributor-visible instruction disagrees with this ADR, this ADR is right.
- Upstream's early history remains in this repository's history, so its authorship and copyright are intact.
