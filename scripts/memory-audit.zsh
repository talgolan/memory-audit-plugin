#!/usr/bin/env zsh
###############################################################################
# memory-audit.zsh — READ-ONLY auditor for a Claude Code project memory dir.
#
# Scans a memory directory (MEMORY.md index + per-fact *.md files) and reports
# rot. It NEVER mutates anything — it prints findings; the /memory-audit skill
# interprets them and proposes fixes for the user to approve.
#
# Usage:
#   memory-audit.zsh [--dir <memory-dir>] [--json] [--max-index <N>]
#
#   --dir <path>     Memory dir to audit. Default: auto-detect (see below).
#   --json           Emit machine-readable JSON instead of human text.
#   --max-index <N>  Index-size threshold for the oversize check (default 25).
#
# Auto-detect order for the memory dir:
#   1. $CLAUDE_MEMORY_DIR if set.
#   2. The nearest `memory/` dir containing MEMORY.md, walking up from $PWD.
#   3. ~/.claude/projects/<slug>/memory for the current project, if present.
#
# Checks (each is a finding category):
#   dangling_index   — MEMORY.md links to a *.md file that does not exist.
#   orphan_file      — a *.md file exists but no MEMORY.md line references it.
#   unresolved_link  — a [[slug]] with no file whose `name:` frontmatter matches.
#   done_candidate   — a project_* index line flagged DONE/SHIPPED/MERGED (archive?).
#   oversize_index   — active index line count exceeds --max-index.
#   slug_mismatch    — a file's `name:` uses underscores or != its [[link]] slug convention.
#   missing_frontmatter — a *.md file lacks a `name:`/`description:` header.
#
# Exit code: 0 always (a report, not a gate). Finding counts are in the output.
###############################################################################
emulate -L zsh
set -u

# ── args ─────────────────────────────────────────────────────────────────────
DIR=""
JSON=0
MAX_INDEX=25
while (( $# )); do
  case "$1" in
    --dir)       DIR="$2"; shift 2 ;;
    --json)      JSON=1; shift ;;
    --max-index) MAX_INDEX="$2"; shift 2 ;;
    -h|--help)   sed -n '2,32p' "$0"; exit 0 ;;
    *)           print -u2 "memory-audit: unknown arg: $1"; exit 2 ;;
  esac
done

# ── locate the memory dir ────────────────────────────────────────────────────
_find_dir() {
  [[ -n "${CLAUDE_MEMORY_DIR:-}" && -f "${CLAUDE_MEMORY_DIR}/MEMORY.md" ]] && { print -r -- "$CLAUDE_MEMORY_DIR"; return 0; }
  local d="$PWD"
  while [[ -n "$d" && "$d" != "/" ]]; do
    [[ -f "$d/memory/MEMORY.md" ]] && { print -r -- "$d/memory"; return 0; }
    [[ -f "$d/MEMORY.md" ]] && { print -r -- "$d"; return 0; }
    d="${d:h}"
  done
  # project-scoped default
  local slug="${PWD//\//-}"
  local cand="$HOME/.claude/projects/${slug}/memory"
  [[ -f "$cand/MEMORY.md" ]] && { print -r -- "$cand"; return 0; }
  return 1
}
[[ -z "$DIR" ]] && DIR="$(_find_dir)"
if [[ -z "$DIR" || ! -f "$DIR/MEMORY.md" ]]; then
  print -u2 "memory-audit: no MEMORY.md found (looked in: ${DIR:-<auto>}). Pass --dir <path>."
  exit 2
fi
MEM="$DIR/MEMORY.md"

