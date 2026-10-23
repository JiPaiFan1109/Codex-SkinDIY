# Local media only: scene/web/application projects are never executed.
function Get-DynamicWallpaperEngineRoots {
  param([string[]]$SteamRoots)
  if(-not $SteamRoots){
    $SteamRoots=@(foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
      $entry=Get-ItemProperty $key -ErrorAction SilentlyContinue
      if($entry.SteamPath){$entry.SteamPath};if($entry.InstallPath){$entry.InstallPath}
    })+@("${env:ProgramFiles(x86)}\Steam","$env:ProgramFiles\Steam")
  }
  $libraries=@($SteamRoots)
  foreach($steam in $SteamRoots){
    $vdf=Join-Path $steam 'steamapps/libraryfolders.vdf'
    if(Test-Path -LiteralPath $vdf -PathType Leaf){
      foreach($match in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s*"([^"\r\n]+)"')){$libraries+=$match.Groups[1].Value.Replace('\\','\')}
    }
  }
  @(foreach($library in $libraries|Sort-Object -Unique){
    $manifest=Join-Path $library 'steamapps/appmanifest_431960.acf'
    if(Test-Path -LiteralPath $manifest){
      $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s*"([^"\r\n]+)"')
      if($match.Success -and $match.Groups[1].Value -notmatch '[/\\:]|^\.\.?$'){
        foreach($suffix in @('myprojects','defaultprojects')){
          $custom=Join-Path $library ('steamapps/common/'+$match.Groups[1].Value+'/projects/'+$suffix)
          if(Test-Path -LiteralPath $custom -PathType Container){[IO.Path]::GetFullPath($custom)}
        }
      }
    }
    foreach($relative in @('steamapps/workshop/content/431960','steamapps/common/wallpaper_engine/projects/myprojects','steamapps/common/wallpaper_engine/projects/defaultprojects')){
      $path=Join-Path $library $relative
      if(Test-Path -LiteralPath $path -PathType Container){[IO.Path]::GetFullPath($path)}
    }
  })|Sort-Object -Unique
}
function Get-DynamicWallpaperEngineProjects {
  param([string]$Root,[int]$Depth=0,[scriptblock]$OnError)
  try{Assert-DreamSkinNoReparseComponents -Path $Root}catch{if($OnError){& $OnError $Root $_.Exception.Message;return};throw}
  if(Test-Path -LiteralPath (Join-Path $Root 'project.json') -PathType Leaf){Get-Item -LiteralPath $Root;return}
  if($Depth -ge 5){return}
  try{$children=@(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop)}catch{if($OnError){& $OnError $Root $_.Exception.Message;return};throw}
  foreach($child in $children){
    if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
    Get-DynamicWallpaperEngineProjects $child.FullName ($Depth+1) $OnError
  }
}
function Import-DynamicSteamReference {
  param([string]$Media,[string]$Kind,[string]$StateRoot,[string]$Title)
  Assert-DreamSkinNoReparseComponents -Path $Media
  $file=Get-Item -LiteralPath $Media -ErrorAction Stop
  if($Kind -eq 'Image'){Assert-DreamSkinImageFile -Path $Media}
  elseif(-not (Test-DynamicVideoDirectImport $Media)){throw '此视频需要转码，无法直接引用；可通过本地导入保存兼容副本。'}
  $hash=(Get-FileHash -LiteralPath $Media -Algorithm SHA256).Hash.ToLowerInvariant()
  Invoke-DynamicWallpaperLock $StateRoot {
    $paths=Get-DynamicWallpaperPaths $StateRoot
    $id=$null;$oldMedia=$null;$oldEntry=$null;$localRecords=@()
    foreach($directory in Get-ChildItem -LiteralPath $paths.Items -Directory){
      if($directory.Name -cnotmatch '^[0-9a-f]{32}$'){continue}
      $item=Read-DynamicWallpaperItem $directory.FullName $directory.Name
      if($item.External -and $item.MediaPath -ieq $file.FullName){
        $id=$item.Id;$oldEntry=[IO.File]::ReadAllText((Join-Path $directory.FullName 'item.json'))|ConvertFrom-Json
        if($item.IsAvailable -and $item.Sha256 -eq $hash){return [pscustomobject]@{Item=$item;AlreadyExists=$true}}
        break
      }
      if($item.IsAvailable -and -not $item.External -and $item.Kind -eq $Kind -and $item.Sha256 -eq $hash -and $item.Sources -contains 'WallpaperEngine'){
        if($item.Sources -contains 'Local'){$localRecords+=Join-Path $directory.FullName 'item.json';continue}
        # Do not delete a legacy copy while a live background/server may use it.
        if((Get-DynamicWallpaperStatus $StateRoot).CurrentId -eq $item.Id){return [pscustomobject]@{Item=$item;AlreadyExists=$true}}
        $id=$item.Id;$oldMedia=$item.MediaPath
        $oldEntry=[IO.File]::ReadAllText((Join-Path $directory.FullName 'item.json'))|ConvertFrom-Json
        break
      }
    }
    $existed=[bool]$id
    if(-not $id){$id=[guid]::NewGuid().ToString('N')}
    $directory=Get-DynamicWallpaperDirectory $StateRoot $id
    Ensure-DreamSkinManagedDirectory -Path $directory -Root $StateRoot
    $name=$Title;if($name.Length -gt 120){$name=$name.Substring(0,120)}
    if($oldEntry){$name=$oldEntry.name}
    $name=Assert-DynamicWallpaperName $name
    $extension=$file.Extension.ToLowerInvariant()
    $entry=[ordered]@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name=$name;kind=$Kind;mediaFile=('wallpaper'+$extension);thumbnailFile='thumbnail.png';size=$file.Length;sha256=$hash;importedAtUtc=[datetime]::UtcNow.ToString('o');sources=@('WallpaperEngine');storage='SteamReference';sourcePath=$file.FullName}
    if($oldEntry){
      $entry.importedAtUtc=$oldEntry.importedAtUtc
      foreach($key in @('previewLevel','transparency')){if($oldEntry.PSObject.Properties[$key]){$entry[$key]=$oldEntry.$key}}
    }
    $null=New-DynamicWallpaperThumbnail $Media $Kind (Join-Path $directory 'thumbnail.png')
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $directory 'item.json') -Content ($entry|ConvertTo-Json)
    foreach($record in $localRecords){
      $localEntry=[IO.File]::ReadAllText($record)|ConvertFrom-Json
      $localEntry.sources=@('Local')
      Write-DreamSkinUtf8FileAtomically -Path $record -Content ($localEntry|ConvertTo-Json)
    }
    if($oldMedia){Assert-DreamSkinNoReparseComponents -Path $oldMedia;Remove-Item -LiteralPath $oldMedia -Force}
    [pscustomobject]@{Item=(Get-DynamicWallpaperItem $StateRoot $id);AlreadyExists=$existed}
  }
}

