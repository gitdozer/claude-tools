# account-skills/

Skill per Claude.ai / Cowork (non per la CLI di Claude Code). Es. skill di
scrittura, generazione documenti, o qualunque skill pensata per essere usata
qui in chat o in Cowork piuttosto che da terminale.

Differenza importante rispetto a `skills/` e `plugins/`: queste skill **non
compaiono in `marketplace.json`** e non si installano con `claude plugin
install`. Non esiste un meccanismo git per installarle nell'account: si
distribuiscono caricando il file `SKILL.md` (o uno zip `.skill` con le
risorse) nell'interfaccia di caricamento skill di Claude.ai/Cowork.

Il repo qui serve solo da sorgente versionata. Flusso di lavoro:

1. Scrivi/modifica `SKILL.md` (+ eventuali `scripts/`, `references/`,
   `resources/`) dentro `account-skills/nome-skill/`.
2. Quando vuoi aggiornarla nel tuo account, impacchetta la cartella in uno
   zip `.skill` (o carica direttamente il `SKILL.md` se non ha risorse
   aggiuntive) tramite l'interfaccia di caricamento skill.
3. Nessun passaggio automatico: il repo non "pubblica" da solo verso
   l'account, è solo storia e backup.

Nota anche sul frontmatter: qui non hanno senso i campi specifici di Claude
Code come `model`, `effort`, `context: fork`, `allowed-tools` o i comandi
iniettati `` !`...` `` — questi valgono solo per le skill di `skills/` e
`plugins/`. Una skill di questa cartella usa solo `name` e `description` nel
frontmatter, e il modello decide da solo quando attivarla in base alla
`description`.

Ancora nessuna skill qui: è una cartella segnaposto per la prima skill
Claude.ai/Cowork che vorrai versionare.
