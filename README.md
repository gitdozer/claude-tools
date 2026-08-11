# claude-tools

Marketplace personale di plugin e skill per Claude Code (più le skill
Claude.ai/Cowork, tenute qui solo come sorgente versionata).

Un solo repo, pensato per crescere: aggiungere un plugin significa aggiungere
una cartella e una voce in `marketplace.json`, non un nuovo repository.

## Installazione

```bash
claude plugin marketplace add gitdozer/claude-tools
claude plugin install commit-desc@claude-tools
```

`add` accetta anche il percorso locale della cartella che contiene
`.claude-plugin/`, comodo per provare una modifica prima di pubblicarla.

## Cosa c'è

| Plugin | Cartella | Cosa fa |
| --- | --- | --- |
| `commit-desc` | [`plugins/commit-desc`](plugins/commit-desc) | Propone un messaggio Conventional Commits per le modifiche in stage. |

## Struttura

```
.
├── .claude-plugin/
│   └── marketplace.json    unico indice: ogni voce di "plugins" è installabile
├── plugins/                 plugin auto-contenuti, ognuno col proprio plugin.json
│   └── commit-desc/
├── skills/                  (vuota) skill semplici senza manifest — pattern alternativo
├── account-skills/          (vuota) skill Claude.ai/Cowork: fuori dal marketplace
├── README.md
├── LICENSE
├── .gitignore
└── .gitattributes
```

## Come sono organizzate le cose

Il **plugin è sempre l'unità di installazione**: un marketplace elenca plugin,
non skill. Una skill raggiunge l'utente sempre *dentro* un plugin. Dalla
documentazione ufficiale, i tre casi possibili:

| Cosa hai | Cos'è |
| --- | --- |
| `<skills-dir>/foo/SKILL.md` senza manifest | una skill semplice, `foo` |
| `<skills-dir>/foo/.claude-plugin/plugin.json` | un plugin `foo@skills-dir` |
| `<plugin>/skills/bar/SKILL.md` | una skill `bar` impacchettata dentro un plugin |

Il manifest di quel plugin può stare in due posti, e da lì i due pattern
possibili — entrambi documentati, entrambi mescolabili nello stesso
`marketplace.json`.

### `plugins/` — la convenzione di questo repo

Ogni plugin è auto-contenuto: `plugin.json` al suo interno, componenti
auto-scoperti dalle cartelle `skills/`, `commands/`, `agents/`, `hooks/` e da
`.mcp.json`. La voce nel marketplace si limita a puntarlo:

```json
{ "name": "commit-desc", "source": "./plugins/commit-desc" }
```

Vantaggi: metadati e versione in un posto solo (dentro il plugin, non duplicati
nel marketplace), pacchetto estraibile in un repository indipendente senza
modifiche, e spazio per crescere — aggiungere un comando o un hook è solo una
cartella in più. È il pattern di
[anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official).
Dettagli nel [README di `plugins/`](plugins/README.md).

### `skills/` — pattern alternativo, oggi non usato

Cartella con solo `SKILL.md`, nessun manifest: è la voce del marketplace a
fare da manifest, con `source: "./"`, `strict: false` e l'elenco esplicito
`skills: [...]`. È il pattern di
[anthropics/skills](https://github.com/anthropics/skills), più leggero ma senza
portabilità né metadati propri. Resta documentato nel
[README di `skills/`](skills/README.md) per il caso in cui serva una skill
davvero minima.

### `account-skills/` — fuori dal marketplace

Skill per Claude.ai/Cowork. Non compaiono in `marketplace.json` e non si
installano con `claude plugin install`: si caricano nell'account come `SKILL.md`
o zip `.skill`. Il repo le tiene solo versionate. Dettagli nel
[README di `account-skills/`](account-skills/README.md).

## Aggiungere un plugin

1. Crea `plugins/nome-plugin/.claude-plugin/plugin.json` con i metadati (name,
   version, description, author) e le cartelle dei componenti che ti servono.
2. Aggiungi la voce in `.claude-plugin/marketplace.json`:
   `{ "name": "nome-plugin", "source": "./plugins/nome-plugin" }`.
3. Aggiungi la riga nella tabella *Cosa c'è*.

## Pubblicare una modifica

Il repository è pubblicato su
[github.com/gitdozer/claude-tools](https://github.com/gitdozer/claude-tools).
Da qui in avanti pubblicare è il normale ciclo git:

```bash
git add .
git commit -m "..."
git push
```

Tre nomi entrano in gioco, e sono indipendenti fra loro. Il repository si chiama
`claude-tools` come la cartella locale, ma chi clona il repo può tenerlo in una
cartella con qualunque nome e git non nota la differenza. Il terzo è il campo
`name` di `marketplace.json`, allineato anch'esso a `claude-tools`: è
l'identificatore che si digita dopo la chiocciola, come in `claude plugin
install commit-desc@claude-tools`. Se un domani rinomini il repository, conviene
aggiornare anche quello.
