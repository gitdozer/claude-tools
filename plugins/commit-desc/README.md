# commit-desc

A Claude Code plugin: before you commit, it reads your staged changes and proposes a one-line
description in the [Conventional Commits](https://www.conventionalcommits.org/) format.

```
> /commit-desc

The message:

    feat(etl): add encoding parameter and safe loader

Ready to run:

    git commit -m "feat(etl): add encoding parameter and safe loader"
```

It proposes, you decide. The plugin never commits, and the text stays editable.

## Installation

### Option A — from the marketplace (recommended)

```bash
claude plugin marketplace add gitdozer/claude-tools
claude plugin install commit-desc@claude-tools
```

Same two commands on any machine. During development you can point `add` at a local working copy
instead — any directory containing `.claude-plugin/marketplace.json`:

```bash
claude plugin marketplace add "C:/path/to/claude-tools"
claude plugin install commit-desc@claude-tools
```

### Option B — copy it into your skills directory

Any directory under `~/.claude/skills/` that contains a `.claude-plugin/plugin.json` loads as
`<name>@skills-dir`, with no marketplace and no install step. Copying **this** folder is enough:

```powershell
Copy-Item -Recurse "<this folder>" "$env:USERPROFILE\.claude\skills\commit-desc"
```

It loads on the next session as `commit-desc@skills-dir`, or immediately with `/reload-plugins`. Check
with `claude plugin list`.

## Usage

Stage what you want to commit, then ask:

```
git add -p                                  # or git add .
/commit-desc
/commit-desc relates to issue #142          # optional extra context
```

The optional argument is free text: an issue number, the intent behind the change, anything that the
diff alone does not show.

## How it works, and why

The design constraints are an answer in a few seconds and minimal token cost. Three decisions follow
from them, each verified by measurement rather than assumed:

1. **`model: haiku` with `effort: low`.** Classifying a diff and writing one line does not need a large
   model. Haiku at low effort is the best balance of quality and latency for this job.

2. **`context: fork`.** Without it, the skill would run *inside* your current conversation, so in a long
   session the input cost would be the whole history rather than just the diff. Forking starts it in a
   clean context window, where it pays for the diff only. Measured cost per invocation: roughly
   **$0.005–0.010 and stable**, against **$0.013–0.044 and highly variable** without the fork.

3. **The diff is compressed before the model sees it.** You do not need a complete diff to understand
   *what* a commit does:
   - `--numstat` instead of `--stat` — the ASCII histogram costs many tokens and adds no information;
   - `-U2` — two lines of context instead of three;
   - lock files, build output, notebooks, datasets and images stay in the file list, but their content
     is not diffed;
   - `head -c 20000` — a hard ceiling, so an enormous commit stays fast.

   The diff sent on a median commit is about **450–650 tokens** (measured across two repositories:
   ~1,800 and ~2,500 characters); the ceiling is about **5,000 tokens**. Because `head -c` is a
   ceiling and not a floor, raising it costs nothing on a typical commit — only the commits that
   would otherwise be truncated send more.

Measured latency: **6–9 seconds** in headless mode, CLI startup included (~2–3 s of that). Inside an
already-running interactive session, only the model round-trip remains.

When the diff does exceed the cap, the model is instructed to say so in its answer before the message,
so a proposal based on partial information never looks complete.

## Customization

Everything is tuned in [`skills/commit-desc/SKILL.md`](skills/commit-desc/SKILL.md):

| What to change | Where |
| --- | --- |
| Language of the message | replace "in English" in the *What to produce* section, and the truncation warning in *Output format* — that one is a separate literal string |
| Format (e.g. subject + bullets) | the *Output format* section |
| Allowed types, maximum length | the *What to produce* section |
| Files excluded from the diff | the `':(exclude)...'` pathspecs in the `git diff` command |
| Character cap | the `head -c` value |
| How many recent commits are used as a style reference | `git log -5` |

Bump `version` in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json), not in the root
`marketplace.json`: with `strict` at its default the plugin manifest is the authority for metadata, and
Claude Code uses that `version` to decide whether an update is available.

Note that the character cap appears in more than one place inside `SKILL.md` — the prose, the
`head -c`, and the truncation check — plus as the `COMMIT_DESC_MAX_CHARS` default in the scripts. Change
one, change all.

## Structure

```
plugins/commit-desc/
├── .claude-plugin/
│   └── plugin.json                    the plugin manifest
├── skills/
│   └── commit-desc/
│       └── SKILL.md                   the skill — the whole execution path lives here
├── scripts/                           companion tooling, NOT on the execution path
│   ├── collect_diff.sh                portable engine for other tools and git hooks
│   ├── measure_history.sh             measures what would be sent to the model, over past commits
│   └── measure_history.ps1            the same measurement in PowerShell, without needing Git Bash
└── README.md
```

