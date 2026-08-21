#!/bin/sh
# Measure, on this repository's real history, how big the diff sent to the model
# by /commit-desc would have been for each past commit.
#
# Answers the only question that matters when tuning the character cap:
# "on MY commits, how often would the cap actually bite?"
#
# Usage:  sh measure_history.sh [number of commits]     (default 100)
#
# Two sizes are reported per commit:
#   RAW   the full diff, no exclusions, 3 lines of context (what a naive tool sends)
#   SENT  what /commit-desc would really send: 2 lines of context, noise files
#         excluded, before the cap is applied
#
# Merge commits are skipped: `git show` prints no diff for them by default, so
# they would show up as 0 and distort the statistics.
#
# For the same reason a commit git fails on is listed and left out of the
# statistics rather than counted as 0: piping git straight into `wc -c` hid its
# exit status, so a failure was indistinguishable from an empty diff and pulled
# the median and the percentiles down -- exactly the numbers the cap is set from.
#
# Environment overrides:
#   COMMIT_DESC_MAX_CHARS   the cap to compare against (default 12000)
#   COMMIT_DESC_CONTEXT     context lines used for SENT (default 2)

N=${1:-100}
CAP=${COMMIT_DESC_MAX_CHARS:-12000}
CTX=${COMMIT_DESC_CONTEXT:-2}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

# The same exclusion list used by SKILL.md, kept as positional parameters so the
# pathspecs survive word splitting untouched.
set -- \
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
  ':(exclude)node_modules/*'

TMP=$(mktemp) || exit 1
OUT=$(mktemp) || exit 1
OK=$(mktemp) || exit 1
trap 'rm -f "$TMP" "$OUT" "$OK"' EXIT INT TERM

# git writes to $OUT and its exit status is checked before measuring, so a
# failure becomes the literal ERR instead of a plausible-looking 0. Measuring the
# file (not a pipe) keeps the count byte-exact, same as the previous `| wc -c`.
git log -n "$N" --no-merges --pretty=%H 2>/dev/null | while read -r sha; do
  if git show --no-color --no-ext-diff --format= -M "$sha" >"$OUT" 2>/dev/null; then
    raw=$(wc -c <"$OUT" | tr -d ' \t')
  else
    raw=ERR
  fi
  if git show --no-color --no-ext-diff --diff-algorithm=minimal "-U$CTX" --format= -M "$sha" -- . "$@" >"$OUT" 2>/dev/null; then
    sent=$(wc -c <"$OUT" | tr -d ' \t')
  else
    sent=ERR
  fi
  subj=$(git log -1 --pretty=%s "$sha" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$raw" "$sent" "$(echo "$sha" | cut -c1-8)" "$subj"
done > "$TMP"

if [ ! -s "$TMP" ]; then
  echo "No non-merge commits found."
  exit 0
fi

# Split measurable commits from failed ones: keeping ERR rows in the sort would
# make them count as 0 again.
awk -F'\t' '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/' "$TMP" > "$OK"
nfail=$(awk -F'\t' '!($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/)' "$TMP" | wc -l | tr -d ' \t')

if [ ! -s "$OK" ]; then
  echo "ERROR: git produced no measurable diff for any of the commits analysed." >&2
  exit 1
fi

sort -t"$(printf '\t')" -k2,2n "$OK" | awk -F'\t' -v cap="$CAP" -v ctx="$CTX" '
function fmt(x) { s = sprintf("%d", x + 0); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } return s out }
{ raw[NR] = $1; sent[NR] = $2; sha[NR] = $3; subj[NR] = $4; rawsum += $1; sentsum += $2; if ($2 > cap) over++ }
END {
  n = NR
  med = sent[int((n + 1) / 2)]
  p90 = sent[int(n * 0.9) < 1 ? 1 : int(n * 0.9)]
  max = sent[n]
  printf "Commits analysed: %d (merges excluded)   cap: %s characters   context: %s lines\n\n", n, fmt(cap), ctx
  printf "Characters sent to the model (after exclusions, before the cap):\n"
  printf "  median         %10s\n", fmt(med)
  printf "  90th percentile%10s\n", fmt(p90)
  printf "  maximum        %10s\n", fmt(max)
  printf "  over the cap: %d of %d (%.0f%%)\n\n", over + 0, n, (over + 0) * 100 / n
  saved = (rawsum > 0) ? (rawsum - sentsum) * 100 / rawsum : 0
  printf "Effect of exclusions and reduced context: from %s to %s total characters (-%.0f%%)\n\n", fmt(rawsum), fmt(sentsum), saved
  printf "The largest commits:\n"
  printf "  %10s  %10s  %8s  %s\n", "sent", "raw", "sha", "subject"
  start = n - 9; if (start < 1) start = 1
  for (i = n; i >= start; i--) {
    flag = sent[i] > cap ? " *" : "  "
    printf "%s%10s  %10s  %8s  %s\n", flag, fmt(sent[i]), fmt(raw[i]), sha[i], substr(subj[i], 1, 60)
  }
  if (over > 0) printf "\n* over the cap: the diff would have been truncated.\n"
}
'

if [ "$nfail" -gt 0 ]; then
  printf '\nWARNING: git produced no measurable diff for %s commits. They are excluded from the statistics above:\n' "$nfail"
  awk -F'\t' '!($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/) { printf "  %s  %s\n", $3, $4 }' "$TMP"
fi
