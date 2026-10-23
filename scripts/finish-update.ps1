[CmdletBinding()]
param([string]$InstallRoot,[string]$Version,[int]$ManagerProcessId,[string]$ReadyPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'app-update.ps1')

function Invoke-DynamicUpdateInstall {
  param([string]$Root,[string]$Stage,[string]$TargetVersion,[int]$ParentId,[scriptblock]$Report)
  if($Report){& $Report '正在校验更新包…'}
  $manifest=Read-DynamicSignedUpdate (Join-Path $Stage 'update.json') (Join-Path $Stage 'update.sig') (Join-Path $Stage 'update-public-key.xml') $TargetVersion
  if(-not(Test-DynamicNewVersion $TargetVersion ([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim()))){throw '已安装此版本或更新版本，取消重复升级。'}
  $setup=Join-Path $Stage 'setup.exe'
  Assert-DynamicUpdateFile $setup $manifest
  if($ParentId -gt 0){
    if($Report){& $Report '正在关闭 CodexPage，准备安装…'}
    $parent=Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    if($parent){try{if(-not $parent.WaitForExit(30000)){throw 'CodexPage 尚未退出，已停止升级。'}}finally{$parent.Dispose()}}
  }
  # The native launcher owns this mutex until its PowerShell child exits.
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while($true){
    $mutex=$null
    try{$mutex=[Threading.Mutex]::OpenExisting('CodexDynamicSkinManager')}catch [Threading.WaitHandleCannotBeOpenedException]{break}
    finally{if($mutex){$mutex.Dispose()}}
    if($watch.Elapsed.TotalSeconds -gt 30){throw 'CodexPage 仍在运行，已停止升级。'}
    Start-Sleep -Milliseconds 200
  }
  # Keep the payload read-locked until setup exits, preventing replacement after verification.
  $lock=[IO.File]::Open($setup,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
    Assert-DynamicUpdateFile $setup $manifest
    if($Report){& $Report '正在安装更新，请稍候…'}
    $process=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+[IO.Path]::GetFullPath($Root).TrimEnd('\')+'"'),('/LOG="'+(Join-Path $Stage 'install.log')+'"')) -WindowStyle Hidden -PassThru
    try{$process.WaitForExit();$exitCode=$process.ExitCode}finally{$process.Dispose()}
    if($exitCode -ne 0){throw ('安装未完成（代码 '+$exitCode+'）。请关闭占用程序后重试。安装日志：'+(Join-Path $Stage 'install.log'))}
    if($Report){& $Report '正在确认安装结果…'}
    if([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim() -cne $TargetVersion){throw '安装后的版本校验失败，请返回 CodexPage 重试。'}
  }finally{$lock.Dispose()}
}

if($MyInvocation.InvocationName -ne '.'){
  $success=$false
  try{
    if($ReadyPath -and [IO.Path]::GetFullPath($ReadyPath) -ine (Join-Path $PSScriptRoot 'ui-ready')){throw '更新状态路径无效。'}
    . (Join-Path $PSScriptRoot 'update-progress.ps1')
    $result=Show-DynamicUpdateInstallProgress $InstallRoot $PSScriptRoot $Version $ManagerProcessId $ReadyPath
    $success=[bool]$result.Success;$message=[string]$result.Message
  }catch{$message='更新未完成：'+$_.Exception.Message}
  [IO.File]::WriteAllText((Join-Path $InstallRoot 'update-result.json'),(@{Success=$success;Message=$message}|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  $launcher=Join-Path $InstallRoot 'CodexSkinManager.exe'
  if(Test-Path -LiteralPath $launcher){Start-Process -FilePath $launcher -WindowStyle Hidden}
  if($success){Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'setup.exe') -Force}
}
