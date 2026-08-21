#!/bin/sh
# Collect a compact, token-efficient snapshot of the staged git changes.
#
# The output is consumed by a small model (Haiku-class) that must return a
# single Conventional Commits subject line, so every line here is a deliberate
# trade between signal and tokens:
#   - a one-line-per-file table (numstat, not the --stat histogram)
#   - the real hunks with only 2 lines of context
#   - noise files (lock files, build output, data, binaries) listed but not diffed
#   - hard caps per file and in total, so a huge commit stays fast
#
# Written in POSIX sh + awk on purpose: those are available everywhere git is,
# including Git Bash on Windows, with no interpreter-name ambiguity.
#
# Environment overrides:
#   COMMIT_DESC_MAX_CHARS       total budget for the diff body (default 20000)
#   COMMIT_DESC_MAX_FILE_CHARS  per-file budget for the diff body (default 2000)
#   COMMIT_DESC_CONTEXT         diff context lines (default 2)
#   COMMIT_DESC_LOG_COUNT       recent commit subjects to include (default 5)
#
# Always exits 0: the caller is a prompt, not a build step, so problems must
# come back as readable text instead of an empty injection.

MAXT=${COMMIT_DESC_MAX_CHARS:-20000}
MAXF=${COMMIT_DESC_MAX_FILE_CHARS:-2000}
CTX=${COMMIT_DESC_CONTEXT:-2}
LOGN=${COMMIT_DESC_LOG_COUNT:-5}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository."
  exit 0
fi

if [ -z "$(git diff --cached --name-only 2>/dev/null)" ]; then
  echo "NOTHING STAGED: 'git diff --cached' is empty."
  pending=$( { git diff --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | head -30 )
  if [ -n "$pending" ]; then
    echo "Unstaged or untracked files that could be added with 'git add':"
    echo "$pending" | sed 's/^/  /'
  fi
  exit 0
fi

echo "BRANCH: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

log=$(git log "-$LOGN" --pretty=%s 2>/dev/null)
if [ -n "$log" ]; then
  echo "RECENT COMMIT SUBJECTS (match this repo's existing style):"
  echo "$log" | sed 's/^/  /'
fi

echo "STAGED FILES (+added/-deleted lines, 'binary' when git cannot diff it):"
git diff --cached --numstat -M 2>/dev/null | awk -F'\t' '{
  counts = ($1 == "-") ? "binary" : "+" $1 "/-" $2
  printf "  %12s  %s\n", counts, $3
}'

echo "DIFF (context=$CTX; lock files, build output, data files and binaries are listed above but not diffed):"
# Exclusion list kept byte-identical to SKILL.md and measure_history.{sh,ps1}.
# Those two measure what the skill really sends, so any drift here silently makes
# their numbers wrong. Note that '*' crosses '/' in a git pathspec, so '*.lock'
# already covers yarn.lock, Cargo.lock and friends at any depth -- but not
# pnpm-lock.yaml, which is why that one is listed explicitly.
git diff --cached -M "-U$CTX" --no-color --no-ext-diff --diff-algorithm=minimal -- . \
  ':(exclude)*.lock' \
  ':(exclude)*-lock.json' \
  ':(exclude)*.lockb' \
  ':(exclude)pnpm-lock.yaml' \
  ':(exclude)*.min.js' \
  ':(exclude)*.min.css' \
  ':(exclude)*.map' \
  ':(exclude)*.snap' \
  ':(exclude)*.ipynb' \
  ':(exclude)*.csv' \
  ':(exclude)*.tsv' \
  ':(exclude)*.parquet' \
  ':(exclude)*.xlsx' \
  ':(exclude)*.geojson' \
  ':(exclude)*.pdf' \
  ':(exclude)*.svg' \
  ':(exclude)*.png' \
  ':(exclude)*.jpg' \
  ':(exclude)*.jpeg' \
  ':(exclude)*.gif' \
  ':(exclude)*.ico' \
  ':(exclude)*.pkl' \
  ':(exclude)*.h5' \
  ':(exclude)*.onnx' \
  ':(exclude)*.zip' \
  ':(exclude)dist/*' \
  ':(exclude)*/dist/*' \
  ':(exclude)build/*' \
  ':(exclude)*/build/*' \
  ':(exclude)node_modules/*' \
  2>/dev/null |
awk -v maxt="$MAXT" -v maxf="$MAXF" '
  /^diff --git / { fchars = 0; fskip = 0 }
  {
    n = length($0) + 1
    if (capped || total + n > maxt) {
      if (!capped) { print "... [diff truncated: total budget reached, judge the rest from the file table above]"; capped = 1 }
      next
    }
    if (fskip) next
    if (fchars + n > maxf) {
      print "... [this file'\''s diff truncated]"
      fskip = 1
      next
    }
    print
    fchars += n
    total += n
  }
'
exit 0
