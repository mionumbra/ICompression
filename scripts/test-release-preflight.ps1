#requires -Version 7.0
# Isolated preflight checks. Tool functions are mocked; no compiler, generator,
# GameMaker runner, dependency download, or release packaging is executed.
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$fixture = Join-Path $repository ('out\release-preflight-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$fixtureScripts = Join-Path $source 'scripts'
$extensionDir = Join-Path $source 'project\extensions\ICompression'
New-Item -ItemType Directory -Path $fixtureScripts, $extensionDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release.ps1') -Destination $fixtureScripts
Copy-Item -LiteralPath (Join-Path $repository 'config.json') -Destination $source
$extensionPath = Join-Path $extensionDir 'ICompression.yy'
$fixtureRelease = Join-Path $fixtureScripts 'release.ps1'
$global:ICReleaseTestState = @{}
$global:ICReleaseTestState.mockWorkspace = $fixture
$global:ICReleaseTestState.mockExtgen = 'extgen v1.d8c68bd'
$global:ICReleaseTestState.mockExtgenExit = 0
$global:ICReleaseTestState.mockCmake = 'cmake version 4.4.3'
$global:ICReleaseTestState.mockCmakeExit = 0
$global:ICReleaseTestState.generationCalls = 0
function git {
    $global:LASTEXITCODE = 0
    if ($args -contains '--show-toplevel') { return $global:ICReleaseTestState.mockWorkspace }
    return 'git version 2.50.0.windows.1'
}
function extgen {
    $global:LASTEXITCODE = 0
    if ($args -contains '--help') { $global:LASTEXITCODE = $global:ICReleaseTestState.mockExtgenExit; return $global:ICReleaseTestState.mockExtgen }
    $global:ICReleaseTestState.generationCalls++
    throw 'STOP_AFTER_PREFLIGHT'
}
function cmake {
    $global:LASTEXITCODE = $global:ICReleaseTestState.mockCmakeExit
    if ($args -contains '--version') { return $global:ICReleaseTestState.mockCmake }
    if ($args -contains 'capabilities') {
        return '{"generators":[{"name":"Visual Studio 18 2026"},{"name":"Visual Studio 17 2022"}]}'
    }
    throw 'Unexpected build or configure invocation'
}
function gm-cli { $global:LASTEXITCODE = 0; return '2.3.0' }
function Set-FixtureVersion([string]$Value) {
    '{"extensionVersion":"' + $Value + '","files":[]}' |
        Set-Content -LiteralPath $extensionPath -Encoding utf8NoBOM
}
$global:ICReleaseTestState.passed = 0
function Assert-Rejected([string]$Name, [hashtable]$Arguments, [string]$Expected, [bool]$CanGenerate = $false) {
    $before = $global:ICReleaseTestState.generationCalls
    $failure = $null
    try { & $fixtureRelease @Arguments | Out-Null }
    catch { $failure = $_.Exception.Message }
    if (!$failure -or $failure -notlike "*$Expected*") { throw "${Name}: expected '$Expected', received '$failure'" }
    if (!$CanGenerate -and $global:ICReleaseTestState.generationCalls -ne $before) { throw "${Name}: generation ran before validation failed" }
    $global:ICReleaseTestState.passed++
    Write-Output "PASS $Name"
}
try {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($fixtureRelease, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw ($errors | Out-String) }
    Set-FixtureVersion '1.0.3.1'
    Assert-Rejected 'Version mismatch' @{ Version = '1.0.2.1' } 'Version must match'
    Assert-Rejected 'Version path traversal' @{ Version = '..\..\src' } 'Version must match'
    Assert-Rejected 'Empty explicit version' @{ Version = '' } 'Version must match'
    Set-FixtureVersion '1.02.3.1'
    Assert-Rejected 'Malformed metadata version' @{} 'must use project.version1.version2.build'
    Set-FixtureVersion '65536.0.0.0'
    Assert-Rejected 'Windows version overflow' @{} 'at most 65535'
    Set-FixtureVersion '1.0.3'
    Assert-Rejected 'Three version fields rejected' @{} 'must use project.version1.version2.build'
    Set-FixtureVersion '1.0.3.1.2'
    Assert-Rejected 'Five version fields rejected' @{} 'must use project.version1.version2.build'
    Set-FixtureVersion '1.0.3.65536'
    Assert-Rejected 'Fourth version field overflow' @{} 'at most 65535'
    Set-FixtureVersion '1.65536.3.1'
    Assert-Rejected 'Second version field overflow' @{} 'at most 65535'
    Set-FixtureVersion '1.0.65536.1'
    Assert-Rejected 'Third version field overflow' @{} 'at most 65535'
    Set-FixtureVersion '1.0.3.01'
    Assert-Rejected 'Fourth version field leading zero' @{} 'must use project.version1.version2.build'
    Set-FixtureVersion '1.0.3.2'
    Assert-Rejected 'Fourth version field preserved' @{ Version = '1.0.3.2' } 'STOP_AFTER_PREFLIGHT' $true
    Assert-Rejected 'Fourth version field mismatch' @{ Version = '1.0.3.1' } 'Version must match'
    Set-FixtureVersion '65535.65535.65535.65535'
    Assert-Rejected 'All version fields at maximum' @{ Version = '65535.65535.65535.65535' } 'STOP_AFTER_PREFLIGHT' $true
    Set-FixtureVersion '1.0.3.1'
    Assert-Rejected 'Workspace root build directory' @{ BuildDirectory = $fixture } 'Path must be a child'
    Assert-Rejected 'Source root build directory' @{ BuildDirectory = $source } 'must not be the source directory'
    Assert-Rejected 'External build directory' @{ BuildDirectory = (Split-Path -Parent $fixture) } 'Path must be a child'
    Assert-Rejected 'Unconfigured build directory' @{ BuildDirectory = (Join-Path $fixture 'missing') } 'existing configured CMake tree'
    $global:ICReleaseTestState.mockExtgenExit = 5
    Assert-Rejected 'extgen help failure' @{} 'extgen failed (exit 5)'
    $global:ICReleaseTestState.mockExtgenExit = 0
    $global:ICReleaseTestState.mockExtgen = 'extgen v1.unknown'
    Assert-Rejected 'Unsupported extgen' @{} 'Expected extgen'
    $global:ICReleaseTestState.mockExtgen = 'extgen v1.d8c68bd'
    $global:ICReleaseTestState.mockCmake = 'cmake version 4.1.0'
    Assert-Rejected 'VS2026 requires CMake 4.2' @{} 'requires CMake 4.2'
    $global:ICReleaseTestState.mockCmake = 'cmake version 4.4.3'
    $global:ICReleaseTestState.mockCmakeExit = 7
    Assert-Rejected 'Tool version failure' @{} 'cmake failed (exit 7)'
    $global:ICReleaseTestState.mockCmakeExit = 0
    Assert-Rejected 'External GameMaker cache' @{ GameMakerCacheDirectory = (Split-Path -Parent $fixture) } 'Path must be a child'
    Assert-Rejected 'Unsupported generator' @{ Generator = 'Unknown generator' } 'does not support generator'
    Assert-Rejected 'Default version and current tools' @{} 'STOP_AFTER_PREFLIGHT' $true
    $global:ICReleaseTestState.mockExtgen = 'extgen v1.225bddc'
    Assert-Rejected 'Previously verified extgen' @{} 'STOP_AFTER_PREFLIGHT' $true
    $global:ICReleaseTestState.mockExtgen = 'extgen v1.d8c68bd'
    $global:ICReleaseTestState.mockCmake = 'cmake version 3.21.0'
    Assert-Rejected 'VS2022 minimum CMake' @{ Generator = 'Visual Studio 17 2022' } 'STOP_AFTER_PREFLIGHT' $true
    $global:ICReleaseTestState.mockCmake = 'cmake version 4.4.3'
    $siblingBuild = Join-Path $fixture 'build'
    New-Item -ItemType Directory -Path $siblingBuild | Out-Null
    @("CMAKE_HOME_DIRECTORY:INTERNAL=$source", 'CMAKE_GENERATOR:INTERNAL=Visual Studio 18 2026') |
        Set-Content -LiteralPath (Join-Path $siblingBuild 'CMakeCache.txt') -Encoding utf8NoBOM
    Assert-Rejected 'Matching sibling build directory' @{ BuildDirectory = $siblingBuild } 'STOP_AFTER_PREFLIGHT' $true
    @("CMAKE_HOME_DIRECTORY:INTERNAL=$fixture", 'CMAKE_GENERATOR:INTERNAL=Visual Studio 18 2026') |
        Set-Content -LiteralPath (Join-Path $siblingBuild 'CMakeCache.txt') -Encoding utf8NoBOM
    Assert-Rejected 'Mismatched cached source' @{ BuildDirectory = $siblingBuild } 'different source directory'
    Write-Output "Release preflight checks: $($global:ICReleaseTestState.passed) passed"
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $allowedParent = [IO.Path]::GetFullPath((Join-Path $repository 'out')) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedFixture.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
