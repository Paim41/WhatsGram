$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content (Join-Path $root '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$destination = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($plugin in $manifest.plugins.windows) {
    $link = Join-Path $destination $plugin.name
    if (!(Test-Path -LiteralPath $link)) {
        New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null
    }
}
Write-Output 'Prepared Windows plugin junctions without changing Developer Mode or machine policy.'
