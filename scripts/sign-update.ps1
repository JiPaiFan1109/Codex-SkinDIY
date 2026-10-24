[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$NotesPath,[string]$SigningKeyPath=(Join-Path $env:LOCALAPPDATA 'CodexDynamicSkinReleaseKeys/update-rsa.dpapi'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'app-update.ps1')
$version=[IO.File]::ReadAllText((Join-Path $repo 'VERSION')).Trim()
$null=Test-DynamicNewVersion $version '0.0.0'
$setup=Join-Path $OutputDirectory 'CodexPage-Setup.exe'
# Published clients pin this exact legacy URL. Keep the signed wire format and
# byte-identical alias until those clients have a supported migration path.
$legacySetup=Join-Path $OutputDirectory 'Codex-Skin-Manager-Setup.exe'
if((Get-FileHash -LiteralPath $setup).Hash -cne (Get-FileHash -LiteralPath $legacySetup).Hash){throw 'Legacy update alias must match the CodexPage installer.'}
$manifest=[ordered]@{
  schema=1;version=$version
  url=('https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$version+'/Codex-Skin-Manager-Setup.exe')
  sha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
  size=(Get-Item -LiteralPath $setup).Length
  notes=[IO.File]::ReadAllText([IO.Path]::GetFullPath($NotesPath)).Trim()
}
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider;$rsa.PersistKeyInCsp=$false
try{
  if($env:UPDATE_SIGNING_KEY_XML){$privateXml=$env:UPDATE_SIGNING_KEY_XML}
  else{
    Add-Type -AssemblyName System.Security
    $privateXml=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($SigningKeyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
  }
  $rsa.FromXmlString($privateXml);$privateXml=$null
  $json=Join-Path $OutputDirectory 'update.json';$signature=Join-Path $OutputDirectory 'update.sig'
  [IO.File]::WriteAllText($json,($manifest|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($signature,[Convert]::ToBase64String($rsa.SignData([IO.File]::ReadAllBytes($json),'SHA256')))
  $verified=Read-DynamicSignedUpdate $json $signature (Join-Path $PSScriptRoot 'update-public-key.xml') $version
  Assert-DynamicUpdateFile $setup $verified
  'Signed update manifest verified for '+$version
}finally{$privateXml=$null;$rsa.Dispose()}
