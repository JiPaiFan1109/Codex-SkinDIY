[CmdletBinding()]
param([string]$InstallRoot,[string]$Version,[int]$ManagerProcessId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'app-update.ps1')

function Invoke-DynamicUpdateInstall {
  param([string]$Root,[string]$Stage,[string]$TargetVersion,[int]$ParentId)
  $manifest=Read-DynamicSignedUpdate (Join-Path $Stage 'update.json') (Join-Path $Stage 'update.sig') (Join-Path $Stage 'update-public-key.xml') $TargetVersion
  if(-not(Test-DynamicNewVersion $TargetVersion ([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim()))){throw '已安装此版本或更新版本，取消重复升级。'}
  $setup=Join-Path $Stage 'setup.exe'
  Assert-DynamicUpdateFile $setup $manifest
  if($ParentId -gt 0){
    $parent=Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    if($parent){try{if(-not $parent.WaitForExit(30000)){throw '管理中心尚未退出，已停止升级。'}}finally{$parent.Dispose()}}
  }
  # The native launcher owns this mutex until its PowerShell child exits.
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while($true){
    $mutex=$null
    try{$mutex=[Threading.Mutex]::OpenExisting('CodexDynamicSkinManager')}catch [Threading.WaitHandleCannotBeOpenedException]{break}
    finally{if($mutex){$mutex.Dispose()}}
    if($watch.Elapsed.TotalSeconds -gt 30){throw '管理中心仍在运行，已停止升级。'}
    Start-Sleep -Milliseconds 200
  }
  # Keep the payload read-locked until setup exits, preventing replacement after verification.
  $lock=[IO.File]::Open($setup,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
    Assert-DynamicUpdateFile $setup $manifest
    $process=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $Stage 'install.log')+'"')) -WindowStyle Hidden -PassThru
    try{$process.WaitForExit();$exitCode=$process.ExitCode}finally{$process.Dispose()}
    if($exitCode -ne 0){throw ('安装未完成（代码 '+$exitCode+'）。请关闭占用程序后重试。安装日志：'+(Join-Path $Stage 'install.log'))}
    if([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim() -cne $TargetVersion){throw '安装后的版本校验失败，请重新下载安装程序。'}
  }finally{$lock.Dispose()}
}

if($MyInvocation.InvocationName -ne '.'){
  $default=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin')).TrimEnd('\')
  if([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') -ine $default){throw '不支持此安装目录的自动升级。'}
  $success=$false
  try{
    Invoke-DynamicUpdateInstall $InstallRoot $PSScriptRoot $Version $ManagerProcessId
    $success=$true;$message='已更新至 '+$Version+'。壁纸收藏已保留，选择壁纸并点击应用可重新连接换肤。'
  }catch{$message='更新未完成：'+$_.Exception.Message}
  [IO.File]::WriteAllText((Join-Path $InstallRoot 'update-result.json'),(@{Success=$success;Message=$message}|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  $launcher=Join-Path $InstallRoot 'CodexSkinManager.exe'
  if(Test-Path -LiteralPath $launcher){Start-Process -FilePath $launcher -WindowStyle Hidden}
  if($success){Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'setup.exe') -Force}
}
