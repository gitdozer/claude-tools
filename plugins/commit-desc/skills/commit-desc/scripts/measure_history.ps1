#Requires -Version 5.1

<#
.SYNOPSIS
    Misura, sulla storia reale del repository corrente, quanti byte il
    comando /commit-desc avrebbe inviato al modello per ogni commit passato.

.DESCRIPTION
    Versione PowerShell di measure_history.sh, per non dipendere da Git Bash.
    Serve a tarare il tetto di caratteri (head -c) usato in SKILL.md sui propri
    commit invece che a intuito.

    Per ogni commit non-merge riporta due misure:
      Grezzi  il diff completo, senza esclusioni, contesto standard
      Inviati cio che /commit-desc invierebbe davvero: contesto ridotto e
              file di rumore esclusi, prima che il tetto venga applicato

    L'unita' di misura sono i byte, la stessa di `head -c` in SKILL.md e di
    `wc -c` in measure_history.sh, cosi' i numeri delle due versioni coincidono
    anche su testo accentato o con fine riga CRLF.

    I merge sono esclusi: `git show` non stampa un diff per i merge, quindi
    risulterebbero a zero e falserebbero le statistiche.

    Se git fallisce su un commit, quel commit viene elencato ed escluso dalle
    statistiche invece di essere contato come zero: uno zero silenzioso
    abbasserebbe mediana e percentili dando numeri plausibili ma sbagliati,
    proprio quelli su cui si decide il tetto.

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

# Ogni invocazione di git passa dalle due funzioni qui sotto, che avviano il
# processo direttamente invece di usare `& git ... 2>$null`. Tre motivi, tutti
# verificati su PowerShell 5.1:
#
#   1. Redirigere lo stderr di un eseguibile nativo incapsula ogni riga in un
#      ErrorRecord; con $ErrorActionPreference = 'Stop' quell'errore diventa
#      TERMINANTE. Un git fallito uccideva lo script con una NativeCommandError
#      prima di raggiungere i controlli scritti per gestirlo -- compreso quello
#      che stampa "questa cartella non e' un repository git".
#   2. Senza guardare il codice di uscita, un git fallito era indistinguibile da
#      un diff vuoto e finiva nelle statistiche come zero.
#   3. `git | ForEach-Object` conta caratteri decodificati, non byte: accenti e
#      CRLF facevano divergere i numeri da quelli di measure_history.sh.
#
# Leggere il BaseStream del processo risolve tutti e tre: byte veri, ExitCode
# affidabile, e il flusso degli errori di PowerShell mai coinvolto.

function New-GitStartInfo {
    param([string[]]$Arguments)

    # Gli argomenti usati qui non contengono spazi (sha esadecimali e pathspec
    # letterali), ma la quotatura resta per non rendere fragile una modifica
    # futura.
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Obbligatorio: un processo avviato cosi' erediterebbe la directory corrente
    # di .NET, che non segue Set-Location. Senza questa riga git girerebbe in
    # un'altra cartella, il pathspec '.' taglierebbe il diff e lo script
    # misurerebbe il repository sbagliato senza dirlo.
    $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    return $psi
}

function Measure-GitOutputBytes {
    param([string[]]$Arguments)

    $psi = New-GitStartInfo -Arguments $Arguments
    $process = [System.Diagnostics.Process]::Start($psi)
    # Lo stderr va svuotato in parallelo: se git ne scrivesse piu' di quanto
    # entra nel buffer della pipe, il processo resterebbe bloccato.
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $stream = $process.StandardOutput.BaseStream
    $buffer = New-Object byte[] 65536
    $total = 0
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $total += $read }

    $process.WaitForExit()
    $null = $stderrTask.Result
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) { return $null }
    return $total
}

