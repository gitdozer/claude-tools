#Requires -Version 5.1

<#
.SYNOPSIS
    Measures, on the real history of the current repository, how many bytes the
    /commit-desc command would have sent to the model for each past commit.

.DESCRIPTION
    PowerShell version of measure_history.sh, so Git Bash is not required.
    Use it to tune the character cap (head -c) used in SKILL.md against your own
    commits instead of guessing.

    For every non-merge commit it reports two measurements:
      Raw   the complete diff, no exclusions, default context
      Sent  what /commit-desc would really send: reduced context and noise files
            excluded, before the cap is applied

    The unit is the byte, the same as `head -c` in SKILL.md and `wc -c` in
    measure_history.sh, so the numbers of the two versions agree even on accented
    text or with CRLF line endings.

    Merges are excluded: `git show` prints no diff for a merge, so they would show
    up as zero and distort the statistics.

    If git fails on a commit, that commit is listed and left out of the statistics
    instead of counting as zero: a silent zero would drag the median and the
    percentiles down, producing plausible but wrong numbers - exactly the numbers
    the cap is decided from.

.PARAMETER Count
    How many commits to analyse, starting from HEAD. Default 100.

.PARAMETER Cap
    The cap to compare the measurements against. Default 12000, as in SKILL.md.

.PARAMETER ContextLines
    Context lines used for the "Sent" measurement. Default 2, as in SKILL.md.

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

# Numbers are formatted with the invariant culture on purpose: PowerShell's `N0`
# follows the machine's locale, so on a non-English Windows the same value would
# print as 12.000 here and 12,000 in measure_history.sh. Forcing the culture keeps
# the two versions comparable line by line.
function Format-Number {
    param([double]$Value)
    return $Value.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: git is not available in PATH." -ForegroundColor Red
    exit 1
}

# Every git invocation goes through the two functions below, which start the
# process directly instead of using `& git ... 2>$null`. Three reasons, all
# verified on PowerShell 5.1:
#
#   1. Redirecting a native executable's stderr wraps every line in an
#      ErrorRecord; with $ErrorActionPreference = 'Stop' that error becomes
#      TERMINATING. A failing git killed the script with a NativeCommandError
#      before reaching the checks written to handle it -- including the one that
#      prints "this folder is not a git repository".
#   2. Without looking at the exit code, a failing git was indistinguishable from
#      an empty diff and ended up in the statistics as a zero.
#   3. `git | ForEach-Object` counts decoded characters, not bytes: accents and
#      CRLF made the numbers diverge from those of measure_history.sh.
#
# Reading the process's BaseStream solves all three: real bytes, a reliable
# ExitCode, and PowerShell's error stream never involved.

function New-GitStartInfo {
    param([string[]]$Arguments)

    # The arguments used here contain no spaces (hexadecimal shas and literal
    # pathspecs), but the quoting stays so that a future change does not make this
    # fragile.
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
    # Mandatory: a process started this way would inherit .NET's current
    # directory, which does not follow Set-Location. Without this line git would
    # run in another folder, the '.' pathspec would cut the diff, and the script
    # would measure the wrong repository without saying so.
    $psi.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    return $psi
}

function Measure-GitOutputBytes {
    param([string[]]$Arguments)

    $psi = New-GitStartInfo -Arguments $Arguments
    $process = [System.Diagnostics.Process]::Start($psi)
    # stderr must be drained in parallel: if git wrote more of it than fits in the
    # pipe buffer, the process would block.
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
    # PowerShell unrolls a single-element array into a string when a function
    # returns it, and [0] on a string gives the first character: that is why every
    # call site wraps the result in @(...).
    return @($out -split '\r?\n' | Where-Object { $_ -ne '' })
}

if ($null -eq (Get-GitLines -Arguments @('rev-parse', '--is-inside-work-tree'))) {
    Write-Host "ERROR: this folder is not a git repository." -ForegroundColor Red
    exit 1
}

# The same exclusion list used by SKILL.md.
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
    Write-Host "No non-merge commits found."
    exit 0
}

$rows = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($sha in $shas) {
    $i++
    Write-Progress -Activity "Analysing commits" -Status "$i of $($shas.Count)" -PercentComplete (100 * $i / $shas.Count)

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
Write-Progress -Activity "Analysing commits" -Completed

if ($rows.Count -eq 0) {
    Write-Host ("ERROR: git produced no measurable diff for any of the {0} commits analysed." -f $shas.Count) -ForegroundColor Red
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
Write-Host ("Commits analysed: {0} (merges excluded)   cap: {1} characters   context: {2} lines" -f $n, (Format-Number $Cap), $ContextLines)
Write-Host ""
Write-Host "Characters sent to the model (after exclusions, before the cap):"
Write-Host ("  median         {0,10}" -f (Format-Number $median))
Write-Host ("  90th percentile{0,10}" -f (Format-Number $p90))
Write-Host ("  maximum        {0,10}" -f (Format-Number $max))
Write-Host ("  over the cap: {0} of {1} ({2}%)" -f $over, $n, (Format-Number ([math]::Round(100 * $over / $n))))
Write-Host ""
Write-Host ("Effect of exclusions and reduced context: from {0} to {1} total characters (-{2}%)" -f (Format-Number $rawSum), (Format-Number $sentSum), (Format-Number ([math]::Round($saved))))
Write-Host ""
Write-Host "The largest commits:"
Write-Host ("  {0,10}  {1,10}  {2,8}  {3}" -f 'sent', 'raw', 'sha', 'subject')

$top = @($sorted[[math]::Max(0, $n - 10)..($n - 1)])
[array]::Reverse($top)
foreach ($r in $top) {
    $flag = '  '
    if ($r.Sent -gt $Cap) { $flag = ' *' }
    $subject = $r.Subject
    if ($subject.Length -gt 60) { $subject = $subject.Substring(0, 60) }
    Write-Host ("{0}{1,10}  {2,10}  {3,8}  {4}" -f $flag, (Format-Number $r.Sent), (Format-Number $r.Raw), $r.Sha, $subject)
}

if ($over -gt 0) {
    Write-Host ""
    Write-Host "* over the cap: the diff would have been truncated."
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host ("WARNING: git produced no measurable diff for {0} of {1} commits. They are excluded from the statistics above:" -f $failed.Count, $shas.Count) -ForegroundColor Yellow
    foreach ($f in $failed) {
        Write-Host ("  {0}  {1}" -f $f.Sha, $f.Subject)
    }
}
