# skills/

This folder holds **simple skills distributed without a manifest of their own**: just a `SKILL.md`
plus any scripts or resources, with the entry in `marketplace.json` acting as the manifest. This is the pattern used by [anthropics/skills](https://github.com/anthropics/skills).

**Empty for now** — no skill matching this pattern has been written yet.

## Layout

```
skills/<skill-name>/
├── SKILL.md
└── scripts/        (optional)
```

## The matching marketplace entry

In the root [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json):

```json
{
  "name": "<skill-name>",
  "description": "...",
  "source": "./",
  "strict": false,
  "skills": ["./skills/<skill-name>"]
}
```

Three details decide whether this works:

**`strict: false` is what makes the entry the manifest.** With the default (`true`), `plugin.json` is
the authority for the plugin's components — and here no `plugin.json` exists. Setting it to `false`
declares that the marketplace entry is the complete definition. Note the flip side: if a `plugin.json`
*does* exist and declares components, `strict: false` turns that into a conflict and the plugin fails
to load.

**Do not omit the `skills` array.** By default Claude Code scans the `skills/` directory under
`source`, and with `source: "./"` that is this whole folder — so without an explicit list every entry
would drag in every skill in the repository. Listing specific subdirectories makes them the complete
set for that entry, and the rest of the folder stays out. One trap to know: if none of the listed paths
exist (a typo, a renamed folder), Claude Code falls back to the default full scan instead of failing —
so a broken path shows up as "suddenly every skill loaded", not as an error.

**Metadata lives in the marketplace entry.** Description, version and author have nowhere else to go,
since the folder has no manifest. That also means the version has to be maintained in
`marketplace.json` rather than next to the skill.

## Choosing between this folder and `plugins/`

Both patterns are live options here; which one a new skill goes into is a per-skill call.

**Manifest-less, in this folder** — pays off for genuinely minimal skills: a `SKILL.md` with no
scripts gains nothing from a `plugin.json`, which would be boilerplate with no content. The cost is
portability: with the metadata sitting in `marketplace.json` instead of next to the skill, lifting the
folder into a repository of its own means rebuilding the manifest by hand, and the version has to be
bumped in the marketplace index rather than beside the code it describes.

**A plugin, in [`plugins/`](../plugins)** — costs a handful of manifest lines and gives back
self-containment: own metadata and version, extractable into a standalone repository with no edits, and
room to grow into commands, agents or hooks later. That is where `commit-desc` lives, and the right
choice for anything that ships scripts, is expected to grow, or might be published on its own.

Rule of thumb: reach for this folder when the whole skill *is* the `SKILL.md`; reach for `plugins/`
as soon as it is anything more.

## Further reading

- [Create and distribute a marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — entry
  fields, the `skills` field and `strict` mode
- [Skills](https://code.claude.com/docs/en/skills) — writing a `SKILL.md`
