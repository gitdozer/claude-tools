#Requires -Version 5.1
<#
.SYNOPSIS
    Misura, sulla storia reale del repository corrente, quanti caratteri il
    comando /commit-desc avrebbe inviato al modello per ogni commit passato.

.DESCRIPTION
    Versione PowerShell di measure_history.sh, per non dipendere da Git Bash.
    Serve a tarare il tetto di caratteri (head -c) usato in SKILL.md sui propri
    commit invece che a intuito.

    Per ogni commit non-merge riporta due misure:
      Grezzi  il diff completo, senza esclusioni, contesto standard
      Inviati cio che /commit-desc invierebbe davvero: contesto ridotto e
              file di rumore esclusi, prima che il tetto venga applicato

    I merge sono esclusi: `git show` non stampa un diff per i merge, quindi
    risulterebbero a zero e falserebbero le statistiche.

.PARAMETER Count
    Quanti commit analizzare, a partire da HEAD. Default 100.

.PARAMETER Cap
    Il tetto con cui confrontare le misure. Default 12000, come in SKILL.md.

.PARAMETER ContextLines
    Righe di contesto usate per la misura "Inviati". Default 2, come in SKILL.md.

.EXAMPLE
    .\measure_history.ps1 200

.EXAMPLE
    .\measure_history.ps1 -Count 200 -Cap 24000
#>
[CmdletBinding()]
param(
    [int]$Count = 100,
    [int]$Cap = 12000,
    [int]$ContextLines = 2
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERRORE: git non e' disponibile nel PATH." -ForegroundColor Red
    exit 1
}

& git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRORE: questa cartella non e' un repository git." -ForegroundColor Red
    exit 1
}

# La stessa lista di esclusioni usata da SKILL.md.
$excludes = @(
    ':(exclude)*.lock'
    ':(exclude)*-lock.json'
    ':(exclude)*.lockb'
    ':(exclude)*.min.js'
    ':(exclude)*.min.css'
    ':(exclude)*.map'
    ':(exclude)*.snap'
    ':(exclude)*.ipynb'
    ':(exclude)*.csv'
    ':(exclude)*.tsv'
    ':(exclude)*.parquet'
    ':(exclude)*.xlsx'
    ':(exclude)*.pdf'
    ':(exclude)*.png'
    ':(exclude)*.jpg'
    ':(exclude)*.gif'
    ':(exclude)*.pkl'
    ':(exclude)*.h5'
    ':(exclude)*.zip'
    ':(exclude)dist/*'
    ':(exclude)*/dist/*'
    ':(exclude)build/*'
    ':(exclude)node_modules/*'
)

function Measure-GitOutputChars {
    param([string[]]$Arguments)
    $total = 0
    & git @Arguments 2>$null | ForEach-Object { $total += $_.Length + 1 }
    return $total
}

$shas = @(& git log -n $Count --no-merges --pretty=%H 2>$null)
if ($shas.Count -eq 0) {
    Write-Host "Nessun commit non-merge trovato."
    exit 0
}

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($sha in $shas) {
    $i++
    Write-Progress -Activity "Analisi dei commit" -Status "$i di $($shas.Count)" -PercentComplete (100 * $i / $shas.Count)

    $rawArgs = @('show', '--no-color', '--no-ext-diff', '--format=', '-M', $sha)
    $sentArgs = @('show', '--no-color', '--no-ext-diff', '--diff-algorithm=minimal', "-U$ContextLines", '--format=', '-M', $sha, '--', '.') + $excludes

    $rows.Add([pscustomobject]@{
        Sha     = $sha.Substring(0, 8)
        Raw     = Measure-GitOutputChars -Arguments $rawArgs
        Sent    = Measure-GitOutputChars -Arguments $sentArgs
        Subject = (& git log -1 --pretty=%s $sha 2>$null)
    })
}
Write-Progress -Activity "Analisi dei commit" -Completed

$sorted = @($rows | Sort-Object Sent)
$n = $sorted.Count
$median = $sorted[[int][math]::Floor(($n - 1) / 2)].Sent
$p90Index = [int][math]::Floor(0.9 * ($n - 1))
if ($p90Index -ge $n) { $p90Index = $n - 1 }
if ($p90Index -lt 0) { $p90Index = 0 }
$p90 = $sorted[$p90Index].Sent
$max = $sorted[$n - 1].Sent
$over = @($rows | Where-Object { $_.Sent -gt $Cap }).Count
$rawSum = ($rows | Measure-Object -Property Raw -Sum).Sum
$sentSum = ($rows | Measure-Object -Property Sent -Sum).Sum
$saved = 0
if ($rawSum -gt 0) { $saved = 100 * ($rawSum - $sentSum) / $rawSum }

Write-Host ""
Write-Host ("Commit analizzati: {0} (merge esclusi)   tetto: {1:N0} caratteri   contesto: {2} righe" -f $n, $Cap, $ContextLines)
Write-Host ""
Write-Host "Caratteri inviati al modello (dopo le esclusioni, prima del tetto):"
Write-Host ("  mediana        {0,10:N0}" -f $median)
Write-Host ("  90 percentile  {0,10:N0}" -f $p90)
Write-Host ("  massimo        {0,10:N0}" -f $max)
Write-Host ("  oltre il tetto: {0} su {1} ({2:N0}%)" -f $over, $n, (100 * $over / $n))
Write-Host ""
Write-Host ("Effetto di esclusioni e contesto ridotto: da {0:N0} a {1:N0} caratteri totali (-{2:N0}%)" -f $rawSum, $sentSum, $saved)
Write-Host ""
Write-Host "I commit piu' grandi:"
Write-Host ("  {0,10} {1,10}  {2,-8}  {3}" -f 'inviati', 'grezzi', 'sha', 'oggetto')

$top = @($sorted[[math]::Max(0, $n - 10)..($n - 1)])
[array]::Reverse($top)
foreach ($r in $top) {
    $flag = '  '
    if ($r.Sent -gt $Cap) { $flag = ' *' }
    $subject = $r.Subject
    if ($subject.Length -gt 60) { $subject = $subject.Substring(0, 60) }
    Write-Host ("{0}{1,10:N0} {2,10:N0}  {3,-8}  {4}" -f $flag, $r.Sent, $r.Raw, $r.Sha, $subject)
}

if ($over -gt 0) {
    Write-Host ""
    Write-Host "* superano il tetto: il diff sarebbe stato troncato."
}
