# Builds Encore for Windows: dist\encore-<version>-windows-x64-setup.exe (the setup program) and
# dist\encore-<version>-windows-x64.zip (the portable copy: unpack anywhere and run encore.exe), plus
# dist\SHA256SUMS-windows.txt. Needs Flutter, Visual Studio's C++ tools, Rust and Inno Setup 6.
# Usage (from the repository):  powershell -File tools\windows\build.ps1 [-NoFlutter]
param([switch]$NoFlutter)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$name = "encore-$version-windows-x64"
if (-not $NoFlutter) { flutter build windows --release; if ($LASTEXITCODE) { exit $LASTEXITCODE } }
$release = 'build\windows\x64\runner\Release'
New-Item -ItemType Directory -Force dist | Out-Null

# a quick check that it starts and finds all its DLLs (--version ends without opening a window)
$p = Start-Process -FilePath "$release\encore.exe" -ArgumentList '--version' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "encore.exe --version failed ($($p.ExitCode))" }

# the portable copy
$zip = "dist\$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
$stage = Join-Path $env:TEMP $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $release $stage
Compress-Archive -Path "$stage\*" -DestinationPath $zip
Remove-Item -Recurse -Force $stage

# the setup program
$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
& $iscc "/DAppVersion=$version" "/DBuildDir=$((Resolve-Path $release).Path)" "/DOutDir=$((Resolve-Path dist).Path)" tools\windows\encore.iss
if ($LASTEXITCODE) { exit $LASTEXITCODE }

# checksums, in the same format as sha256sum (lowercase, two spaces)
Push-Location dist
$lines = foreach ($f in @("$name-setup.exe", "$name.zip")) {
  "$((Get-FileHash -Algorithm SHA256 $f).Hash.ToLower())  $f"
}
[IO.File]::WriteAllLines((Join-Path $PWD 'SHA256SUMS-windows.txt'), $lines)
Pop-Location
Get-ChildItem dist
