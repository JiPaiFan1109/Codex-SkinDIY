$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/media.ps1";Initialize-DynamicMedia $repo
. "$repo/scripts/skin-manager.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
$w=New-DynamicSkinManagerWindow
try{
 $c=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText("$repo/scripts/skin-manager.xaml"),'x:Name="([^"]+)"')){$c[$m.Groups[1].Value]=$w.FindName($m.Groups[1].Value)}
 $script:SkinManager=@{Window=$w;Controls=$c;PendingOperation='Apply';Filter='Image';Source='Local';Busy=$true;PrepareOnly=$true;Playing=$false;Connection=[pscustomobject]@{Available=$false;Connected=$false;Message='Offline'};Items=@();Selected=$null}
 $script:result=[pscustomobject]@{Items=@();Status=[pscustomobject]@{Error=$null;CurrentId=$null;HasExternalCurrent=$false};Message='Cancelled';Connection=$script:SkinManager.Connection;SelectedId=$null;EngineReport=$null;Cancelled=$true}
 $worker=[pscustomobject]@{HadErrors=$false};$worker|Add-Member ScriptMethod EndInvoke {param($a);$script:result};$worker|Add-Member ScriptMethod Dispose {}
 $runspace=[pscustomobject]@{};$runspace|Add-Member ScriptMethod Dispose {}
 $script:SkinManager.Worker=$worker;$script:SkinManager.Runspace=$runspace;$script:SkinManager.Async=[pscustomobject]@{IsCompleted=$true};$script:SkinManager.Queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]';$script:SkinManager.Timer=New-Object Windows.Threading.DispatcherTimer
 Complete-DynamicManagerWork
 Assert ($c.ToastMessage.Text -ne '壁纸已应用') 'Cancelled apply incorrectly reported success'
 $path=Join-Path $repo 'engine/assets/demo-background.png'
 $first=Read-DynamicManagerBitmap $path
 $second=Read-DynamicManagerBitmap $path
 Assert ([object]::ReferenceEquals($first,$second)) 'Repeated thumbnails decoded again instead of reusing immutable bitmap'
 'PASS cancellation feedback and repeated bitmap reuse'
}finally{if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()};$w.Close();$script:SkinManager=$null}