function Import-DynamicWallpaperEngine {
  param([string[]]$Roots,[string]$StateRoot,[scriptblock]$Report)
  if(-not $Roots){$Roots=@(Get-DynamicWallpaperEngineRoots)}
  $result=[pscustomobject]@{Imported=0;Existing=0;Skipped=0;Failed=0;Details=@();SelectedId=$null;Roots=@($Roots)}
  $visited=@{}
  foreach($root in $Roots|Sort-Object -Unique){
    foreach($directory in Get-DynamicWallpaperEngineProjects $root -OnError {param($path,$message);$result.Failed++;$result.Details+=($path+'：'+$message)}){
      if($visited.ContainsKey($directory.FullName)){continue};$visited[$directory.FullName]=$true
      $label=$directory.Name
      try{
        Assert-DreamSkinNoReparseComponents -Path $directory.FullName
        $metadata=Join-Path $directory.FullName 'project.json'
        if(-not (Test-Path -LiteralPath $metadata -PathType Leaf)){continue}
        Assert-DreamSkinNoReparseComponents -Path $metadata
        if((Get-Item -LiteralPath $metadata).Length -gt 1MB){throw '项目描述文件过大。'}
        $project=[IO.File]::ReadAllText($metadata)|ConvertFrom-Json -ErrorAction Stop
        if($project.title){$label=[string]$project.title}
        if([string]$project.type -notin @('video','image')){
          $result.Skipped++;$result.Details+=($label+'：不支持 '+$project.type+' 类型，需要 Wallpaper Engine 渲染。');continue
        }
        $relative=[string]$project.file
        if(-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')){throw '媒体路径无效。'}
        $media=[IO.Path]::GetFullPath((Join-Path $directory.FullName $relative))
        if(-not $media.StartsWith($directory.FullName+'\',[StringComparison]::OrdinalIgnoreCase)){throw '媒体路径越出项目目录。'}
        Assert-DreamSkinNoReparseComponents -Path $media
        if(-not (Test-Path -LiteralPath $media -PathType Leaf)){throw '项目媒体文件不存在。'}
        $kind='Image';if($project.type -eq 'video'){$kind='Video'}
        if($Report){& $Report ('正在导入：'+$label)}
        $import=Import-DynamicSteamReference -Media $media -Kind $kind -StateRoot $StateRoot -Title $label
        $result.SelectedId=$import.Item.Id
        if($import.AlreadyExists){$result.Existing++}else{
          $result.Imported++
          try{$null=Rename-DynamicWallpaper $StateRoot $import.Item.Id $label}catch{}
        }
      }catch{$result.Failed++;$result.Details+=($label+'：'+$_.Exception.Message)}
    }
  }
  return $result
}
