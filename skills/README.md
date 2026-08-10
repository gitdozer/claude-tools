# skills/

Cartella per **skill semplici** distribuite senza un manifest proprio: solo
`SKILL.md` più eventuali script o risorse, con la voce del `marketplace.json`
che fa da manifest.

Layout:

```
skills/nome-skill/
├── SKILL.md
└── scripts/        (opzionale)
```

Voce corrispondente in `.claude-plugin/marketplace.json`:

```json
{
  "name": "nome-skill",
  "description": "...",
  "source": "./",
  "strict": false,
  "skills": ["./skills/nome-skill"]
}
```

Tre dettagli che contano, con questo pattern:

`strict: false` è obbligatorio — dichiara che la voce del marketplace è la
definizione completa e che la cartella non ha un `plugin.json`. Con il default
`strict: true` il manifest sarebbe l'autorità, e qui non esiste.

L'array `skills` non va omesso. Con `source: "./"` il comportamento di default
è scansionare tutta la cartella `skills/`, quindi senza l'elenco ogni voce del
marketplace si porterebbe dietro ogni skill del repo.

I metadati (descrizione, versione, autore) vivono nella voce del marketplace,
non in un file della cartella.

## Quando usare questa cartella invece di `plugins/`

Solo per skill davvero minime, dove scrivere un `plugin.json` sarebbe
boilerplate senza contenuto e non interessa la portabilità.

In questo repo la convenzione scelta è l'opposto: **ogni cosa pubblicata sta in
`plugins/` come pacchetto auto-contenuto**, così ha metadati e versione propri
ed è estraibile in un repository indipendente senza modifiche. `commit-desc`
segue quella strada. Questa cartella resta come opzione documentata, per il
caso in cui serva.

Attualmente vuota.