# ── collect ──────────────────────────────────────────────────────────────────
# Active *.md files (exclude MEMORY.md + anything under archive/).
typeset -a files
files=("$DIR"/*.md(N))
typeset -a active_files
for f in $files; do
  [[ "${f:t}" == "MEMORY.md" ]] && continue
  active_files+=("${f:t}")
done

# Index pointers: (file.md) targets referenced from MEMORY.md.
typeset -a index_targets
index_targets=(${(f)"$(grep -oE '\((feedback|project|reference|user)_[a-z0-9_]+\.md\)' "$MEM" 2>/dev/null | tr -d '()')"})

# Active index line count (lines starting "- [").
local index_lines=$(grep -cE '^- \[' "$MEM" 2>/dev/null)

# ── findings ─────────────────────────────────────────────────────────────────
typeset -a f_dangling f_orphan f_unresolved f_done f_slug f_missing_fm
local f_oversize=""

# dangling_index: index → missing file
for t in $index_targets; do
  [[ -f "$DIR/$t" ]] || f_dangling+=("$t")
done

# orphan_file: file with no index reference
for a in $active_files; do
  print -r -- "$index_targets" | grep -qw "$a" || f_orphan+=("$a")
done

# unresolved_link: [[slug]] with no matching `name:` field. Ignore the literal
# token "links" (appears in prose like "fix inbound [[links]]").
typeset -a all_slugs
all_slugs=(${(fu)"$(grep -rohE '\[\[[a-z0-9-]+\]\]' "$DIR"/*.md(N) 2>/dev/null | tr -d '[]')"})
for s in $all_slugs; do
  [[ "$s" == "links" ]] && continue
  grep -rqE "^name: ${s}\$" "$DIR"/*.md(N) 2>/dev/null || f_unresolved+=("$s")
done

# done_candidate: project_* index line flagged DONE/SHIPPED/MERGED
while IFS= read -r line; do
  [[ "$line" == *'(project_'*'.md)'* ]] || continue
  print -r -- "$line" | grep -qiE 'DONE|SHIPPED|MERGED|no pending work|✅' || continue
  # extract the project_*.md file token for actionability (robust grep, not a
  # fragile nested parameter expansion).
  local tok=$(print -r -- "$line" | grep -oE 'project_[a-z0-9_]+\.md' | head -1)
  f_done+=("${tok:-${line[1,60]}}")
done < <(grep -E '^- \[' "$MEM" 2>/dev/null)

# oversize_index
(( index_lines > MAX_INDEX )) && f_oversize="$index_lines > $MAX_INDEX"

# slug_mismatch + missing_frontmatter: per active file
for a in $active_files; do
  # NB: combined `local x=$(...)` — a separate `local x` then `x=$(...)` echoes
  # the assignment to stdout under `emulate -L zsh` at script scope (zsh quirk).
  local nm=$(grep -m1 -E '^name:' "$DIR/$a" 2>/dev/null | sed -E 's/^name:[[:space:]]*//')
  if [[ -z "$nm" ]] || ! grep -qE '^description:' "$DIR/$a" 2>/dev/null; then
    f_missing_fm+=("$a")
    continue
  fi
  # convention: name slug should be hyphen-case (no underscores)
  [[ "$nm" == *_* ]] && f_slug+=("$a (name: $nm — underscores; convention is hyphen-case)")
done

# ── output ───────────────────────────────────────────────────────────────────
local total=$(( ${#f_dangling} + ${#f_orphan} + ${#f_unresolved} + ${#f_done} + ${#f_slug} + ${#f_missing_fm} ))
[[ -n "$f_oversize" ]] && (( total++ ))

if (( JSON )); then
  _arr() { local first=1; printf '['; for x in "$@"; do (( first )) || printf ','; printf '%s' "\"${x//\"/\\\"}\""; first=0; done; printf ']'; }
  printf '{\n'
  printf '  "dir": "%s",\n' "$DIR"
  printf '  "index_lines": %s,\n' "${index_lines:-0}"
  printf '  "active_files": %s,\n' "${#active_files}"
  printf '  "total_findings": %s,\n' "$total"
  printf '  "dangling_index": %s,\n' "$(_arr "${f_dangling[@]}")"
  printf '  "orphan_file": %s,\n' "$(_arr "${f_orphan[@]}")"
  printf '  "unresolved_link": %s,\n' "$(_arr "${f_unresolved[@]}")"
  printf '  "done_candidate": %s,\n' "$(_arr "${f_done[@]}")"
  printf '  "slug_mismatch": %s,\n' "$(_arr "${f_slug[@]}")"
  printf '  "missing_frontmatter": %s,\n' "$(_arr "${f_missing_fm[@]}")"
  printf '  "oversize_index": "%s"\n' "$f_oversize"
  printf '}\n'
  exit 0
fi

print -- "memory-audit — $DIR"
print -- "  index lines: ${index_lines:-0}   active files: ${#active_files}   findings: $total"
print -- ""
_section() {
  local title="$1"; shift
  (( $# )) || { print -- "  ✓ $title: none"; return; }
  print -- "  ✗ $title ($#):"
  for x in "$@"; do print -- "      - $x"; done
}
_section "dangling index pointers (index → missing file)" "${f_dangling[@]}"
_section "orphan files (no index line)"                    "${f_orphan[@]}"
_section "unresolved [[links]] (no matching name:)"        "${f_unresolved[@]}"
_section "DONE/shipped archive candidates"                 "${f_done[@]}"
_section "slug mismatches (underscores in name:)"          "${f_slug[@]}"
_section "missing frontmatter (name:/description:)"        "${f_missing_fm[@]}"
if [[ -n "$f_oversize" ]]; then
  print -- "  ✗ oversize index: $f_oversize"
else
  print -- "  ✓ index size within threshold ($MAX_INDEX)"
fi
print -- ""
if (( total == 0 )); then
  print -- "  Clean — no rot detected."
else
  print -- "  $total finding(s). The /memory-audit skill will propose approval-gated fixes."
fi
exit 0
