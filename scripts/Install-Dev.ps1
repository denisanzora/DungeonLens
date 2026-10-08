[CmdletBinding()]
param(
    [string]$GamePath = 'E:\World of Warcraft\_classic_beta_',
    [ValidateSet('Junction', 'Copy')]
    [string]$Mode = 'Junction'
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$client = [IO.Path]::GetFullPath($GamePath).TrimEnd('\')
$exe = Join-Path $client 'WowB.exe'
$buildInfo = Join-Path (Split-Path -Parent $client) '.build.info'
$addons = Join-Path $client 'Interface\AddOns'
$destination = Join-Path $addons 'DungeonLens'
$files = @('DungeonLens.toc', 'Core.lua', 'MapData.lua', 'MapRegistry.lua', 'DungeonLevels.lua', 'DungeonEntrances.lua', 'WMOComposition.lua', 'BossData.lua', 'LootData.lua', 'MarkerData.lua', 'MapDetector.lua', 'Overlay.lua', 'MapRenderer.lua', 'DungeonWindow.lua', 'SeenLoot.lua', 'BossPanel.lua', 'BossList.lua', 'EntranceCard.lua', 'MinimapButton.lua', 'Authoring.lua', 'PositionProbe.lua', 'Diagnostics.lua', 'CompositePreview.lua')

if ((Split-Path -Leaf $client) -ne '_classic_beta_' -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Expected a Forever _classic_beta_ directory containing WowB.exe: $client"
}
$version = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
if ($version -notlike '1.60.1.*' -or -not (Test-Path -LiteralPath $buildInfo -PathType Leaf)) {
    throw "The selected client is not the targeted Forever 1.60.1 beta: $client"
}
if (-not ((Get-Content -LiteralPath $buildInfo) -match '\|wow_classic_beta\s*$')) {
    throw "Build metadata does not identify wow_classic_beta: $buildInfo"
}
if (-not (Test-Path -LiteralPath $addons -PathType Container)) {
    throw "AddOns parent directory does not exist: $addons"
}
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $file) -PathType Leaf)) {
        throw "Missing runtime file: $file"
    }
}

$existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $targets = @($existing.Target)
        if ($targets.Count -eq 1 -and $targets[0].TrimEnd('\') -eq $repo) {
            "Existing development link verified: $destination -> $repo"
            return
        }
        throw "DungeonLens is already a different link; refusing to replace it: $destination"
    }
    $marker = Join-Path $destination '.dungeonlens-dev-install'
    if ($Mode -ne 'Copy' -or -not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        (Get-Content -LiteralPath $marker -Raw).Trim() -ne $repo) {
        throw "DungeonLens already exists and is not this repository's managed copy: $destination"
    }
}

if ($Mode -eq 'Junction') {
    New-Item -ItemType Junction -Path $destination -Target $repo | Out-Null
    $link = Get-Item -LiteralPath $destination -Force
    if (-not ($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @($link.Target)[0].TrimEnd('\') -ne $repo) {
        throw 'Created junction did not resolve to the repository.'
    }
    "Development junction created: $destination -> $repo"
} else {
    if (-not $existing) { New-Item -ItemType Directory -Path $destination | Out-Null }
    $marker = Join-Path $destination '.dungeonlens-dev-install'
    [IO.File]::WriteAllText($marker, $repo)
    foreach ($file in $files) {
        Copy-Item -LiteralPath (Join-Path $repo $file) -Destination (Join-Path $destination $file) -Force
    }
    "Development copy installed: $destination"
}

foreach ($file in $files) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $repo $file) -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath (Join-Path $destination $file) -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash) { throw "Installed runtime file differs: $file" }
}
"Verified $($files.Count) runtime files. Client build: $version"
'Restart the client for a newly installed addon; use /reload for subsequent source edits.'