function Get-GitLines {
    param([string[]]$Arguments)

    $psi = New-GitStartInfo -Arguments $Arguments
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::Start($psi)
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $out = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    $null = $stderrTask.Result
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) { return $null }
    # PowerShell srotola un array di un solo elemento in una stringa quando lo
    # restituisce una funzione, e [0] su una stringa da' il primo carattere: per
    # questo chi chiama racchiude sempre il risultato in @(...).
    return @($out -split '\r?\n' | Where-Object { $_ -ne '' })
}

if ($null -eq (Get-GitLines -Arguments @('rev-parse', '--is-inside-work-tree'))) {
    Write-Host "ERRORE: questa cartella non e' un repository git." -ForegroundColor Red
    exit 1
}

# La stessa lista di esclusioni usata da SKILL.md.
$excludes = @(
    ':(exclude)*.lock'
    ':(exclude)*-lock.json'
    ':(exclude)*.lockb'
    ':(exclude)pnpm-lock.yaml'
    ':(exclude)*.min.js'
    ':(exclude)*.min.css'
    ':(exclude)*.map'
    ':(exclude)*.snap'
    ':(exclude)*.ipynb'
    ':(exclude)*.csv'
    ':(exclude)*.tsv'
    ':(exclude)*.parquet'
    ':(exclude)*.xlsx'
    ':(exclude)*.geojson'
    ':(exclude)*.pdf'
    ':(exclude)*.svg'
    ':(exclude)*.png'
    ':(exclude)*.jpg'
    ':(exclude)*.jpeg'
    ':(exclude)*.gif'
    ':(exclude)*.ico'
    ':(exclude)*.pkl'
    ':(exclude)*.h5'
    ':(exclude)*.onnx'
    ':(exclude)*.zip'
    ':(exclude)dist/*'
    ':(exclude)*/dist/*'
    ':(exclude)build/*'
    ':(exclude)*/build/*'
    ':(exclude)node_modules/*'
)

$shas = @(Get-GitLines -Arguments @('log', '-n', "$Count", '--no-merges', '--pretty=%H'))
if ($shas.Count -eq 0) {
    Write-Host "Nessun commit non-merge trovato."
    exit 0
}

$rows = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($sha in $shas) {
    $i++
    Write-Progress -Activity "Analisi dei commit" -Status "$i di $($shas.Count)" -PercentComplete (100 * $i / $shas.Count)

    $rawArgs = @('show', '--no-color', '--no-ext-diff', '--format=', '-M', $sha)
    $sentArgs = @('show', '--no-color', '--no-ext-diff', '--diff-algorithm=minimal', "-U$ContextLines", '--format=', '-M', $sha, '--', '.') + $excludes

    $raw = Measure-GitOutputBytes -Arguments $rawArgs
    $sent = Measure-GitOutputBytes -Arguments $sentArgs
    $subjectLines = @(Get-GitLines -Arguments @('log', '-1', '--pretty=%s', $sha))
    $subject = if ($subjectLines.Count -gt 0) { [string]$subjectLines[0] } else { '' }
    $short = $sha.Substring(0, 8)

    if ($null -eq $raw -or $null -eq $sent) {
        $failed.Add([pscustomobject]@{ Sha = $short; Subject = $subject })
        continue
    }

    $rows.Add([pscustomobject]@{
        Sha     = $short
        Raw     = $raw
        Sent    = $sent
        Subject = $subject
    })
}
Write-Progress -Activity "Analisi dei commit" -Completed

if ($rows.Count -eq 0) {
    Write-Host ("ERRORE: git non ha prodotto un diff misurabile per nessuno dei {0} commit analizzati." -f $shas.Count) -ForegroundColor Red
    exit 1
}

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

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host ("ATTENZIONE: git non ha prodotto un diff misurabile per {0} commit su {1}. Sono esclusi dalle statistiche qui sopra:" -f $failed.Count, $shas.Count) -ForegroundColor Yellow
    foreach ($f in $failed) {
        Write-Host ("  {0}  {1}" -f $f.Sha, $f.Subject)
    }
}
