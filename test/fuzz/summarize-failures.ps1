param(
    [string]$Output = "FUZZ_FINDINGS.md",
    [string]$LogDir = "logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

$commit = (git rev-parse --short HEAD) 2>$null
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$logs = @()
if (Test-Path -LiteralPath $LogDir) {
    $logs = Get-ChildItem -LiteralPath $LogDir -File -Filter "*.log" | Sort-Object LastWriteTime -Descending
}

$failureFiles = @()
foreach ($path in @("cache\fuzz\failures", "cache\invariant\failures", "corpus\echidna", "corpus\medusa")) {
    if (Test-Path -LiteralPath $path) {
        $failureFiles += Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName
    }
}

$patterns = @(
    "failed",
    "falsified",
    "assertion",
    "panic",
    "invariant_",
    "echidna_",
    "test_crytic",
    "reproducer",
    "counterexample",
    "Call sequence"
)

$sections = New-Object System.Collections.Generic.List[string]
$sections.Add("# Fuzz Findings")
$sections.Add("")
$sections.Add("- Generated: $now")
$sections.Add("- Commit: $commit")
$sections.Add("- Logs scanned: $($logs.Count)")
$sections.Add("- Failure/corpus files found: $($failureFiles.Count)")
$sections.Add("")

$sections.Add("## Logs")
$sections.Add("")
if ($logs.Count -eq 0) {
    $sections.Add("No log files found under " + "``" + $LogDir + "``" + ".")
} else {
    foreach ($log in $logs) {
        $sections.Add("- " + "``" + $log.FullName + "``")
    }
}
$sections.Add("")

$sections.Add("## Failure Artifacts")
$sections.Add("")
if ($failureFiles.Count -eq 0) {
    $sections.Add("No failure artifacts found yet.")
} else {
    foreach ($file in $failureFiles) {
        $rel = Resolve-Path -LiteralPath $file.FullName -Relative
        $sections.Add("- " + "``" + $rel + "``")
    }
}
$sections.Add("")

$sections.Add("## Suspicious Log Excerpts")
$sections.Add("")
if ($logs.Count -eq 0) {
    $sections.Add("No logs to scan.")
    $sections.Add("")
} else {
    foreach ($log in $logs) {
        $matches = Select-String -LiteralPath $log.FullName -Pattern $patterns -SimpleMatch -CaseSensitive:$false -Context 2,8 -ErrorAction SilentlyContinue
        if (-not $matches) {
            continue
        }

        $sections.Add("### $($log.Name)")
        $sections.Add("")
        $seen = 0
        foreach ($match in $matches) {
            if ($seen -ge 12) {
                $sections.Add("_Additional matches omitted; inspect the raw log._")
                $sections.Add("")
                break
            }
            $sections.Add('```text')
            foreach ($line in $match.Context.PreContext) {
                $sections.Add($line)
            }
            $sections.Add($match.Line)
            foreach ($line in $match.Context.PostContext) {
                $sections.Add($line)
            }
            $sections.Add('```')
            $sections.Add("")
            $seen++
        }
    }
}

$sections.Add("## Triage Checklist")
$sections.Add("")
$sections.Add("- Reproduce the shortest sequence locally.")
$sections.Add("- Decide whether the failed property is a real spec violation or a harness precondition issue.")
$sections.Add("- Promote valid failures into deterministic Foundry tests.")
$sections.Add("- Add the root cause and affected surface to " + "``ISSUES.md``" + " or a dedicated audit note.")
$sections.Add("")

Set-Content -LiteralPath $Output -Value $sections -Encoding UTF8
Write-Host "Wrote $Output"
