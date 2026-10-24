$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$release=[IO.File]::ReadAllText((Join-Path $repo 'scripts/build-release.ps1'))
$app=[IO.File]::ReadAllText((Join-Path $repo 'scripts/build-app.ps1'))
function Assert([bool]$condition,[string]$message){if(-not $condition){throw $message}}
Assert ($release -match 'CodexPage-\$version-windows-x64\.zip') 'Release build must emit the canonical CodexPage ZIP name.'
Assert ($release -match 'Codex-Dynamic-Skin-\$version-windows-x64\.zip') 'Release build must retain the legacy ZIP name.'
Assert ($release -match 'Copy-Item -LiteralPath \$zipPath -Destination \$legacyZipPath') 'Legacy ZIP must be a byte-identical copy.'
Assert ($app -match "\$canonicalSetupName='CodexPage-Setup\.exe'") 'App build must define canonical setup name.'
Assert ($app -match "\$legacySetupName='Codex-Skin-Manager-Setup\.exe'") 'App build must retain legacy setup name.'
Assert ($app -match 'Copy-Item -LiteralPath \$generatedSetup -Destination \$canonicalSetup') 'Canonical setup must alias the compiled installer.'
Assert ($app -match 'Copy-Item -LiteralPath \$generatedSetup -Destination \$setup') 'Legacy setup must alias the compiled installer.'
'PASS canonical and legacy package names preserve byte-identical aliases'
