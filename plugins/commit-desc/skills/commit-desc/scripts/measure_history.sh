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
  ':(exclude)*.min.js' \
  ':(exclude)*.min.css' \
  ':(exclude)*.map' \
  ':(exclude)*.snap' \
  ':(exclude)*.ipynb' \
  ':(exclude)*.csv' \
  ':(exclude)*.tsv' \
  ':(exclude)*.parquet' \
  ':(exclude)*.xlsx' \
  ':(exclude)*.pdf' \
  ':(exclude)*.png' \
  ':(exclude)*.jpg' \
  ':(exclude)*.gif' \
  ':(exclude)*.pkl' \
  ':(exclude)*.h5' \
  ':(exclude)*.zip' \
  ':(exclude)dist/*' \
  ':(exclude)*/dist/*' \
  ':(exclude)build/*' \
  ':(exclude)node_modules/*'

TMP=$(mktemp) || exit 1
trap 'rm -f "$TMP"' EXIT INT TERM

git log -n "$N" --no-merges --pretty=%H 2>/dev/null | while read -r sha; do
  raw=$(git show --no-color --no-ext-diff --format= -M "$sha" 2>/dev/null | wc -c)
  sent=$(git show --no-color --no-ext-diff --diff-algorithm=minimal "-U$CTX" --format= -M "$sha" -- . "$@" 2>/dev/null | wc -c)
  subj=$(git log -1 --pretty=%s "$sha" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$raw" "$sent" "$(echo "$sha" | cut -c1-8)" "$subj"
done > "$TMP"

if [ ! -s "$TMP" ]; then
  echo "No non-merge commits found."
  exit 0
fi

sort -t"$(printf '\t')" -k2,2n "$TMP" | awk -F'\t' -v cap="$CAP" -v ctx="$CTX" '
function fmt(x) { s = sprintf("%d", x + 0); out = ""; while (length(s) > 3) { out = "." substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } return s out }
{ raw[NR] = $1; sent[NR] = $2; sha[NR] = $3; subj[NR] = $4; rawsum += $1; sentsum += $2; if ($2 > cap) over++ }
END {
  n = NR
  med = sent[int((n + 1) / 2)]
  p90 = sent[int(n * 0.9) < 1 ? 1 : int(n * 0.9)]
  max = sent[n]
  printf "Commit analizzati: %d (merge esclusi)   tetto: %s caratteri   contesto: %s righe\n\n", n, fmt(cap), ctx
  printf "Caratteri inviati al modello (dopo le esclusioni, prima del tetto):\n"
  printf "  mediana      %10s\n", fmt(med)
  printf "  90 percentile%10s\n", fmt(p90)
  printf "  massimo      %10s\n", fmt(max)
  printf "  oltre il tetto: %d su %d (%.0f%%)\n\n", over + 0, n, (over + 0) * 100 / n
  saved = (rawsum > 0) ? (rawsum - sentsum) * 100 / rawsum : 0
  printf "Effetto di esclusioni e contesto ridotto: da %s a %s caratteri totali (-%.0f%%)\n\n", fmt(rawsum), fmt(sentsum), saved
  printf "I commit piu grandi:\n"
  printf "  %10s  %10s  %8s  %s\n", "inviati", "grezzi", "sha", "oggetto"
  start = n - 9; if (start < 1) start = 1
  for (i = n; i >= start; i--) {
    flag = sent[i] > cap ? " *" : "  "
    printf "%s%10s  %10s  %8s  %s\n", flag, fmt(sent[i]), fmt(raw[i]), sha[i], substr(subj[i], 1, 60)
  }
  if (over > 0) printf "\n* superano il tetto: il diff sarebbe stato troncato.\n"
}
'
