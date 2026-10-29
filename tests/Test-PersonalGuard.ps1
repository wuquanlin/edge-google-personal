$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$source=Join-Path $workspace 'EdgeGooglePersonal\Guard.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) {throw ($errors | Out-String)}
foreach($name in @('Save-Json','Get-ExtensionState')) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('personal-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$originalLocalAppData=$env:LOCALAPPDATA
$results=[Collections.Generic.List[string]]::new()
try {
    $InstallDir=$fixture
    $requestPath=Join-Path $fixture 'request.json'
    Save-Json -Path $requestPath -Data ([pscustomobject]@{id='one';text='Unicode test'})
    Save-Json -Path $requestPath -Data ([pscustomobject]@{id='two';text='second'})
    if ((Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json).id -ne 'two') {throw 'Request replacement failed'}
    $raw=[IO.File]::ReadAllBytes($requestPath)
    if ($raw[0] -ne 123) {throw 'JSON must be UTF8 without a BOM'}
    if (@(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp').Count -ne 0) {throw 'Temporary file leak'}
    $results.Add('PASS: atomic JSON request replacement, UTF-8 without BOM, no temporary-file leak')
    $env:LOCALAPPDATA=$fixture
    $config=[pscustomobject]@{Profile='Profile 1';ExtensionId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}
    if ((Get-ExtensionState $config) -ne 'unknown-profile') {throw 'Missing-profile detection failed'}
    $profileDir=Join-Path $fixture 'Microsoft\Edge\User Data\Profile 1'
    New-Item -ItemType Directory -Path $profileDir | Out-Null
    $secure=Join-Path $profileDir 'Secure Preferences'
    Save-Json -Path $secure -Data @{extensions=@{settings=@{}}}
    if ((Get-ExtensionState $config) -ne 'not-loaded') {throw 'Missing-extension detection failed'}
    Save-Json -Path $secure -Data @{extensions=@{settings=@{aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=@{disable_reasons=@();location=4}}}}
    if ((Get-ExtensionState $config) -ne 'present-not-live-verified') {throw 'Present extension must not imply actual browser verification'}
    Save-Json -Path $secure -Data @{extensions=@{settings=@{aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=@{disable_reasons=@(1)}}}}
    if ((Get-ExtensionState $config) -ne 'disabled') {throw 'Disabled-extension detection failed'}
    $results.Add('PASS: distinguish absent profile, unloaded extension, disabled extension and persisted-but-not-live-verified state')
    $results.Add(('PASS: source parses with PowerShell '+$PSVersionTable.PSVersion.ToString()))
    $results
} finally {
    $env:LOCALAPPDATA=$originalLocalAppData
    # The fixture is a unique test-owned directory, never the live browser profile.
    if (Test-Path -LiteralPath $fixture) {Remove-Item -LiteralPath $fixture -Recurse -Force}
}
