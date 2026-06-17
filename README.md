# memory-audit-plugin

A Claude Code plugin that audits a project **memory directory** — a `MEMORY.md`
index plus per-fact `*.md` files — for rot, and proposes fixes you approve
before anything is written.

One slash command: **`/memory-audit`**.

---

## Why this exists

File-based memory (a `MEMORY.md` index loaded every session + one file per fact)
drifts over time: a shipped task still listed as "NEXT", a `*.md` deleted but its
index line left behind, a `[[link]]` whose target was renamed, near-duplicate
feedback notes, an index that quietly grows past the point of being cheap to load.
None of it is catastrophic; all of it costs context-window budget and trust.

This plugin makes the audit **one command** instead of a manual grep sweep — and
keeps a human gate on every change. The detection is a read-only script; Claude
turns findings into proposed fixes you approve.

## What it checks

| Category | Meaning |
|---|---|
| `dangling_index` | `MEMORY.md` links a `*.md` file that doesn't exist |
| `orphan_file` | a `*.md` file exists but no index line points to it |
| `unresolved_link` | a `[[slug]]` with no file whose `name:` matches |
| `done_candidate` | a `project_*` index line flagged DONE/SHIPPED/MERGED (archive?) |
| `oversize_index` | active index exceeds the threshold (default 25 lines) |
| `slug_mismatch` | a `name:` uses underscores (convention is hyphen-case) |
| `missing_frontmatter` | a `*.md` lacks `name:`/`description:` |

## Design — read-only detection, approval-gated fixes

- **`scripts/memory-audit.zsh` is READ-ONLY.** It scans and reports. It never
  edits, moves, or deletes. Run it as often as you like with zero risk.
- **The skill proposes; you approve.** Claude interprets the findings, proposes
  concrete fixes (recreate vs drop a dangling target, archive a DONE project,
  rename a slug + fix inbound links), and applies only what you OK. Mutating
  memory you can't see is the failure mode this tool prevents — so it never
  auto-deletes.

## Usage

After installing (below), in any project with a memory dir:

```
/memory-audit
```

It auto-detects the memory dir (`$CLAUDE_MEMORY_DIR` → nearest `memory/MEMORY.md`
walking up from cwd → `~/.claude/projects/<slug>/memory`). Or run the script
directly:

```sh
zsh scripts/memory-audit.zsh --dir /path/to/memory          # human report
zsh scripts/memory-audit.zsh --dir /path/to/memory --json   # machine output
zsh scripts/memory-audit.zsh --max-index 30                 # custom threshold
```

Requirements: `zsh` (macOS/Linux), standard `grep`/`sed`. No build step.

## Install (via marketplace)

```
/plugin marketplace add talgolan/memory-audit-plugin
/plugin install memory-audit-plugin@talgolan
```

Update later:

```
/plugin marketplace update talgolan
```

### Shared `talgolan` marketplace

`.claude-plugin/marketplace.json` here defines a `talgolan` catalog that lists
this plugin alongside `smoke-test-skill` and `session-continuity`. To graduate to
a single dedicated catalog repo (recommended once you have 3+ plugins), move this
`marketplace.json` into a standalone `talgolan/marketplace` repo and keep each
plugin in its own repo (the `source` entries already point at the per-plugin
github repos). Until then, adding this repo as a marketplace exposes all three.

## License

MIT — see [LICENSE](LICENSE).
