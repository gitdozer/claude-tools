# plugins/

Plugin **auto-contenuti**: ognuno ha il proprio `.claude-plugin/plugin.json` e
può raggruppare più componenti — skill, comandi slash, agenti, hook, server MCP.

È il pattern usato da
[anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official),
e la convenzione scelta per questo repo: tutto ciò che viene pubblicato sta qui.

## Contenuto

| Plugin | Cosa fa |
| --- | --- |
| [`commit-desc`](commit-desc) | Propone un messaggio Conventional Commits per le modifiche in stage. |

## Layout di un plugin

```
plugins/nome-plugin/
├── .claude-plugin/
│   └── plugin.json     manifest: name, version, description, author. Solo metadati.
├── skills/             skill del plugin (opzionale)
│   └── nome-skill/SKILL.md
├── commands/           comandi slash (opzionale)
├── agents/             agenti (opzionale)
├── hooks/              hook (opzionale)
├── .mcp.json           server MCP (opzionale)
└── README.md
```

**I componenti si auto-scoprono per convenzione**: non vanno elencati in
`plugin.json`. Il manifest del plugin ufficiale `agent-sdk-dev` di Anthropic è
letteralmente solo questo:

```json
{
  "name": "agent-sdk-dev",
  "description": "Claude Agent SDK Development Plugin",
  "author": { "name": "Anthropic", "email": "support@anthropic.com" }
}
```

Un `plugin.json` che dichiari componenti già trovati per convenzione non serve, e
in combinazione con `strict: false` nel marketplace diventa perfino un conflitto
che impedisce il caricamento.

## Registrare il plugin nel marketplace

Nel `.claude-plugin/marketplace.json` di radice basta puntare la cartella:

```json
{ "name": "nome-plugin", "source": "./plugins/nome-plugin" }
```

Senza `strict`: il default `strict: true` significa "il `plugin.json` è
l'autorità", che è esattamente quello che si vuole qui. Descrizione, versione,
autore e licenza vivono così in un posto solo, dentro il plugin, invece di
essere duplicati nel marketplace. Nella voce restano solo i campi che esistono
unicamente a livello di marketplace, come `category`.

## Perché questo pattern e non `skills/`

Il plugin è l'unità di installazione in entrambi i casi, e chi installa non nota
differenze. Cambia dove vive il manifest, e con esso due cose concrete:

**Portabilità.** Un plugin con il manifest dentro si estrae in un repository
indipendente senza modifiche (`git subtree split` e basta).

**Spazio per crescere.** Aggiungere un comando, un hook o un server MCP è solo
una cartella in più: nessuna migrazione, nessun cambio di layout.

Il costo è un file di metadati per plugin. Vedi il README di
[`skills/`](../skills) per il pattern alternativo, più leggero ma senza queste
due proprietà.
