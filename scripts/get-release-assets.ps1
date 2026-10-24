[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference='Stop'
# Validate the complete inventory before creating or publishing a release.
$pairs=@(
  @('CodexPage-Setup.exe','Codex-Skin-Manager-Setup.exe'),
  @("CodexPage-$Version-windows-x64.zip","Codex-Dynamic-Skin-$Version-windows-x64.zip")
)
$assets=@()
foreach($pair in $pairs){
  $hashes=@()
  foreach($name in $pair){
    $path=Join-Path $OutputDirectory $name
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected=$hash+'  '+$name
    if([IO.File]::ReadAllText(($path+'.sha256')).Trim() -cne $expected){throw "Invalid release checksum: $name"}
    $hashes+=$hash
    $assets+=@($name,($name+'.sha256'))
  }
  if($hashes[0] -cne $hashes[1]){throw "Compatibility alias differs: $($pair[1])"}
}
foreach($name in @('update.json','update.sig')){
  if(-not(Test-Path -LiteralPath (Join-Path $OutputDirectory $name) -PathType Leaf)){throw "Missing release metadata: $name"}
  $assets+=$name
}
$assets
