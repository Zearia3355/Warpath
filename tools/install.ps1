<#
.SYNOPSIS
    Copy the working copy into the game's AddOns folder.

.DESCRIPTION
    The working copy is deliberately not the AddOns folder: installed files
    change only on a rev, never as a side effect of editing. This script is
    that rev step.

    Repo-only files (git, CI, docs, tools, project notes) are never copied.
    Files already in the destination that are no longer in the repo are
    reported, not deleted, so nothing is lost by surprise.

.PARAMETER Destination
    The Warpath folder inside the game's Interface\AddOns. Falls back to the
    WARPATH_ADDONS environment variable. The actual path is recorded in
    CLAUDE.local.md, which is untracked.

.PARAMETER DryRun
    List what would be copied and change nothing.

.EXAMPLE
    .\tools\install.ps1 -DryRun
    .\tools\install.ps1 -Destination 'D:\Games\WoW\Interface\AddOns\Warpath'
#>
[CmdletBinding()]
param(
    [string] $Destination = $env:WARPATH_ADDONS,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Destination)) {
    throw "No destination. Pass -Destination, or set WARPATH_ADDONS. The path is in CLAUDE.local.md."
}

$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repo 'Warpath.toc'))) {
    throw "$repo does not look like the Warpath repo (no Warpath.toc)."
}

# Repo-only: never shipped. Mirrors the ignore list in .pkgmeta.
$excludeDirs = @('.git', '.github', 'docs', 'tools')
$excludeFiles = @('.pkgmeta', '.gitattributes', '.gitignore', 'CLAUDE.md', 'CLAUDE.local.md', 'README.md')

$version = (Select-String -Path (Join-Path $repo 'Warpath.toc') -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

# Everything the addon actually ships.
$files = Get-ChildItem -Path $repo -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($repo.Length + 1)
    $top = ($rel -split '\\')[0]
    ($excludeDirs -notcontains $top) -and ($excludeFiles -notcontains $rel)
}

Write-Host ""
Write-Host "Warpath $version" -ForegroundColor Cyan
Write-Host "  from: $repo"
Write-Host "  to:   $Destination"
Write-Host "  $($files.Count) files"
Write-Host ""

# Anything in the destination that this release no longer contains: a leftover
# from an older layout, which matters because the addon was one file until 3.4.
if (Test-Path $Destination) {
    $shipping = $files | ForEach-Object { $_.FullName.Substring($repo.Length + 1) }
    $stale = Get-ChildItem -Path $Destination -Recurse -File | ForEach-Object {
        $_.FullName.Substring($Destination.Length + 1)
    } | Where-Object { $shipping -notcontains $_ }

    if ($stale) {
        Write-Host "Already there but not part of this release (left alone):" -ForegroundColor Yellow
        $stale | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host ""
    }
}

if ($DryRun) {
    Write-Host "Dry run: nothing copied." -ForegroundColor Yellow
    return
}

foreach ($f in $files) {
    $rel = $f.FullName.Substring($repo.Length + 1)
    $target = Join-Path $Destination $rel
    $dir = Split-Path -Parent $target
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $f.FullName -Destination $target -Force
}

Write-Host "Installed Warpath $version." -ForegroundColor Green
Write-Host "A new or removed file, or any .toc change, needs a full game restart, not /reload." -ForegroundColor Cyan
