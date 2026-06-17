---
name: memory-audit
description: Audit a Claude Code project memory directory for rot and propose approval-gated fixes. Use when the user says "audit my memory", "/memory-audit", "check the memory dir", "is my memory clean", "clean up memory", or after adding/removing memories. Reports dangling index pointers, orphan files, unresolved [[links]], shipped/DONE archive candidates, an oversize index, and frontmatter/slug issues — then proposes fixes you approve before any change.
---

# memory-audit

Audits a Claude Code project memory directory — a `MEMORY.md` index plus
per-fact `*.md` files (the file-based memory described in the user's memory
instructions) — for the kinds of rot that accumulate over time, and proposes
fixes the user approves before anything is written.

## When to invoke

| User says | Action |
|---|---|
| "/memory-audit", "audit my memory", "check the memory dir" | Run the audit + report |
| "is my memory clean / organized", "clean up memory" | Run the audit, then propose fixes |
| After adding/removing several memories in a session | Offer to run it |

## The split (why this is safe)

- **The script is READ-ONLY.** `${CLAUDE_PLUGIN_ROOT}/scripts/memory-audit.zsh`
  scans and reports. It never edits, moves, or deletes anything.
- **You (Claude) interpret + propose.** Turn findings into concrete fixes and
  present them for approval. NEVER auto-apply destructive changes (delete /
  archive / rewrite) without the user's explicit OK — mutating memory the user
  can't see is the exact failure mode this tool exists to prevent.

## How to run it

Run the auditor from the user's project (it auto-detects the memory dir), or
pass `--dir` explicitly. Try, in order, until one works:

  1. `zsh "${CLAUDE_PLUGIN_ROOT}/scripts/memory-audit.zsh" {{args}}`
  2. `zsh scripts/memory-audit.zsh {{args}}`   (if the plugin root is the cwd)

Useful flags: `--dir <path>` (audit a specific memory dir), `--json` (machine
output for your own parsing), `--max-index <N>` (oversize threshold, default 25).

Auto-detection order: `$CLAUDE_MEMORY_DIR` → nearest `memory/MEMORY.md` walking
up from cwd → `~/.claude/projects/<slug>/memory`. If it can't find one, ask the
user for the path and re-run with `--dir`.

## What it checks (finding categories)

| Category | Meaning | Typical fix to PROPOSE |
|---|---|---|
| `dangling_index` | `MEMORY.md` links a `*.md` file that doesn't exist | Recreate the file from its index hook, OR drop the index line — ask which |
| `orphan_file` | a `*.md` file exists but no index line points to it | Add an index line, OR archive/delete if obsolete |
| `unresolved_link` | a `[[slug]]` with no file whose `name:` matches | Fix the slug on the link or the target's `name:` (hyphen-case convention) |
| `done_candidate` | a `project_*` index line flagged DONE/SHIPPED/MERGED | Move the file to `archive/` + delete the index line (history without the cost) |
| `oversize_index` | active index exceeds the threshold | Audit for DONE/duplicate/stale before it grows further |
| `slug_mismatch` | a `name:` uses underscores (convention is hyphen-case) | Rename the `name:` field + fix inbound links |
| `missing_frontmatter` | a `*.md` lacks `name:`/`description:` | Add the header |

## How to act on the report

1. Run the script; read the findings.
2. For EACH finding, form a concrete proposed fix (use the table above). Where a
   fix is ambiguous (recreate vs delete a dangling target), present BOTH options
   and let the user choose — don't pick silently.
3. Apply ONLY what the user approves. Prefer the maintenance-contract rules if
   the user's `MEMORY.md` has them (one current-task pointer; archive DONE same
   session; extend near-duplicate feedback rather than create siblings;
   supersede = delete + fix links, no tombstones).
4. Judgment checks the script can't do — look for these yourself: near-duplicate
   `feedback` memories (same lesson, two files → propose extend+delete), and a
   stale "NEXT TASK"/"current" pointer to work that has shipped.
5. Re-run the script after applying fixes to confirm a clean report.

## Boundaries

- Read-only by default. No deletion, archiving, or rewrite without explicit
  approval.
- Don't fabricate facts when recreating a dangling target — recreate only from
  surviving evidence (the index hook, inbound links) and say so; verify any
  code/file claim against the real source before asserting it.
