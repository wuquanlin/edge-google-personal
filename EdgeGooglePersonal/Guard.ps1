#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Install','Request','Check','Uninstall')][string]$Mode='Check')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Keep persistent files beside the source in Documents. MSIX can redirect LocalAppData.
$InstallDir=$PSScriptRoot
$InstalledScript=$PSCommandPath
$TaskName='Codex-EdgeGooglePersonal'
$ConfigPath=Join-Path $InstallDir 'config.json'
$LogPath=Join-Path $InstallDir 'login.log'

function Write-Log([string]$Message) {
    if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null }
    if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 1048576) {
        Move-Item -LiteralPath $LogPath -Destination ($LogPath+'.old') -Force
    }
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'),$Message)
}
function Save-Json([string]$Path,$Data) {
    # The same-volume rename prevents the extension from reading half-written JSON.
    $tempPath=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $replaceBackup=$tempPath+'.bak'
    [IO.File]::WriteAllText($tempPath,($Data | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    try {
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tempPath,$Path,$replaceBackup) }
        else { [IO.File]::Move($tempPath,$Path) }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force }
    }
}
function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw 'Not installed. Run Install.cmd first.' }
    Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
function Get-TaskRoot {
    $service=New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    return $service.GetFolder('\')
}
function Get-GuardTask($Root) {
    try { return $Root.GetTask($TaskName) }
    catch { if ($_.Exception.Message -match '0x80070002') { return $null }; throw }
}
function Assert-OwnedTask($Task) {
    if ($null -ne $Task -and ($Task.Definition.RegistrationInfo.Author -ne 'Codex EdgeGooglePersonal' -or $Task.Definition.Actions.Item(1).Arguments -notlike ('*"'+$InstalledScript+'"*'))) {
        throw 'A task with the same name is not owned by this installation; refusing to change it.'
    }
}
function Get-ExtensionState($Config) {
    $secure=Join-Path $env:LOCALAPPDATA ('Microsoft\Edge\User Data\{0}\Secure Preferences' -f $Config.Profile)
    if (-not (Test-Path -LiteralPath $secure)) { return 'unknown-profile' }
    $prefs=Get-Content -LiteralPath $secure -Raw | ConvertFrom-Json
    $settings=$prefs.PSObject.Properties['extensions']
    if ($null -eq $settings) { return 'not-loaded' }
    $allSettings=$settings.Value.PSObject.Properties['settings']
    if ($null -eq $allSettings) { return 'not-loaded' }
    $entry=$allSettings.Value.PSObject.Properties[$Config.ExtensionId]
    if ($null -eq $entry) { return 'not-loaded' }
    $state=$entry.Value.PSObject.Properties['state']
    $reasons=$entry.Value.PSObject.Properties['disable_reasons']
    if ($null -ne $state -and [int]$state.Value -ne 1) { return 'disabled' }
    if ($null -ne $reasons) {
        $value=$reasons.Value
        if ($value -is [array] -and $value.Count -gt 0) { return 'disabled' }
        if ($value -is [ValueType] -and [int64]$value -ne 0) { return 'disabled' }
    }
    # Persisted state is only a startup diagnostic; the extension does the actual search test.
    return 'present-not-live-verified'
}
function New-Request($Config) {
    $request=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');createdAt=(Get-Date).ToUniversalTime().ToString('o')}
    Save-Json -Path (Join-Path $InstallDir 'Extension\login-request.json') -Data $request
    $extensionState=Get-ExtensionState $Config
    Write-Log "Request=$($request.id); Extension=$extensionState; ActualBrowserVerified=Pending"
    if ($extensionState -eq 'present-not-live-verified') {
        # Start the selected profile without opening a browser window or a settings page.
        Start-Process -FilePath $Config.EdgePath -ArgumentList @('--no-startup-window',('--profile-directory="{0}"' -f $Config.Profile)) -WindowStyle Hidden | Out-Null
        Write-Output 'Verification requested. Open the extension popup for the actual result (normally within one minute while Edge runs).'
    } else {
        Write-Output "Extension state: $extensionState. Load/enable the prepared extension in the selected profile to finish setup."
    }
}

try {
    if ($Mode -eq 'Install') {
        $sourceDir=$PSScriptRoot
        $extensionId=(Get-Content -LiteralPath (Join-Path $sourceDir 'extension-id.txt') -Raw).Trim()
        if ($extensionId -cnotmatch '^[a-p]{32}$') { throw 'Invalid extension ID.' }
        $edgePaths=@((Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'))
        $edgePath=$edgePaths | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
        if (-not $edgePath) { throw 'Microsoft Edge executable not found.' }
        $localState=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Local State') -Raw | ConvertFrom-Json
        $profile=[string]$localState.profile.last_used
        if ([string]::IsNullOrWhiteSpace($profile) -or $profile -match '[\\/:*?"<>|]') { throw 'Cannot determine a safe Edge profile directory.' }
        if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null }
        $config=[pscustomobject]@{Profile=$profile;EdgePath=$edgePath;ExtensionId=$extensionId}
        Save-Json -Path $ConfigPath -Data $config
        $psPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Request' -f $InstalledScript
        $service=New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $root=$service.GetFolder('\')
        Assert-OwnedTask (Get-GuardTask $root)
        $definition=$service.NewTask(0)
        $definition.RegistrationInfo.Author='Codex EdgeGooglePersonal'
        $definition.RegistrationInfo.Description='Request a real default-search verification after this user signs in. Requires the approved Google search guard extension.'
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $definition.Principal.UserId=$sid
        $definition.Principal.LogonType=3
        $definition.Principal.RunLevel=0
        $definition.Settings.Enabled=$true
        $definition.Settings.AllowDemandStart=$true
        $definition.Settings.DisallowStartIfOnBatteries=$false
        $definition.Settings.StopIfGoingOnBatteries=$false
        $definition.Settings.StartWhenAvailable=$true
        $definition.Settings.ExecutionTimeLimit='PT2M'
        $definition.Settings.MultipleInstances=2
        $trigger=$definition.Triggers.Create(9)
        $trigger.UserId=$sid
        $trigger.Delay='PT20S'
        $trigger.Enabled=$true
        $action=$definition.Actions.Create(0)
        $action.Path=$psPath
        $action.Arguments=$arguments
        $action.WorkingDirectory=$InstallDir
        $root.RegisterTaskDefinition($TaskName,$definition,6,$sid,$null,3,$null) | Out-Null
        $registered=Get-GuardTask $root
        if ($null -eq $registered -or $registered.Definition.Actions.Item(1).Arguments -cne $arguments -or -not $registered.Enabled) { throw 'Scheduled task read-back failed.' }
        New-Request $config
        Write-Output ('Ready. Selected Edge profile: '+$profile)
        Write-Output ('ONE-TIME MANUAL STEP: in Edge Extensions, Load unpacked: '+(Join-Path $InstallDir 'Extension'))
        Write-Output 'Approve/enable the extension if Edge asks about changing the search engine. No actual browser verification is claimed yet.'
    } elseif ($Mode -eq 'Request') {
        New-Request (Read-Config)
    } elseif ($Mode -eq 'Check') {
        $config=Read-Config
        $task=Get-GuardTask (Get-TaskRoot)
        [pscustomobject]@{SelectedProfile=$config.Profile;ExtensionId=$config.ExtensionId;ExtensionPersistedState=(Get-ExtensionState $config);StartupRegistered=($null -ne $task -and $task.Enabled);StartupTask=$TaskName;ActualBrowserVerified='Read the extension popup; this script does not infer success from files or registry.';LoadThisFolder=(Join-Path $InstallDir 'Extension')} | ConvertTo-Json
    } else {
        $root=Get-TaskRoot
        $task=Get-GuardTask $root
        Assert-OwnedTask $task
        if ($null -ne $task) { $root.DeleteTask($TaskName,0) }
        if ($null -ne (Get-GuardTask $root)) { throw 'Scheduled task removal failed.' }
        Write-Log 'Startup uninstalled. Remove the browser extension manually to release its Google setting.'
        Write-Output 'Startup uninstalled. Also remove the Google search guard extension in Edge. Files retained.'
    }
    exit 0
} catch {
    try { Write-Log ('ERROR: '+$_.Exception.Message) } catch {}
    Write-Error $_ -ErrorAction Continue
    exit 1
}
