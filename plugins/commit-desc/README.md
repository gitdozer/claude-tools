# commit-desc

Plugin per Claude Code: prima di ogni commit, genera una descrizione sintetica
delle modifiche in stage nel formato **Conventional Commits** (in inglese).

```
> /commit-desc

The message:

    feat(etl): add encoding parameter and safe loader

Ready to run:

    git commit -m "feat(etl): add encoding parameter and safe loader"
```

## Come è fatto (e perché così)

Il vincolo del progetto è: risposta in pochi secondi e consumo di token minimo.
Da qui tre scelte, tutte verificate con misurazioni:

1. **`model: haiku` + `effort: low`.** Classificare un diff e scrivere una riga
   non richiede un modello grande. Haiku con effort basso è il punto di
   equilibrio migliore fra qualità e latenza.
2. **`context: fork`.** Senza questo, lo slash command girerebbe *dentro* la
   conversazione in corso: in una sessione lunga il costo dell'input sarebbe
   quello di tutta la cronologia, non quello del diff. Con il fork la skill
   parte in una finestra di contesto pulita e paga solo il diff. Nei test il
   costo per invocazione è risultato circa 0,005–0,010 $ e stabile, contro
   0,013–0,044 $ e molto variabile senza fork.
3. **Il diff viene compresso prima di arrivare al modello.** Non serve l'intero
   diff per capire *cosa* fa un commit:
   - `--numstat` invece di `--stat`: l'istogramma ASCII di `--stat` costa molti
     token e non aggiunge informazione;
   - `-U2`: due righe di contesto invece di tre;
   - lock file, output di build, notebook, dataset e immagini restano
     nell'elenco dei file ma il loro contenuto non viene diffato;
   - `head -c 12000`: tetto massimo, così un commit enorme resta veloce.

   Su un commit realistico il contesto inviato è di circa 300–400 token; il
   tetto massimo è di circa 3.500 token.

Latenza misurata: 6–9 secondi in modalità headless, avvio della CLI incluso
(~2–3 s). In una sessione interattiva già avviata resta solo il round-trip del
modello.

## Struttura

```
plugins/commit-desc/
├── .claude-plugin/
│   └── plugin.json                    manifest del plugin
├── skills/
│   └── commit-desc/
│       ├── SKILL.md                   la skill: raccolta del diff + istruzioni al modello
│       └── scripts/
│           ├── collect_diff.sh        motore portabile per altri strumenti e git hook
│           ├── measure_history.sh     misura quanto verrebbe inviato al modello, sui commit passati
│           └── measure_history.ps1    la stessa misura in PowerShell, senza dipendere da Git Bash
└── README.md
```

Il plugin è **auto-contenuto**: il manifest sta al suo interno e i componenti si
auto-scoprono per convenzione (`skills/`, e se un giorno servissero anche
`commands/`, `agents/`, `hooks/`, `.mcp.json`). Nessuno di questi va dichiarato
in `plugin.json`, ed è il motivo per cui il manifest contiene solo metadati.

Conseguenza pratica: questa cartella si può estrarre in un repository
indipendente senza modificare nulla.

## Installazione

### Opzione A — marketplace (consigliata)

Dalla radice del repo che contiene `.claude-plugin/marketplace.json`:

```bash
claude plugin marketplace add "C:/percorso/di/plugin-commit-description"
claude plugin install commit-desc@claude-tools
```

Dopo la pubblicazione su GitHub basta cambiare l'`add`:

```bash
claude plugin marketplace add <owner>/<repo>
claude plugin install commit-desc@claude-tools
```

Stessa installazione, da qualunque macchina.

### Opzione B — copia nella cartella skills

Qualunque cartella dentro `~/.claude/skills/` che contenga un
`.claude-plugin/plugin.json` viene caricata come plugin `nome@skills-dir`, senza
marketplace e senza installazione. Basta quindi copiare **questa** cartella:

```powershell
Copy-Item -Recurse "<questa cartella>" "$env:USERPROFILE\.claude\skills\commit-desc"
```

Si carica alla sessione successiva come `commit-desc@skills-dir`, oppure subito
con `/reload-plugins`. Verifica con `claude plugin list`.

## Uso

Metti in stage ciò che vuoi committare, poi:

```
git add -p          # o git add .
/commit-desc
/commit-desc riferito alla issue #142     # contesto opzionale
```

Il plugin non committa: propone il messaggio e la riga `git commit` pronta da
incollare. Il testo resta sempre modificabile.

## Personalizzazione

Tutto si regola in `skills/commit-desc/SKILL.md`:

| Cosa cambiare | Dove |
| --- | --- |
| Lingua del messaggio | sostituisci "in English" nella sezione *What to produce* |
| Formato (es. subject + bullet) | sezione *Output format* |
| Tipi ammessi, lunghezza massima | sezione *What to produce* |
| File esclusi dal diff | i `':(exclude)...'` nel comando `git diff` |
| Tetto di token | il valore di `head -c` |
| Numero di commit recenti usati come riferimento di stile | `git log -5` |

