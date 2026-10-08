[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$InGameValidated
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$runtime = @('Core.lua', 'MapData.lua', 'MapRegistry.lua', 'DungeonLevels.lua', 'DungeonEntrances.lua', 'WMOComposition.lua', 'BossData.lua', 'LootData.lua', 'MarkerData.lua', 'MapDetector.lua', 'Overlay.lua', 'MapRenderer.lua', 'DungeonWindow.lua', 'SeenLoot.lua', 'BossPanel.lua', 'BossList.lua', 'EntranceCard.lua', 'MinimapButton.lua', 'Authoring.lua', 'PositionProbe.lua', 'Diagnostics.lua', 'CompositePreview.lua')
$files = @('DungeonLens.toc') + $runtime
$tocPath = Join-Path $repo 'DungeonLens.toc'
$toc = Get-Content -LiteralPath $tocPath
if ($toc -notcontains '## Interface: 16001' -or $toc -notcontains '## Version: 0.2.0') {
    throw 'The TOC must target Interface 16001, Version 0.2.0.'
}
$tocFiles = @($toc | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($tocFiles.Count -ne $runtime.Count -or (Compare-Object $runtime $tocFiles)) {
    throw 'TOC runtime entries differ from the explicit packaging allowlist.'
}
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $file) -PathType Leaf)) {
        throw "Missing runtime file: $file"
    }
}
if (-not $CheckOnly -and -not $InGameValidated) {
    throw 'Run the in-game acceptance checklist first, then pass -InGameValidated. Use -CheckOnly for a no-file ZIP validation.'
}

Add-Type -AssemblyName System.IO.Compression
$memory = New-Object IO.MemoryStream
$zip = $null
try {
    $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($file in $files) {
        $entry = $zip.CreateEntry("DungeonLens/$file", [IO.Compression.CompressionLevel]::Optimal)
        $stream = $entry.Open()
        try {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $repo $file))
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
    $zip.Dispose()
    $zip = $null
    $memory.Position = 0
    $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Read, $true)
    $expectedNames = @($files | ForEach-Object { "DungeonLens/$_" })
    $actualNames = @($zip.Entries | ForEach-Object { $_.FullName })
    if ($actualNames.Count -ne $expectedNames.Count -or (Compare-Object $expectedNames $actualNames)) {
        throw 'ZIP entries differ from the runtime-only allowlist.'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in $files) {
            $entry = $zip.GetEntry("DungeonLens/$file")
            $stream = $entry.Open()
            try {
                $source = [IO.File]::ReadAllBytes((Join-Path $repo $file))
                $expectedHash = [Convert]::ToBase64String($sha.ComputeHash($source))
                $actualHash = [Convert]::ToBase64String($sha.ComputeHash($stream))
                if ($expectedHash -ne $actualHash) { throw "ZIP payload differs: $file" }
            } finally { $stream.Dispose() }
        }
    } finally { $sha.Dispose() }
    $zip.Dispose()
    $zip = $null

    if ($CheckOnly) {
        "PASS: in-memory ZIP contains exactly $($files.Count) runtime files under DungeonLens/; all SHA256 payloads match. No ZIP was written."
        return
    }
    $dist = Join-Path $repo 'dist'
    if (-not (Test-Path -LiteralPath $repo -PathType Container)) { throw 'Repository parent is missing.' }
    if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
    if (-not (Test-Path -LiteralPath $dist -PathType Container)) { throw 'dist is not a directory.' }
    $output = Join-Path $dist 'DungeonLens-0.2.0.zip'
    if (Test-Path -LiteralPath $output) { throw "ZIP already exists: $output" }
    [IO.File]::WriteAllBytes($output, $memory.ToArray())
    "Created and verified: $output"
} finally {
    if ($zip) { $zip.Dispose() }
    $memory.Dispose()
}