`SKILL.md` is the entire plugin at run time: it inlines its own `git` commands and calls nothing in
`scripts/`. That directory holds tools you run yourself — a git hook, another CLI, a calibration pass —
and it sits at the plugin root because that is where the
[plugin reference](https://code.claude.com/docs/en/plugins-reference) puts bundled helper scripts.
Keeping it inside `skills/` implied the skill executed it, which it never did.

The plugin is **self-contained**: the manifest lives inside it, and components are auto-discovered by
convention (`skills/`, and if ever needed `commands/`, `agents/`, `hooks/`, `.mcp.json`). None of them
belongs in `plugin.json`, which is why the manifest holds metadata only. `scripts/` is not a component
directory, so Claude Code ships it without interpreting it.

The practical consequence: this folder can be extracted into a standalone repository without changing
anything.

## Inspecting your own history and calibrating the cap

The measurement scripts answer the only question that matters when tuning the cap: *on my commits, how
often would it actually bite?* They are also useful just to see what your commits look like — you do
not have to want to change `head -c 20000` to run them.

Run them **from the repository you want to measure**, giving the full path to the script (which lives
here, not in the repository being measured):

```powershell
cd C:\path\to\the\repo
& "C:\path\to\claude-tools\plugins\commit-desc\scripts\measure_history.ps1" -Count 200
```

```bash
cd /path/to/the/repo
sh "/c/path/to/claude-tools/plugins/commit-desc/scripts/measure_history.sh" 200
```

If you installed with Option B, the path becomes:

```powershell
& "$env:USERPROFILE\.claude\skills\commit-desc\scripts\measure_history.ps1" -Count 200
```

```bash
sh "$HOME/.claude/skills/commit-desc/scripts/measure_history.sh" 200
```

Both versions report the same numbers in the same layout: median, 90th percentile, maximum, how many
commits would have exceeded the cap and which ones. They also compare the raw diff against what is
actually sent, which quantifies how much the exclusions are earning you.

The unit is the byte, the same as `head -c` in the skill. Two details keep the two implementations from
drifting apart: the PowerShell version counts git's raw stdout rather than decoded strings — otherwise
accented characters and CRLF would make it diverge from `wc -c` — and it formats numbers with the
invariant culture, since PowerShell's `N0` follows the machine's locale and would print `20.000` where
the POSIX version prints `20,000`.

If git fails on a commit — an unreadable object, say — that commit is listed separately and left out of
the statistics instead of counting as zero. A silent zero would drag the median and the percentiles
down, producing plausible but wrong numbers, which are exactly the numbers the cap is chosen from.

To try a different cap without touching `SKILL.md`:

```powershell
& "...\measure_history.ps1" -Count 200 -Cap 24000
```

```bash
COMMIT_DESC_MAX_CHARS=24000 sh ".../measure_history.sh" 200
```

Defaults: `-Count`/`[number of commits]` is 100, `-Cap`/`COMMIT_DESC_MAX_CHARS` is 20000, context lines
are 2. Merge commits are skipped, since `git show` prints no diff for them by default and they would
show up as zero.

If PowerShell refuses to run the script because running scripts is disabled on this system, unblock it
for the current session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Rule of thumb for reading the output: if the median is well below the cap and the few commits that
exceed it are massive mechanical changes (renames, changelogs, regenerated files), the cap is fine as
it is — a generic message is the right answer for those commits anyway.

The number to set the cap from is the **90th percentile**, not the maximum: put the cap just above it
and truncation is pushed back into the tail, where it belongs. That is how the current 20,000 was
chosen — on a 200-commit application repository the 90th percentile came out at 17,082, with the cap
at 12,000 truncating 28 commits out of 200 (14%) and at 20,000 truncating 18 (9%). Chasing the
maximum instead is not worth it: the commits above 20,000 there were 50–95 KB planning documents,
where a truncated diff and a generic message are the correct outcome.

## Reusing the diff collector in other tools

[`scripts/collect_diff.sh`](scripts/collect_diff.sh) is the
reusable engine: it collects and compresses the staged changes with the same logic as the skill, plus a
per-file ceiling and handling for the "nothing staged" case, and it does not depend on Claude Code. It
is POSIX `sh` + `awk`, so it also runs under Git Bash on Windows.

From a terminal, with any tool that can read stdin:

```bash
sh scripts/collect_diff.sh | claude -p --model haiku \
  'Reply with ONE Conventional Commits subject line for the staged changes below. Output only that line.'
```

This route pays the CLI cold start (~13 s measured), so treat it as the basis for a
`prepare-commit-msg` **git hook**, or for integrating with Codex and similar tools — not as a
replacement for the skill inside a session.

Parameters come from environment variables: `COMMIT_DESC_MAX_CHARS` (default 20000),
`COMMIT_DESC_MAX_FILE_CHARS` (2000), `COMMIT_DESC_CONTEXT` (2), `COMMIT_DESC_LOG_COUNT` (5).

## Two constraints discovered on the field

Useful if you ever change the commands injected into the skill with `` !`...` ``:

- **The injected command must match `allowed-tools`.** If it does not, the permission system blocks it
  and the skill **fails silently**: no output, no visible error. The current entries are
  `Bash(git *), Bash(head *), Bash(wc *)`.
- **No shell variables in an injected command.** A command containing `$VAR` — including
  `$CLAUDE_PLUGIN_ROOT` — is rejected by the same mechanism. That is why the `git` commands are written
  out in `SKILL.md` instead of calling a script by path.

## License

[MIT](../../LICENSE) © Dennis Maffei