La versione va aggiornata in `.claude-plugin/plugin.json`, non nel
`marketplace.json` di radice: con `strict` al valore di default il manifest del
plugin è l'autorità sui metadati.

## Due vincoli tecnici scoperti sul campo

Utili se in futuro modifichi i comandi iniettati nella skill (`` !`...` ``):

- **Il comando iniettato deve corrispondere a `allowed-tools`.** Se non
  corrisponde viene bloccato dal sistema dei permessi e la skill **fallisce in
  silenzio**: nessun output, nessun errore visibile. Le voci attuali sono
  `Bash(git *), Bash(head *), Bash(wc *)`.
- **Niente variabili di shell nel comando iniettato.** Un comando che contiene
  `$VAR` (compreso `$CLAUDE_PLUGIN_ROOT`) viene rifiutato dallo stesso
  meccanismo. È il motivo per cui i comandi `git` sono scritti direttamente in
  `SKILL.md` invece di richiamare uno script tramite percorso.

## Analizzare lo storico dei commit e calibrare il tetto di caratteri

Lo stesso script serve anche solo per vedere, sulla repository che stai
analizzando, che tipo di commit fai e quanto sono grandi i loro diff — non
serve necessariamente voler cambiare il tetto (`head -c 12000`) per usarlo.
Lo script va lanciato **dalla cartella del repository da misurare**, indicando
il percorso completo dello script (che vive qui, non nel repository misurato).

Dalla cartella sorgente del plugin, da PowerShell:

```powershell
cd C:\percorso\del\repo
& "C:\percorso\di\plugin-commit-description\plugins\commit-desc\skills\commit-desc\scripts\measure_history.ps1" -Count 200
```

Da Git Bash o da qualsiasi shell POSIX:

```bash
cd /percorso/del/repo
sh "/c/percorso/di/plugin-commit-description/plugins/commit-desc/skills/commit-desc/scripts/measure_history.sh" 200
```

Se hai installato con l'Opzione B (copia in `~/.claude/skills/commit-desc`), il
percorso diventa:

```powershell
cd C:\percorso\del\repo
& "$env:USERPROFILE\.claude\skills\commit-desc\skills\commit-desc\scripts\measure_history.ps1" -Count 200
```

```bash
cd /percorso/del/repo
sh "$HOME/.claude/skills/commit-desc/skills/commit-desc/scripts/measure_history.sh" 200
```

(il doppio `commit-desc` non è un errore: il primo è la cartella del plugin, il
secondo quella della skill al suo interno)

Le due versioni (PowerShell e POSIX) sono equivalenti e danno gli stessi
numeri: mediana, 90° percentile, massimo, quanti commit avrebbero superato il
tetto e quali. Confrontano anche il diff grezzo con quello effettivamente
inviato, per quantificare quanto stanno rendendo le esclusioni.

Per provare un tetto diverso senza toccare `SKILL.md`:

```powershell
& "...\measure_history.ps1" -Count 200 -Cap 24000
```

```bash
COMMIT_DESC_MAX_CHARS=24000 sh ".../measure_history.sh" 200
```

Se PowerShell risponde `Impossibile caricare il file ... perché l'esecuzione di
script è disattivata`, sbloccalo per la sola sessione corrente:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Regola pratica: se la mediana è molto sotto il tetto e i pochi commit che lo
superano sono modifiche massive e meccaniche (rinomine, changelog, file
rigenerati), il tetto va bene così — su quei commit un messaggio generico è
comunque corretto.

## Portabilità verso altri strumenti

`skills/commit-desc/scripts/collect_diff.sh` è il motore riutilizzabile:
raccoglie e comprime le modifiche in stage (stessa logica della skill, più un
tetto per singolo file e la gestione del caso "niente in stage") e non dipende
da Claude Code. È scritto in POSIX sh + awk, quindi funziona anche in Git Bash
su Windows.

Uso da terminale, con qualsiasi strumento capace di leggere stdin:

```bash
sh skills/commit-desc/scripts/collect_diff.sh | claude -p --model haiku \
  'Reply with ONE Conventional Commits subject line for the staged changes below. Output only that line.'
```

Questa strada paga però l'avvio a freddo della CLI (~13 s misurati), quindi
serve come base per un **git hook `prepare-commit-msg`** o per l'integrazione
con Codex e strumenti simili, non come sostituto della skill in sessione.

Parametri via variabili d'ambiente: `COMMIT_DESC_MAX_CHARS` (default 12000),
`COMMIT_DESC_MAX_FILE_CHARS` (2000), `COMMIT_DESC_CONTEXT` (2),
`COMMIT_DESC_LOG_COUNT` (5).
