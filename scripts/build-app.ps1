[CmdletBinding()]
param([string]$NodeRuntimePath,[string]$IsccPath,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'dist'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$canonicalSetupName='CodexPage-Setup.exe'
$legacySetupName='Codex-Skin-Manager-Setup.exe'
if((Test-Path (Join-Path $OutputDirectory 'app-package')) -or (Test-Path (Join-Path $OutputDirectory $canonicalSetupName)) -or (Test-Path (Join-Path $OutputDirectory $legacySetupName))){throw 'Use an empty output directory to avoid replacing an existing build.'}
if(-not $IsccPath){
  $IsccPath=@((Join-Path $repo '.tools/inno/compiler/ISCC.exe'),"${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe","$env:ProgramFiles/Inno Setup 7/ISCC.exe")|Where-Object{Test-Path -LiteralPath $_}|Select-Object -First 1
}
if(-not $IsccPath){throw 'Install Inno Setup and pass -IsccPath with ISCC.exe.'}
$version=(Get-Content (Join-Path $repo 'VERSION') -Raw).Trim()
$buildRoot=Join-Path ([IO.Path]::GetTempPath()) ('skin-app-build-'+[guid]::NewGuid().ToString('N'))
New-Item $buildRoot -ItemType Directory|Out-Null
try {
  & (Join-Path $PSScriptRoot 'build-release.ps1') -NodeRuntimePath $NodeRuntimePath -OutputDirectory $buildRoot|Write-Host
  $package=Join-Path $buildRoot 'package'
  Expand-Archive -LiteralPath (Join-Path $buildRoot "CodexPage-$version-windows-x64.zip") -DestinationPath $package
  New-Item $OutputDirectory -ItemType Directory -Force|Out-Null
  & $IsccPath ("/DSourceRoot=$package") ("/DAppVersion=$version") ("/O$OutputDirectory") (Join-Path $repo 'installer/windows.iss')
  if($LASTEXITCODE -ne 0){throw 'Windows setup compilation failed.'}
  $generatedSetup=$null
  foreach($candidateName in @($canonicalSetupName,$legacySetupName)){
    $candidatePath=Join-Path $OutputDirectory $candidateName
    if(Test-Path -LiteralPath $candidatePath -PathType Leaf){$generatedSetup=$candidatePath;break}
  }
  if(-not $generatedSetup){throw 'Windows setup compiler did not produce an installer executable.'}
  $setup=Join-Path $OutputDirectory $legacySetupName
  $canonicalSetup=Join-Path $OutputDirectory $canonicalSetupName
  if([IO.Path]::GetFullPath($generatedSetup) -ne [IO.Path]::GetFullPath($setup)){Copy-Item -LiteralPath $generatedSetup -Destination $setup}
  if([IO.Path]::GetFullPath($generatedSetup) -ne [IO.Path]::GetFullPath($canonicalSetup)){Copy-Item -LiteralPath $generatedSetup -Destination $canonicalSetup}
  foreach($artifact in @($setup,$canonicalSetup)){
    $sum=(Get-FileHash $artifact -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($artifact)
    [IO.File]::WriteAllText(($artifact+'.sha256'),$sum+"`n",(New-Object Text.UTF8Encoding($false)))
  }
  # Keep an inspectable copy of exactly the files used to compile this installer.
  $audit=Join-Path $OutputDirectory 'app-package'
  if(Test-Path $audit){throw 'app-package already exists; use an empty output directory.'}
  Copy-Item -LiteralPath $package -Destination $audit -Recurse
  foreach($zipName in @("CodexPage-$version-windows-x64.zip","Codex-Dynamic-Skin-$version-windows-x64.zip")){
    Copy-Item -LiteralPath (Join-Path $buildRoot $zipName) -Destination $OutputDirectory
    Copy-Item -LiteralPath (Join-Path $buildRoot ($zipName+'.sha256')) -Destination $OutputDirectory
  }
  Write-Output $canonicalSetup
  Write-Output $sum
}finally{
  if([IO.Path]::GetFullPath($buildRoot).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
  }
}
