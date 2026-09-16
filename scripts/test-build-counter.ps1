#requires -Version 7.0
[CmdletBinding()]
param([string]$Generator = 'Visual Studio 18 2026', [switch]$KeepFixture)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$fixture = Join-Path $repository ('out\build-counter-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$build = Join-Path $fixture 'build'
$output = Join-Path $fixture 'output'
$statePath = Join-Path $source '.build-state\counter.json'
$passed = 0
$complete = $false
New-Item -ItemType Directory -Path $source -Force | Out-Null
function Assert-Check([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Write-Source([int]$Value) {
    [IO.File]::WriteAllText((Join-Path $source 'probe.cpp'), "extern `"C`" __declspec(dllexport) int probe() { return $Value; }`n")
}
function Write-Version([string]$Value) {
    @{extensionVersion=$Value} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'metadata.json') -Encoding utf8NoBOM
}
function Configure([string]$Tree) {
    $log = Join-Path $fixture ((Split-Path -Leaf $Tree) + '-configure.log')
    & cmake -S $source -B $Tree -G $Generator -A x64 *> $log
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 45; throw 'Fixture CMake configure failed' }
}
function Build([string]$Tree, [string]$Label, [bool]$ExpectFailure = $false, [switch]$Clean) {
    $log = Join-Path $fixture ($Label + '.log')
    $arguments = @('--build', $Tree, '--config', 'Release', '--parallel', '2')
    if ($Clean) { $arguments += '--clean-first' }
    & cmake @arguments *> $log
    if (($LASTEXITCODE -ne 0) -ne $ExpectFailure) { Get-Content -LiteralPath $log -Tail 55; throw "Unexpected build result: $Label" }
}
function Snapshot([string]$Tree) {
    $dll = Join-Path $Tree 'Release\ICompression.dll'
    return @((Get-FileHash -LiteralPath $dll).Hash, (Get-FileHash -LiteralPath "$dll.build.json").Hash,
        (Get-FileHash -LiteralPath $statePath).Hash, [IO.File]::GetLastWriteTimeUtc($dll).Ticks.ToString()) -join '|'
}
function Verify([string]$Tree, [string]$Version, [string]$Label) {
    $dll = Join-Path $Tree 'Release\ICompression.dll'
    $receipt = Get-Content -Raw -LiteralPath "$dll.build.json" | ConvertFrom-Json
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($dll)
    Assert-Check ($info.FileVersion -ceq $Version -and $info.ProductVersion -ceq $Version) "$Label DLL version mismatch"
    Assert-Check ($receipt.version -ceq $Version -and $receipt.base_version -ceq ($Version.Split('.')[0..2] -join '.') -and $receipt.build_number -eq [int]$Version.Split('.')[3]) "$Label receipt version mismatch"
    $hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    Assert-Check ($receipt.sha256 -ceq $hash -and $receipt.configuration -ceq 'Release') "$Label receipt hash/config mismatch"
    Assert-Check ($receipt.source_revision -match '^[0-9a-f]{40}$' -and $receipt.source_has_local_changes -is [bool] -and $receipt.cxx_compiler -and $receipt.generator) "$Label missing provenance"
    Assert-Check ((Get-FileHash -LiteralPath (Join-Path $output 'ICompression.dll')).Hash -ceq $hash) "$Label copied DLL mismatch"
    Assert-Check ((Get-FileHash -LiteralPath (Join-Path $output 'ICompression.dll.build.json')).Hash -ceq (Get-FileHash -LiteralPath "$dll.build.json").Hash) "$Label copied receipt mismatch"
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json -AsHashtable
    Assert-Check ($state.last_builds[$receipt.base_version] -eq $receipt.build_number) "$Label persistent counter mismatch"
    $script:passed++
    Write-Output "PASS $Label ($Version)"
}
try {
    Copy-Item -LiteralPath (Join-Path $repository 'src\native\ICompression_version.rc') -Destination (Join-Path $source 'version.rc')
    Copy-Item -LiteralPath (Join-Path $repository 'src\native\ICompression_version.h.in') -Destination $source
    $cmakeText = @'
cmake_minimum_required(VERSION 3.21)
project(CounterProbe LANGUAGES CXX RC)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" metadata)
string(JSON IC_EXTENSION_VERSION GET "${metadata}" extensionVersion)
string(REPLACE "." ";" version_parts "${IC_EXTENSION_VERSION}")
list(GET version_parts 0 IC_VERSION_PROJECT)
list(GET version_parts 1 IC_VERSION_FIRST)
list(GET version_parts 2 IC_VERSION_SECOND)
list(GET version_parts 3 IC_VERSION_BUILD)
configure_file(ICompression_version.h.in ICompression_version.h @ONLY)
add_library(ICompression SHARED probe.cpp version.rc)
target_include_directories(ICompression PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
include("@REPOSITORY@/src/build-counter.cmake")
ic_enable_build_counter(ICompression
  METADATA "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
  STATE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.build-state"
  SOURCE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  OUTPUT_DIRECTORY "@OUTPUT@")
'@
    $cmakeText.Replace('@REPOSITORY@', $repository.Replace('\','/')).Replace('@OUTPUT@',$output.Replace('\','/')) |
        Set-Content -LiteralPath (Join-Path $source 'CMakeLists.txt') -Encoding utf8NoBOM
    Write-Version '1.0.3.0'; Write-Source 1; Configure $build
    Build $build 'first'; Verify $build '1.0.3.1' 'First successful build'
    $before = Snapshot $build
    Build $build 'no-op'
    Assert-Check ((Snapshot $build) -ceq $before) 'No-op build changed the DLL, receipt, or counter'
    $passed++; Write-Output 'PASS No-op build does not count'
    Write-Source 2; Build $build 'changed-source'; Verify $build '1.0.3.2' 'Changed source'
    $before = Snapshot $build
    [IO.File]::WriteAllText((Join-Path $source 'probe.cpp'), 'this is deliberately invalid C++')
    Build $build 'failed-compile' $true
    Assert-Check ((Snapshot $build) -ceq $before) 'Failed compilation changed the DLL, receipt, or counter'
    $passed++; Write-Output 'PASS Failed compilation does not count'
    Write-Source 3; Build $build 'fixed-compile'; Verify $build '1.0.3.3' 'Fixed compilation'
    $otherBuild = Join-Path $fixture 'build-other'
    Configure $otherBuild; Build $otherBuild 'other-tree'; Verify $otherBuild '1.0.3.4' 'Another build directory shares counter'
    Build $build 'clean-first' $false -Clean; Verify $build '1.0.3.5' 'Clean rebuild preserves counter'
    Write-Version '1.0.4.99'; Build $build 'new-base'; Verify $build '1.0.4.1' 'Functional version change resets count'
    Write-Source 4; Build $build 'new-base-second'; Verify $build '1.0.4.2' 'New base second build'
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json -AsHashtable
    Assert-Check ($state.last_builds['1.0.3'] -eq 5 -and $state.last_builds['1.0.4'] -eq 2) 'Counter lost prior base history'
    $savedState = [IO.File]::ReadAllText($statePath)
    $before = Snapshot $build
    $updater = Join-Path $repository 'scripts\update-build-counter.ps1'
    $updateArgs = @('-NoProfile', '-File', $updater, '-Binary', (Join-Path $build 'Release\ICompression.dll'),
        '-MetadataPath', (Join-Path $source 'metadata.json'), '-StateDirectory', (Split-Path -Parent $statePath),
        '-SourceDirectory', $source, '-OutputDirectory', $output)
    try {
        [IO.File]::Delete($statePath)
        & pwsh @updateArgs *> (Join-Path $fixture 'missing-state.log')
        Assert-Check ($LASTEXITCODE -ne 0) 'Missing state was silently reset despite existing receipts'
        Assert-Check (!(Test-Path -LiteralPath $statePath)) 'Missing state was silently recreated'
    } finally { [IO.File]::WriteAllText($statePath, $savedState) }
    Assert-Check ((Snapshot $build) -ceq $before) 'Missing-state failure changed the completed artifact'
    $passed++; Write-Output 'PASS Lost counter state fails without reusing a build number'
    try {
        [IO.File]::WriteAllText($statePath, 'invalid JSON')
        & pwsh @updateArgs *> (Join-Path $fixture 'invalid-state.log')
        Assert-Check ($LASTEXITCODE -ne 0) 'Invalid state was silently reset'
    } finally { [IO.File]::WriteAllText($statePath, $savedState) }
    Assert-Check ((Snapshot $build) -ceq $before) 'Invalid-state failure changed the completed artifact'
    $passed++; Write-Output 'PASS Corrupt state fails without changing the DLL'
    $complete = $true
    Write-Output "Build counter checks: $passed passed"
} finally {
    if ($complete -and !$KeepFixture) {
        $full = [IO.Path]::GetFullPath($fixture)
        $allowed = [IO.Path]::GetFullPath((Join-Path $repository 'out')) + [IO.Path]::DirectorySeparatorChar
        if (!$full.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
        Remove-Item -LiteralPath $full -Recurse -Force
    } else { Write-Output "Build counter fixture: $fixture" }
}
