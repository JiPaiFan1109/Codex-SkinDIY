$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
Add-Type -TypeDefinition @"
public static class TaskbarIdentityProbe {
  [System.Runtime.InteropServices.DllImport("shell32.dll")]
  public static extern int GetCurrentProcessExplicitAppUserModelID(out System.IntPtr appId);
}
"@
$originalLocalAppData=$env:LOCALAPPDATA
$env:LOCALAPPDATA=Join-Path ([IO.Path]::GetTempPath()) ('missing-icon-cache-'+[guid]::NewGuid().ToString('N'))
$window=$null
try{
  $window=New-DynamicSkinManagerWindow
  $pointer=[IntPtr]::Zero
  try{
    [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([TaskbarIdentityProbe]::GetCurrentProcessExplicitAppUserModelID([ref]$pointer))
    if([Runtime.InteropServices.Marshal]::PtrToStringUni($pointer) -cne 'CodexDynamicSkin.Manager'){throw 'Manager still uses the host taskbar identity'}
  }finally{if($pointer -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer)}}
  if($null -eq $window.Icon -or $window.Icon.Width -le 0){throw 'Manager taskbar icon did not load'}
  if($null -eq $window.FindName('CodexIcon').Source -or $window.FindName('CodexIconFallback').Visibility -ne 'Collapsed'){throw 'Bundled connection icon did not load without the local cache'}
  'PASS: independent manager taskbar identity, manager icon, bundled connection icon without local cache'
}finally{
  if($window){$window.Close()}
  $env:LOCALAPPDATA=$originalLocalAppData
}