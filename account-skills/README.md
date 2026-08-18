# account-skills/

Skills for **claude.ai and Cowork** — not for the Claude Code CLI. Writing skills, document
generation, or anything meant to be used in a chat rather than from a terminal.

**The folder is currently empty.** 

## How these differ from `skills/` and `plugins/`

These skills **do not appear in `marketplace.json`** and cannot be installed with
`claude plugin install`. There is no git-based mechanism to get a skill into a Claude account: you
upload it manually. This folder is therefore only a versioned source (history and backup), not a distribution
channel.

Custom skills also **do not sync between surfaces**. A skill uploaded to claude.ai is not available
through the Claude API, and neither is aware of the filesystem skills used by Claude Code. Each surface
is uploaded and managed separately, even when the `SKILL.md` is identical.

## Workflow

1. Write or edit `SKILL.md` — plus any `scripts/`, `references/`, `resources/` — inside
   `account-skills/<skill-name>/`.
2. To update it in your account, zip the skill folder and upload the archive from **Settings >
   Features** on claude.ai. Custom skills require a Pro, Max, Team or Enterprise plan with code
   execution enabled, and each user uploads their own: they are not shared organization-wide and
   cannot be managed centrally by admins.
3. There is no automatic step. Pushing to this repository does not publish anything to the account.

## Frontmatter: only `name` and `description`

A claude.ai skill uses the two fields of the Agent Skills standard, and the model decides on its own
when to activate it by matching your request against the `description`:

```yaml
---
name: my-skill
description: What the skill does, and when Claude should use it.
---
```

Both are required, with constraints worth knowing before a failed upload:

| Field | Constraints |
| --- | --- |
| `name` | Max 64 characters; lowercase letters, numbers and hyphens only; cannot contain the reserved words `anthropic` or `claude` |
| `description` | Non-empty, max 1024 characters. Must say **what** the skill does *and* **when** to use it — this is the only text Claude matches a request against |

The Claude Code-specific frontmatter has no meaning here: `model`, `effort`, `context: fork`,
`argument-hint` and injected `` !`...` `` commands are features of the CLI's skill loader, and apply
only to skills under [`skills/`](../skills) and [`plugins/`](../plugins).

## Further reading

- [Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) —
  structure, progressive disclosure, per-surface behaviour and limits
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [How to create custom skills](https://support.claude.com/en/articles/12512198-creating-custom-skills)
  — the claude.ai upload flow
