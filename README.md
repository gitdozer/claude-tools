# claude-tools

A small **plugin marketplace for [Claude Code](https://code.claude.com/docs/en/overview)** — a single
repository that Claude Code reads directly, so installing anything from it takes two commands.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-d97757.svg)](https://code.claude.com/docs/en/plugin-marketplaces)

The repository is built to grow: publishing a new plugin means adding a folder and one entry in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json), not creating a new repository.

## Requirements

- [Claude Code](https://code.claude.com/docs/en/quickstart) installed and authenticated (`claude --version`)
- `git`

## Installation

```bash
# 1. Register this marketplace (once per machine)
claude plugin marketplace add gitdozer/claude-tools

# 2. Install any plugin listed below
claude plugin install <plugin-name>@claude-tools

# Example
claude plugin install commit-desc@claude-tools
```

Check the result with `claude plugin list`. If the install output asks you to run `/reload-plugins`,
run it inside your Claude Code session — otherwise the new plugin becomes available on the next
session.

`commit-desc@claude-tools` reads as `plugin@marketplace`: `claude-tools` is the marketplace
identifier (the `name` field of `marketplace.json`), and it disambiguates plugins that share a name
across marketplaces. Plain `claude plugin install commit-desc` works too, as long as no other
registered marketplace offers a plugin by that name.

### Managing the installation

```bash
claude plugin update commit-desc              # pull the latest published version
claude plugin uninstall commit-desc           # remove the plugin, keep the marketplace
claude plugin marketplace update claude-tools # refresh the index from GitHub
claude plugin marketplace remove claude-tools # unregister the marketplace entirely
```

### A note on trust

A Claude Code plugin can add skills, slash commands, subagents, hooks and MCP servers to your
session, so treat installing one like installing any other executable code: only add marketplaces you
trust. Everything in this repository is plain text you can read before installing.

`commit-desc` runs read-only `git` commands (`git diff --cached`, `git log`, `git rev-parse`) and never creates a
commit itself.

## New to Claude Code plugins?

Three terms are worth separating, because they are easy to confuse:

| Term | What it is |
| --- | --- |
| **Skill** | A folder with a `SKILL.md` file: instructions Claude loads on demand, either because you invoke it (for instance by typing `/commit-desc`) or because the task matches its description. |
| **Plugin** | The unit of installation. A plugin has a manifest (`.claude-plugin/plugin.json`) and can bundle skills, slash commands, subagents, hooks and MCP servers. |
| **Marketplace** | An index (`.claude-plugin/marketplace.json`) listing plugins. You register the index once, then install plugins from it. This repository is one. |

The practical consequence: **a marketplace lists plugins, never bare skills.** A skill always reaches
you inside a plugin. Official documentation: [plugins](https://code.claude.com/docs/en/plugins),
[marketplaces](https://code.claude.com/docs/en/plugin-marketplaces),
[skills](https://code.claude.com/docs/en/skills).

## Available plugins

| Plugin | What it does |
| --- | --- |
| [`commit-desc`](plugins/commit-desc) | Proposes a [Conventional Commits](https://www.conventionalcommits.org/) message for your staged changes, then hands you the ready-to-run `git commit` line. |

### commit-desc

Stage what you want to commit, then ask for a message:

```
git add -p                     # or git add .
/commit-desc                   # optionally: /commit-desc relates to issue #142
```

```
The message:

    feat(etl): add encoding parameter and safe loader

Ready to run:

    git commit -m "feat(etl): add encoding parameter and safe loader"
```

The plugin proposes, you decide: it never commits, and the text stays editable.

It is designed around two constraints, an answer in a few seconds, and minimal token cost:

- **Runs on Haiku with low reasoning effort.** Classifying a diff and writing one subject line does
  not need a large model.
- **Runs in a forked context**, so it pays for the diff only, not for the whole conversation it was
  invoked from. In a long session that is the difference between a stable and reasonable cost and an unpredictable
  one.
- **Compresses the diff before the model sees it**: `--numstat` instead of `--stat`, two lines of
  context instead of three, lock files / build output / notebooks / datasets / images listed but not
  diffed, and a hard 20,000-character cap so an enormous commit stays fast (but keep in mind that you're losing context if you exceed the 20,000 chars).

On a median commit that adds up to roughly 450–650 tokens of context per invocation.
[plugins/commit-desc/README.md](plugins/commit-desc/README.md) documents the measurements, how to
customize the message language and format, and the two bundled scripts — one reusable diff collector
for git hooks and other tools, and one that measures, over your own commit history, exactly how much
the skill would send.

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json   the only index: every entry in "plugins" is installable
├── plugins/               self-contained plugins, each with its own plugin.json
│   └── commit-desc/
├── skills/                (empty) reserved for manifest-less skills
├── account-skills/        (empty) Claude.ai / Cowork skills: outside the marketplace
├── LICENSE
├── .gitignore
└── .gitattributes
```

Only what `marketplace.json` lists is reachable by `claude plugin install`; anything else in the
repository is invisible to the CLI.

## License

[MIT](LICENSE) © Dennis Maffei
