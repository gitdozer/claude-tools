# plugins/

**Self-contained plugins**: each one carries its own `.claude-plugin/plugin.json` and can bundle
several components — skills, slash commands, agents, hooks, MCP servers.

This is the pattern used by
[anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official), and the
default pattern for this repository: anything that ships scripts, bundles several components or
might be published on its own goes here.

## Contents

| Plugin | What it does |
| --- | --- |
| [`commit-desc`](commit-desc) | Proposes a Conventional Commits message for the staged changes. |

## Layout of a plugin

```
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json     manifest: name, version, description, author. Metadata only.
├── skills/             the plugin's skills (optional)
│   └── <skill-name>/SKILL.md
├── commands/           slash commands (optional)
├── agents/             subagents (optional)
├── hooks/              hooks (optional)
├── .mcp.json           MCP servers (optional)
└── README.md
```

**Components are auto-discovered by convention, so never list them in `plugin.json`.** Claude Code
finds them by looking at those directory names. A manifest can therefore be as short as this and still
ship a working plugin:

```json
{
  "name": "my-plugin",
  "description": "What the plugin does",
  "author": { "name": "Your Name" }
}
```

Declaring components that convention already finds is not just redundant: combined with
`strict: false` in the marketplace entry it becomes a conflict, and the plugin fails to load.

One more rule worth knowing: only `plugin.json` goes inside `.claude-plugin/`. `skills/`, `commands/`,
`agents/` and `hooks/` must sit at the plugin root, next to it — not inside it.

## Registering the plugin in the marketplace

In the root [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json), the entry only
needs to point at the folder:

```json
{ "name": "<plugin-name>", "source": "./plugins/<plugin-name>" }
```

Leave `strict` alone. Its default (`true`) means "`plugin.json` is the authority for this plugin's
components", which is exactly what you want here: description, version, author and license live in one
place, inside the plugin, instead of being duplicated in the marketplace. The entry keeps only fields
that exist at marketplace level, such as `category`.

## Why this pattern rather than `skills/`

The plugin is the unit of installation either way, and whoever installs it sees no difference. What
changes is where the manifest lives, and with it two concrete properties:

**Portability.** A plugin that carries its own manifest can be extracted into a standalone repository
with no edits — a `git subtree split` and nothing else.

**Room to grow.** Adding a command, a hook or an MCP server is just one more directory: no migration,
no change of layout.

The price is one metadata file per plugin. See the [`skills/`](../skills) README for the alternative
pattern, which is lighter but has neither property.

## Further reading

- [Create plugins](https://code.claude.com/docs/en/plugins) — components, layout, local testing
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — manifest schema, version
  management
- [Create and distribute a marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — entry
  fields and `strict` mode
