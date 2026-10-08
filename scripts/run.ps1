param([ValidateSet('windows','android')][string]$Target = 'windows')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } elseif (Test-Path 'C:\Projects\WhatsGramFlutter\bin\flutter.bat') { 'C:\Projects\WhatsGramFlutter\bin\flutter.bat' } else { throw 'Install Flutter 3.47.6 and add its bin directory to PATH.' }
if (!(Test-Path 'config/telegram.local.json')) { throw 'Copy config/telegram.example.json to config/telegram.local.json and enter your Telegram api_id and api_hash.' }
if ($Target -eq 'windows' -and !(Test-Path 'native/windows/tdjson.dll')) { throw 'Run scripts/build-tdlib-windows.ps1 first.' }
& $flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
if ($Target -eq 'windows') { & $flutter run -d windows --dart-define-from-file=config/telegram.local.json }
else { & $flutter run --dart-define-from-file=config/telegram.local.json }
if ($LASTEXITCODE -ne 0) { throw 'Flutter run failed.' }
