param([int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
$env:VCPKG_MAX_CONCURRENCY = "$Jobs"
$project = Split-Path $PSScriptRoot -Parent
$native = Join-Path $project 'native'
$lock = Get-Content (Join-Path $native 'tdlib.lock.json') -Raw | ConvertFrom-Json
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Install Visual Studio Desktop development with C++ and a Windows SDK.' }
Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
$cmake = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$ninja = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
$env:PATH = "$(Split-Path $ninja);$env:PATH"
$td = Join-Path $native 'td'
if (!(Test-Path $td)) { Invoke-Checked git @('clone','--filter=blob:none','--no-checkout',$lock.repository,$td) }
Invoke-Checked git @('-C',$td,'fetch','origin',$lock.commit,'--depth','1')
Invoke-Checked git @('-C',$td,'checkout','--detach',$lock.commit)
$vcpkg = Join-Path $native 'vcpkg'
$vcpkgCommit = '2750401336fb7c95f6619657a46a7e798661341c'
if (!(Test-Path $vcpkg)) { Invoke-Checked git @('clone','--filter=blob:none','--no-checkout','https://github.com/microsoft/vcpkg.git',$vcpkg) }
Invoke-Checked git @('-C',$vcpkg,'fetch','origin',$vcpkgCommit,'--depth','1')
Invoke-Checked git @('-C',$vcpkg,'checkout','--detach',$vcpkgCommit)
Invoke-Checked (Join-Path $vcpkg 'bootstrap-vcpkg.bat') @('-disableMetrics')
Invoke-Checked (Join-Path $vcpkg 'vcpkg.exe') @('install','openssl:x64-windows-static-md','zlib:x64-windows-static-md','gperf:x64-windows','--disable-metrics')
$build = Join-Path $native 'build\windows'
Invoke-Checked $cmake @('-S',$td,'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_TOOLCHAIN_FILE=$vcpkg/scripts/buildsystems/vcpkg.cmake",'-DVCPKG_TARGET_TRIPLET=x64-windows-static-md',"-DGPERF_EXECUTABLE=$vcpkg/installed/x64-windows/tools/gperf/gperf.exe",'-DTD_ENABLE_JNI=OFF','-DTD_ENABLE_DOTNET=OFF','-DOPENSSL_USE_STATIC_LIBS=TRUE')
Invoke-Checked $cmake @('--build',$build,'--target','tdjson','--parallel',"$Jobs")
$dll = Get-ChildItem -LiteralPath $build -Recurse -Filter tdjson.dll | Select-Object -First 1
if (!$dll) { throw 'TDLib built without producing tdjson.dll.' }
$destination = Join-Path $native 'windows'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $destination 'tdjson.dll')
Write-Output "TDLib $($lock.version) copied to $destination. OpenSSL and zlib are linked statically; MSVC runtime is required."
