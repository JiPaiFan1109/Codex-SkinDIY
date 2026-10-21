$ErrorActionPreference='Stop'
$manager=Join-Path $PSScriptRoot '../scripts/skin-manager.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($manager,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Manager does not parse'}
$function=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Confirm-DynamicWallpaperApply'},$true)[0]
. ([scriptblock]::Create($function.Extent.Text))
function Show-DynamicManagerConfirmation {param($Title,$Message,$AcceptText,$Action) & $Action}
function Save-DynamicManagerOpacity {
  $script:events.Add('save')
  if(-not $script:saveFails){$script:savedValue=$script:SkinManager.PendingOpacity.Value;$script:SkinManager.PendingOpacity=$null}
}
function Start-DynamicManagerWork {param($Kind,$Id) $script:events.Add('apply');$script:appliedValue=$script:savedValue}
function Show-DynamicManagerToast {param($Message,$Kind) $script:events.Add('error')}
foreach($fails in @($false,$true)){
  $script:events=[Collections.Generic.List[string]]::new()
  $script:saveFails=$fails;$script:savedValue=50;$script:appliedValue=$null
  $script:SkinManager=@{Selected=@{Id='image-one'};PrepareOnly=$false;Busy=$false;PendingOpacity=@{Id='image-one';Value=73}}
  Confirm-DynamicWallpaperApply
  if($fails){
    if($script:events -contains 'apply'){throw 'Saving failure must block application'}
    if($script:events -notcontains 'error'){throw 'Saving failure must be reported'}
  }else{
    if(($script:events -join ',') -ne 'save,apply'){throw 'Must save the pending slider value before starting apply'}
    if($script:appliedValue -ne 73){throw 'Apply used an old slider value'}
  }
}
'PASS: immediate apply flushes the latest clarity; save failure blocks stale application'
