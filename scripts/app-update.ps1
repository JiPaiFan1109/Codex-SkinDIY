# Update metadata is authenticated independently of GitHub using the bundled RSA key.
function Test-DynamicNewVersion {
  param([string]$Candidate,[string]$Current)
  foreach($value in @($Candidate,$Current)){if($value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'){throw 'Invalid stable version'}}
  return ([version]$Candidate -gt [version]$Current)
}

function Read-DynamicUpdateState {
  param([string]$StateRoot)
  try{
    $path=Join-Path $StateRoot 'update-state.json'
    if((Get-Item -LiteralPath $path -ErrorAction Stop).Length -gt 16KB){return @{}}
    $value=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    return @{LastCheckUtc=[string]$value.LastCheckUtc;SkippedVersion=[string]$value.SkippedVersion}
  }catch{return @{}}
}

function Save-DynamicUpdateState {
  param([string]$StateRoot,$State)
  $path=Join-Path $StateRoot 'update-state.json';$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try{
    [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
  }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Test-DynamicUpdateDue {
  param($State,[datetime]$Now=[datetime]::UtcNow)
  try{$Now=$Now.ToUniversalTime();$last=[datetime]::Parse($State.LastCheckUtc).ToUniversalTime();return ($Now -lt $last -or ($Now-$last).TotalHours -ge 24)}catch{return $true}
}

function Read-DynamicSignedUpdate {
  param([string]$ManifestPath,[string]$SignaturePath,[string]$PublicKeyPath,[string]$Version)
  if((Get-Item $ManifestPath).Length -gt 64KB -or (Get-Item $SignaturePath).Length -gt 4KB){throw '更新清单过大。'}
  $bytes=[IO.File]::ReadAllBytes($ManifestPath)
  $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
  $rsa.PersistKeyInCsp=$false
  try{
    $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
    if(-not $rsa.VerifyData($bytes,'SHA256',[Convert]::FromBase64String([IO.File]::ReadAllText($SignaturePath).Trim()))){throw '更新签名无效，已停止更新。'}
  }finally{$rsa.Dispose()}
  $manifest=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
  $null=Test-DynamicNewVersion ([string]$manifest.version) '0.0.0'
  $url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$manifest.version+'/Codex-Skin-Manager-Setup.exe'
  if($manifest.schema -ne 1 -or $manifest.version -cne $Version -or $manifest.url -cne $url -or
    $manifest.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $manifest.size -lt 1 -or $manifest.size -gt 300MB -or
    [string]$manifest.notes -eq '' -or ([string]$manifest.notes).Length -gt 12000){throw '更新清单格式或来源无效。'}
  return $manifest
}

function Assert-DynamicUpdateFile {
  param([string]$Path,$Manifest)
  if((Get-Item -LiteralPath $Path).Length -ne $Manifest.size -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Manifest.sha256){throw '更新包校验失败，原有程序未被替换。'}
}

function Receive-DynamicUpdateFile {
  param([string]$Url,[string]$Path,[long]$Limit,[scriptblock]$Report)
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $request=[Net.HttpWebRequest]::Create($Url);$request.UserAgent='Codex-Dynamic-Skin-Updater';$request.Timeout=15000;$request.ReadWriteTimeout=15000
  $response=$null;$inputStream=$null;$outputStream=$null;$complete=$false
  try{
    $response=$request.GetResponse()
    if($response.ResponseUri.Scheme -ne 'https' -or $response.ContentLength -gt $Limit){throw '更新下载地址或大小无效。'}
    $inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($Path)
    $buffer=New-Object byte[] 65536;$total=0L;$watch=[Diagnostics.Stopwatch]::StartNew();$lastReport=-1
    while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
      $total+=$count;if($total -gt $Limit -or $watch.Elapsed.TotalMinutes -gt 10){throw '更新下载超过大小或时间限制。'}
      $outputStream.Write($buffer,0,$count)
      if($Report){
        $percent=[int][Math]::Min(100,[Math]::Floor(100.0*$total/$Limit))
        if($percent -ne $lastReport){& $Report ('正在下载更新… '+$percent+'%');$lastReport=$percent}
      }
    }
    $complete=$true
  }finally{
    if($outputStream){$outputStream.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()}
    if(-not $complete -and (Test-Path -LiteralPath $Path)){Remove-Item -LiteralPath $Path -Force}
  }
}

function Get-DynamicAppUpdate {
  param([string]$InstallRoot,[string]$StateRoot,[switch]$Manual)
  $state=Read-DynamicUpdateState $StateRoot
  if(-not $Manual -and -not(Test-DynamicUpdateDue $state)){return $null}
  # Throttle failed requests as well; manual checks always remain available.
  $state.LastCheckUtc=[datetime]::UtcNow.ToString('o');Save-DynamicUpdateState $StateRoot $state
  $temp=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-check-'+[guid]::NewGuid().ToString('N'))
  New-Item $temp -ItemType Directory|Out-Null
  try{
    $releasePath=Join-Path $temp 'release.json'
    Receive-DynamicUpdateFile 'https://api.github.com/repos/JiPaiFan1109/Codex-Dynamic-Skin/releases/latest' $releasePath 1MB
    $release=[IO.File]::ReadAllText($releasePath)|ConvertFrom-Json
    if($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v\d+\.\d+\.\d+$'){throw '无法确认稳定版本。'}
    $version=$release.tag_name.Substring(1)
    $current=[IO.File]::ReadAllText((Join-Path $InstallRoot 'VERSION')).Trim()
    if(-not(Test-DynamicNewVersion $version $current)){return $null}
    if(-not $Manual -and $state.SkippedVersion -eq $version){return $null}
    $base='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$version
    $json=Join-Path $temp 'update.json';$sig=Join-Path $temp 'update.sig'
    Receive-DynamicUpdateFile ($base+'/update.json') $json 64KB
    Receive-DynamicUpdateFile ($base+'/update.sig') $sig 4KB
    return Read-DynamicSignedUpdate $json $sig (Join-Path $InstallRoot 'scripts/update-public-key.xml') $version
  }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

function Save-DynamicAppUpdate {
  param([string]$InstallRoot,$Manifest,[scriptblock]$Report)
  $current=[IO.File]::ReadAllText((Join-Path $InstallRoot 'VERSION')).Trim()
  if(-not(Test-DynamicNewVersion $Manifest.version $current)){throw '此更新不比当前版本新。'}
  $temp=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-'+[guid]::NewGuid().ToString('N'))
  New-Item $temp -ItemType Directory|Out-Null
  try{
    # Re-fetch and verify the signed release at the download boundary, never trust UI state.
    $base='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$Manifest.version
    Receive-DynamicUpdateFile ($base+'/update.json') (Join-Path $temp 'update.json') 64KB
    Receive-DynamicUpdateFile ($base+'/update.sig') (Join-Path $temp 'update.sig') 4KB
    $verified=Read-DynamicSignedUpdate (Join-Path $temp 'update.json') (Join-Path $temp 'update.sig') (Join-Path $InstallRoot 'scripts/update-public-key.xml') $Manifest.version
    $setup=Join-Path $temp 'setup.exe'
    Receive-DynamicUpdateFile $verified.url $setup $verified.size $Report
    if($Report){& $Report '正在校验更新包…'}
    Assert-DynamicUpdateFile $setup $verified
    foreach($name in @('app-update.ps1','finish-update.ps1','update-progress.ps1','update-progress.xaml','update-public-key.xml')){Copy-Item -LiteralPath (Join-Path $InstallRoot ('scripts/'+$name)) -Destination $temp}
    return $temp
  }catch{Remove-Item -LiteralPath $temp -Recurse -Force;throw}
}
