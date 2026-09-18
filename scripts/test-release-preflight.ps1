#requires -Version 7.0
# Isolated preflight checks. Tool functions are mocked; no compiler, generator,
# GameMaker runner, or dependency download is executed. The test gate, staging,
# packaging, and the source seed advance run end-to-end against fixture trees
# inside a temporary workspace, never the real repository.
$ErrorActionPreference = 'Stop'
trap {
    Write-Output ("PREFLIGHT TERMINATING ERROR: " + $_.Exception.ToString())
    Write-Output ("AT: " + $_.InvocationInfo.PositionMessage)
    exit 1
}
Write-Output "pwsh $($PSVersionTable.PSVersion)"
$repository = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$fixture = Join-Path $repository ('out\release-preflight-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$fixtureScripts = Join-Path $source 'scripts'
$extensionDir = Join-Path $source 'project\extensions\ICompression'
New-Item -ItemType Directory -Path $fixtureScripts, $extensionDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release.ps1') -Destination $fixtureScripts
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'validate-package.ps1') -Destination $fixtureScripts
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
$global:ICReleaseTestState.extgenCalls = 0
$global:ICReleaseTestState.cmakeCalls = 0
$global:ICReleaseTestState.allowGeneration = $false
$global:ICReleaseTestState.buildArguments = @()
$global:ICReleaseTestState.mockDllPath = Join-Path $extensionDir 'ICompression.dll'
$global:ICReleaseTestState.mockDllVersion = '1.0.3.2'
$global:ICReleaseTestState.sourceProject = Join-Path $source 'project\ICompression.yyp'
$global:ICReleaseTestState.mockTestOutput = $null
$global:ICReleaseTestState.mockTestExit = 0
$global:ICReleaseTestState.mockLsFiles = ''
$global:ICReleaseTestState.mockSeedFail = $false
$global:ICReleaseTestState.nodeCalls = @()
$global:ICReleaseTestState.resourceSnapshots = @()
$global:ICReleaseTestState.hostMessages = @()
$global:ICReleaseTestState.cycleAtCompress = $null
$global:ICReleaseTestState.counterPath = $null
$global:ICReleaseTestState.mockBuildSync = $true
$global:ICReleaseTestState.gmRunCalls = 0
$global:ICReleaseTestState.tamperStagedFile = $false
$global:ICReleaseTestState.gmRunArgs = @()
$global:ICReleaseTestState.mockYycOutput = $null
$global:ICReleaseTestState.mockYycExit = 0
function git {
    $global:LASTEXITCODE = 0
    if ($args -contains '--show-toplevel') { return $global:ICReleaseTestState.mockWorkspace }
    if ($args -contains 'ls-files') { return $global:ICReleaseTestState.mockLsFiles }
    return 'git version 2.50.0.windows.1'
}
function extgen {
    $global:ICReleaseTestState.extgenCalls++
    $global:LASTEXITCODE = 0
    if ($args -contains '--help') { $global:LASTEXITCODE = $global:ICReleaseTestState.mockExtgenExit; return $global:ICReleaseTestState.mockExtgen }
    $global:ICReleaseTestState.generationCalls++
    if (!$global:ICReleaseTestState.allowGeneration) { throw 'STOP_AFTER_PREFLIGHT' }
}
function cmake {
    $global:ICReleaseTestState.cmakeCalls++
    $global:LASTEXITCODE = $global:ICReleaseTestState.mockCmakeExit
    if ($args -contains '--version') { return $global:ICReleaseTestState.mockCmake }
    if ($args -contains 'capabilities') {
        return '{"generators":[{"name":"Visual Studio 18 2026"},{"name":"Visual Studio 17 2022"}]}'
    }
    if ($global:ICReleaseTestState.allowGeneration) {
        $global:ICReleaseTestState.buildArguments += ,@($args)
        $buildIndex = [System.Array]::IndexOf($args, '--build')
        if ($buildIndex -ge 0) {
            # Simulate the post-build sync: the fresh DLL lands in the build tree.
            $releaseOut = Join-Path $args[$buildIndex + 1] 'Release'
            New-Item -ItemType Directory -Path $releaseOut -Force | Out-Null
            if ($global:ICReleaseTestState.mockBuildSync) {
                Copy-Item -LiteralPath $global:ICReleaseTestState.mockDllPath -Destination (Join-Path $releaseOut 'ICompression.dll')
            }
            else {
                [IO.File]::WriteAllBytes((Join-Path $releaseOut 'ICompression.dll'), [byte[]]::new(256))
            }
        }
        return
    }
    throw 'Unexpected build or configure invocation'
}
function gm-cli {
    if ($args -contains 'run') {
        $global:ICReleaseTestState.gmRunCalls++
        $global:ICReleaseTestState.gmRunArgs += ,@($args)
        if ($null -eq $global:ICReleaseTestState.mockTestOutput) {
            $global:LASTEXITCODE = 0
            throw 'STOP_AFTER_ARTIFACT_VALIDATION'
        }
        if ($args -contains '--runtime=native') {
            $global:LASTEXITCODE = $global:ICReleaseTestState.mockYycExit
            if ($null -ne $global:ICReleaseTestState.mockYycOutput) { return $global:ICReleaseTestState.mockYycOutput }
            return $global:ICReleaseTestState.mockTestOutput
        }
        $global:LASTEXITCODE = $global:ICReleaseTestState.mockTestExit
        return $global:ICReleaseTestState.mockTestOutput
    }
    $global:LASTEXITCODE = 0
    return '2.3.0'
}
function node {
    if (@($args).Count -and $args[0] -is [string] -and $args[0] -like '*set-extension-version.cjs') {
        # Stand-in for the ResourceTool MCP client: record the call, snapshot
        # the staged project copy, then persist the requested version exactly
        # like the verified read-back in set-extension-version.cjs expects.
        $mcpProject = $null
        $mcpVersion = $null
        for ($i = 1; $i -lt $args.Count - 1; $i++) {
            if ($args[$i] -eq '--project') { $mcpProject = $args[$i + 1] }
            if ($args[$i] -eq '--version') { $mcpVersion = $args[$i + 1] }
        }
        $global:ICReleaseTestState.nodeCalls += ,@($mcpProject, $mcpVersion)
        if ($global:ICReleaseTestState.mockSeedFail -and $mcpProject -eq $global:ICReleaseTestState.sourceProject) {
            $global:LASTEXITCODE = 9
            return 'simulated ResourceTool failure'
        }
        $projectDir = Split-Path -Parent $mcpProject
        $bundleRoot = Split-Path -Parent $projectDir
        if ([IO.Path]::GetFileName($bundleRoot) -like 'release-resources-*') {
            $global:ICReleaseTestState.resourceSnapshots += ,@(
                Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Force |
                    ForEach-Object { $_.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/') })
        }
        $target = Join-Path $projectDir 'extensions\ICompression\ICompression.yy'
        $text = Get-Content -Raw -LiteralPath $target
        if ($text -notmatch '"extensionVersion"\s*:\s*"[^"]*"') {
            $global:LASTEXITCODE = 4
            return 'extensionVersion not found'
        }
        $updated = $text -replace '"extensionVersion"\s*:\s*"[^"]*"', ('"extensionVersion":"' + $mcpVersion + '"')
        Set-Content -LiteralPath $target -Value $updated -Encoding utf8NoBOM -NoNewline
        $global:LASTEXITCODE = 0
        return "Staged extension version: $mcpVersion"
    }
    $global:LASTEXITCODE = 0
    if ($args -contains '--version') { return 'v24.0.0' }
    throw 'Unexpected MCP client invocation in preflight checks'
}
# Pre-load the Archive module: importing it at mock-call time would replace
# this script-scope function and let later calls through to the real cmdlet.
Import-Module Microsoft.PowerShell.Archive
function Compress-Archive {
    [CmdletBinding()]
    param([string]$Path, [string]$DestinationPath, [string]$CompressionLevel)
    # Capture the cycle count at archive time to pin the reset's ordering.
    $global:ICReleaseTestState.cycleAtCompress = $null
    if ($global:ICReleaseTestState.counterPath -and (Test-Path -LiteralPath $global:ICReleaseTestState.counterPath -PathType Leaf)) {
        $global:ICReleaseTestState.cycleAtCompress = ([IO.File]::ReadAllText($global:ICReleaseTestState.counterPath) | ConvertFrom-Json).cycle_builds
    }
    if ($global:ICReleaseTestState.tamperStagedFile) {
        # Flip one staged byte after SHA256SUMS.txt was written, so the archived
        # bytes no longer match the manifest the validator re-checks.
        $tamperTarget = Join-Path (Split-Path -Parent $Path) 'CHANGELOG.md'
        $tamperBytes = [IO.File]::ReadAllBytes($tamperTarget)
        $tamperBytes[0] = $tamperBytes[0] -bxor 0xFF
        [IO.File]::WriteAllBytes($tamperTarget, $tamperBytes)
    }
    Microsoft.PowerShell.Archive\Compress-Archive @PSBoundParameters
}
function Write-Host {
    param([Parameter(Position = 0, ValueFromPipeline)][object]$Object, [object]$ForegroundColor, [object]$BackgroundColor, [switch]$NoNewline)
    $global:ICReleaseTestState.hostMessages += ,[string]$Object
}
function Get-Item {
    [CmdletBinding()]
    param([string]$LiteralPath, [switch]$Force)
    if ($LiteralPath -eq $global:ICReleaseTestState.mockDllPath) {
        return [pscustomobject]@{
            Attributes = [IO.FileAttributes]::Normal
            VersionInfo = [pscustomobject]@{ FileVersion = $global:ICReleaseTestState.mockDllVersion; ProductVersion = $global:ICReleaseTestState.mockDllVersion }
        }
    }
    Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}
function Set-FixtureArtifact([string]$Value) {
    $global:ICReleaseTestState.mockDllVersion = $Value
    $bytes = [byte[]]::new(256)
    [BitConverter]::GetBytes([int]128).CopyTo($bytes, 0x3c)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes, 132)
    [IO.File]::WriteAllBytes($global:ICReleaseTestState.mockDllPath, $bytes)
    [ordered]@{
        schema_version = 1; base_version = ($Value.Split('.')[0..2] -join '.'); version = $Value
        build_number = [int]$Value.Split('.')[3]
        sha256 = (Get-FileHash -LiteralPath $global:ICReleaseTestState.mockDllPath -Algorithm SHA256).Hash
        configuration = 'Release'; source_revision = ('a' * 40); source_has_local_changes = $false
        built_at_utc = '2026-09-15T00:00:00Z'; cxx_compiler = 'MSVC test'; generator = 'Visual Studio 18 2026'
    } | ConvertTo-Json | Set-Content -LiteralPath ($global:ICReleaseTestState.mockDllPath + '.build.json') -Encoding utf8NoBOM
}
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
function Assert-ReleaseSucceeded([string]$Name, [hashtable]$Arguments) {
    $failure = $null
    try { & $fixtureRelease @Arguments | Out-Null }
    catch { $failure = $_.Exception.Message }
    if ($failure) { throw "${Name}: expected success, received '$failure'" }
    $global:ICReleaseTestState.passed++
    Write-Output "PASS $Name"
}
function Add-Pass([string]$Name) {
    $global:ICReleaseTestState.passed++
    Write-Output "PASS $Name"
}
function Get-FixtureCounter {
    return [IO.File]::ReadAllText($global:ICReleaseTestState.counterPath) | ConvertFrom-Json -AsHashtable
}
function Get-FixtureCycle { return [int](Get-FixtureCounter).cycle_builds }
function Set-FixtureCycle([int]$Value) {
    $counter = Get-FixtureCounter
    $counter.cycle_builds = $Value
    [IO.File]::WriteAllText($global:ICReleaseTestState.counterPath, ($counter | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}
function Add-FixtureTree {
    # Complete source-tree stand-in for the pipeline's second half: release
    # documents, project resources, credential/local-settings files that must
    # never ship, and the dependency license sources staged from _deps.
    'readme' | Set-Content -LiteralPath (Join-Path $source 'README.md')
    'license' | Set-Content -LiteralPath (Join-Path $source 'LICENSE')
    'changelog' | Set-Content -LiteralPath (Join-Path $source 'CHANGELOG.md')
    'zlib bzip2 zstd lz4 xz libarchive' | Set-Content -LiteralPath (Join-Path $source 'THIRD_PARTY_NOTICES.md')
    'ext stub' | Set-Content -LiteralPath (Join-Path $extensionDir 'ICompression.ext')
    New-Item -ItemType Directory -Path (Join-Path $source 'project\scripts\ICompression_API'), (Join-Path $source 'project\scripts\ExtensionCore_api'),
        (Join-Path $source 'project\scripts\ExtensionCore_exports'), (Join-Path $source 'project\notes\ExtensionCore_readme'),
        (Join-Path $source 'project\extensions\ExtensionCore\AndroidSource\Java'), (Join-Path $source 'third_party') -Force | Out-Null
    '{"resources":[]}' | Set-Content -LiteralPath $global:ICReleaseTestState.sourceProject
    'api yy' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ICompression_API\ICompression_API.yy')
    'api gml' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ICompression_API\ICompression_API.gml')
    'core ext yy' | Set-Content -LiteralPath (Join-Path $source 'project\extensions\ExtensionCore\ExtensionCore.yy')
    'core utils java' | Set-Content -LiteralPath (Join-Path $source 'project\extensions\ExtensionCore\AndroidSource\Java\GMExtUtils.java')
    'core wire java' | Set-Content -LiteralPath (Join-Path $source 'project\extensions\ExtensionCore\AndroidSource\Java\GMExtWire.java')
    'core api yy' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ExtensionCore_api\ExtensionCore_api.yy')
    'core api gml' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ExtensionCore_api\ExtensionCore_api.gml')
    'core exports yy' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ExtensionCore_exports\ExtensionCore_exports.yy')
    'core exports gml' | Set-Content -LiteralPath (Join-Path $source 'project\scripts\ExtensionCore_exports\ExtensionCore_exports.gml')
    'core readme yy' | Set-Content -LiteralPath (Join-Path $source 'project\notes\ExtensionCore_readme\ExtensionCore_readme.yy')
    'core readme md' | Set-Content -LiteralPath (Join-Path $source 'project\notes\ExtensionCore_readme\ExtensionCore_readme.md')
    'apache-2.0' | Set-Content -LiteralPath (Join-Path $source 'third_party\extension-core-LICENSE.txt')
    New-Item -ItemType Directory -Path (Join-Path $source 'project\.gmcache\license') -Force | Out-Null
    'secret-license' | Set-Content -LiteralPath (Join-Path $source 'project\.gmcache\license\gm.key')
    '{"mcpServers":{}}' | Set-Content -LiteralPath (Join-Path $source 'project\.mcp.json')
    'agent notes' | Set-Content -LiteralPath (Join-Path $source 'project\AGENTS.md')
    'claude notes' | Set-Content -LiteralPath (Join-Path $source 'project\CLAUDE.md')
    '{"options":{}}' | Set-Content -LiteralPath (Join-Path $source 'project\gm-options.json')
    $deps = [ordered]@{
        'zlib-src\LICENSE' = 'zlib'; 'bzip2-src\LICENSE' = 'bzip2'; 'zstd-src\LICENSE' = 'zstd'
        'lz4-src\lib\LICENSE' = 'lz4'; 'xz-src\COPYING' = 'xz'; 'xz-src\COPYING.0BSD' = '0bsd'
        'libarchive-src\COPYING' = 'libarchive'
        'libarchive-src\libarchive\archive_read_support_filter_compress.c' = 'reader'
        'libarchive-src\libarchive\archive_write_add_filter_compress.c' = 'writer'
    }
    foreach ($relative in $deps.Keys) {
        $licenseSource = Join-Path $packageBuild (Join-Path '_deps' $relative)
        New-Item -ItemType Directory -Path (Split-Path -Parent $licenseSource) -Force | Out-Null
        $deps[$relative] | Set-Content -LiteralPath $licenseSource
    }
    # Build counter state with a nonzero cycle count for the release to reset.
    $global:ICReleaseTestState.counterPath = Join-Path $source '.build-state\counter.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $global:ICReleaseTestState.counterPath) -Force | Out-Null
    [IO.File]::WriteAllText($global:ICReleaseTestState.counterPath,
        (@{ schema_version = 1; last_builds = @{ '1.0.3' = 8 }; artifacts = @{}; cycle_builds = 7 } | ConvertTo-Json -Depth 20),
        [Text.UTF8Encoding]::new($false))
    # Toolchain stand-in for the opt-in YYC pass (only existence and the file
    # name are checked; it is never executed).
    New-Item -ItemType Directory -Path (Join-Path $fixture 'vs') -Force | Out-Null
    'rem fixture toolchain' | Set-Content -LiteralPath (Join-Path $fixture 'vs\VsDevCmd.bat')
    # Mach-O stand-ins for the optional macOS binary: a valid fat/universal
    # magic, a wrong-name twin, and an MZ (non-Mach-O) impostor.
    New-Item -ItemType Directory -Path (Join-Path $fixture 'macho'), (Join-Path $fixture 'bad') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $fixture 'macho\libICompression.dylib'), ([byte[]](0xCA, 0xFE, 0xBA, 0xBE) + [byte[]]::new(60)))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'macho\foo.dylib'), ([byte[]](0xCA, 0xFE, 0xBA, 0xBE) + [byte[]]::new(60)))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'bad\libICompression.dylib'), ([byte[]](0x4D, 0x5A, 0x90, 0x00) + [byte[]]::new(60)))
    # ELF stand-ins for the optional Linux binary: a valid x86-64 shared-object
    # header, a wrong-name twin, and an MZ (non-ELF) impostor.
    New-Item -ItemType Directory -Path (Join-Path $fixture 'elf'), (Join-Path $fixture 'badelf') -Force | Out-Null
    $elfHeader = [byte[]](0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x3E, 0x00)
    [IO.File]::WriteAllBytes((Join-Path $fixture 'elf\libICompression.so'), ($elfHeader + [byte[]]::new(44)))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'elf\foo.so'), ($elfHeader + [byte[]]::new(44)))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'badelf\libICompression.so'), ([byte[]](0x4D, 0x5A, 0x90, 0x00) + [byte[]]::new(60)))
    # Tracked-file view offered to the release filter, including files that
    # must be excluded from the ResourceTool staging copy.
    $global:ICReleaseTestState.mockLsFiles = (@(
        'project/ICompression.yyp'
        'project/extensions/ICompression/ICompression.yy'
        'project/extensions/ICompression/ICompression.ext'
        'project/extensions/ICompression/ICompression.dll'
        'project/extensions/ExtensionCore/ExtensionCore.yy'
        'project/extensions/ExtensionCore/AndroidSource/Java/GMExtUtils.java'
        'project/extensions/ExtensionCore/AndroidSource/Java/GMExtWire.java'
        'project/scripts/ICompression_API/ICompression_API.yy'
        'project/scripts/ICompression_API/ICompression_API.gml'
        'project/scripts/ExtensionCore_api/ExtensionCore_api.yy'
        'project/scripts/ExtensionCore_api/ExtensionCore_api.gml'
        'project/scripts/ExtensionCore_exports/ExtensionCore_exports.yy'
        'project/scripts/ExtensionCore_exports/ExtensionCore_exports.gml'
        'project/notes/ExtensionCore_readme/ExtensionCore_readme.yy'
        'project/notes/ExtensionCore_readme/ExtensionCore_readme.md'
        'project/.gmcache/license/gm.key'
        'project/.mcp.json'
        'project/AGENTS.md'
        'project/CLAUDE.md'
        'project/gm-options.json'
    ) -join "`n")
}
try {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($fixtureRelease, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw ($errors | Out-String) }
    Set-FixtureVersion '1.0.3.1'
    Assert-Rejected 'Version mismatch' @{ Version = '1.0.2.1' } 'Version must match'
    Assert-Rejected 'Version path traversal' @{ Version = '..\..\src' } 'must use project.version1.version2.build'
    Assert-Rejected 'Empty explicit version' @{ Version = '' } 'must use project.version1.version2.build'
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
    Assert-Rejected 'Fourth version checked only after compilation' @{ Version = '1.0.3.1' } 'STOP_AFTER_PREFLIGHT' $true
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
    # Exercise OnlyPackage without real tools or loading any native code. The
    # synthetic PE and mocked VersionInfo stand in for a successfully built DLL.
    $packageBuild = Join-Path $source 'out\release-build'
    New-Item -ItemType Directory -Path $packageBuild -Force | Out-Null
    @("CMAKE_HOME_DIRECTORY:INTERNAL=$source", 'CMAKE_GENERATOR:INTERNAL=Visual Studio 18 2026') |
        Set-Content -LiteralPath (Join-Path $packageBuild 'CMakeCache.txt') -Encoding utf8NoBOM
    Set-FixtureVersion '1.0.3.1'
    Set-FixtureArtifact '1.0.3.8'
    $receiptPath = $global:ICReleaseTestState.mockDllPath + '.build.json'
    $receiptHash = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    $beforeExtgen = $global:ICReleaseTestState.extgenCalls
    $beforeCmake = $global:ICReleaseTestState.cmakeCalls
    $global:ICReleaseTestState.mockExtgenExit = 5
    $global:ICReleaseTestState.mockCmakeExit = 7
    Assert-Rejected 'OnlyPackage uses compiled version above metadata seed' @{ OnlyPackage = $true; Version = '1.0.3.8' } 'STOP_AFTER_ARTIFACT_VALIDATION'
    if ($beforeExtgen -ne $global:ICReleaseTestState.extgenCalls -or $beforeCmake -ne $global:ICReleaseTestState.cmakeCalls) {
        throw 'OnlyPackage called extgen or cmake'
    }
    if ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -cne $receiptHash) { throw 'OnlyPackage modified the build receipt' }
    Assert-Rejected 'OnlyPackage rejects requested build mismatch' @{ OnlyPackage = $true; Version = '1.0.3.1' } 'Version must match compiled DLL'
    $global:ICReleaseTestState.mockExtgenExit = 0
    $global:ICReleaseTestState.mockCmakeExit = 0
    $invalidReceipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    $invalidReceipt.sha256 = '0' * 64
    $invalidReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    Assert-Rejected 'OnlyPackage rejects receipt hash mismatch' @{ OnlyPackage = $true } 'SHA-256 does not match'
    Set-FixtureArtifact '1.0.3.8'
    $global:ICReleaseTestState.mockDllVersion = '1.0.3.9'
    Assert-Rejected 'OnlyPackage rejects DLL version mismatch' @{ OnlyPackage = $true } 'DLL version does not match its build receipt'
    Set-FixtureArtifact '1.0.3.8'
    Set-FixtureVersion '1.0.4.1'
    Assert-Rejected 'OnlyPackage rejects old version base' @{ OnlyPackage = $true } 'version/base is inconsistent'
    Set-FixtureVersion '1.0.3.1'
    $invalidReceipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    $invalidReceipt.configuration = 'Debug'
    $invalidReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    Assert-Rejected 'OnlyPackage rejects Debug artifacts' @{ OnlyPackage = $true } 'Only a Release DLL'
    Set-FixtureArtifact '1.0.3.8'
    $invalidReceipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    $invalidReceipt.source_revision = 'unknown'
    $invalidReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    Assert-Rejected 'OnlyPackage requires source provenance' @{ OnlyPackage = $true } 'source/compiler provenance'
    Remove-Item -LiteralPath $receiptPath
    Assert-Rejected 'OnlyPackage requires a build receipt' @{ OnlyPackage = $true } 'DLL build receipt is missing'
    Set-FixtureArtifact '1.0.3.8'
    $marker = Join-Path $packageBuild 'cache-marker.txt'
    'keep cached dependencies' | Set-Content -LiteralPath $marker
    $global:ICReleaseTestState.allowGeneration = $true
    Assert-Rejected 'Default release keeps incremental build tree' @{ Version = '1.0.3.8' } 'STOP_AFTER_ARTIFACT_VALIDATION' $true
    if (!(Test-Path -LiteralPath $marker)) { throw 'Incremental release deleted its build cache' }
    $buildCommands = @($global:ICReleaseTestState.buildArguments | Where-Object { $_ -contains '--build' })
    if (!$buildCommands.Count -or @($global:ICReleaseTestState.buildArguments | Where-Object { $_ -contains '--clean-first' }).Count) {
        throw 'Release did not use an incremental build'
    }
    $global:ICReleaseTestState.allowGeneration = $false

    # Second half of the pipeline: the real test gate, staging, packaging, and
    # the source seed advance run against a complete fixture tree. The release
    # copy's $root is $source, so nothing here can touch the real repository.
    Add-FixtureTree
    $releaseParent = Join-Path $source 'release'
    $stageName = 'ICompression-1.0.3.8'
    $stageDir = Join-Path $releaseParent $stageName
    $archivePath = "$stageDir.zip"
    $passingLog = "Preparing runtime-2026.0.0.23`nTests: 12 total, 12 passed, 0 failed`nAll suites passed"
    $bannedPath = '(^|/)(\.git|\.gmcache|\.mcp\.json|AGENTS\.md|CLAUDE\.md|gm-options\.json)(/|$)'
    function Reset-SecondHalf {
        $global:ICReleaseTestState.nodeCalls = @()
        $global:ICReleaseTestState.resourceSnapshots = @()
        $global:ICReleaseTestState.mockSeedFail = $false
        $global:ICReleaseTestState.mockTestExit = 0
        $global:ICReleaseTestState.hostMessages = @()
        $global:ICReleaseTestState.cycleAtCompress = $null
        $global:ICReleaseTestState.mockBuildSync = $true
        $global:ICReleaseTestState.gmRunCalls = 0
        $global:ICReleaseTestState.tamperStagedFile = $false
        $global:ICReleaseTestState.gmRunArgs = @()
        $global:ICReleaseTestState.mockYycOutput = $null
        $global:ICReleaseTestState.mockYycExit = 0
    }
    Set-FixtureVersion '1.0.3.1'
    Set-FixtureArtifact '1.0.3.8'
    Reset-SecondHalf
    $global:ICReleaseTestState.mockTestOutput = 'Tests: 5 total, 4 passed, 1 failed'
    Assert-Rejected 'Test gate rejects failed tests' @{ OnlyPackage = $true } 'reports failures'
    $global:ICReleaseTestState.mockTestOutput = 'Tests: 5 total, 4 passed, 0 failed'
    Assert-Rejected 'Test gate rejects skipped tests' @{ OnlyPackage = $true } 'reports failures'
    $global:ICReleaseTestState.mockTestOutput = "Tests: 3 total, 3 passed, 0 failed`nTests: 4 total, 3 passed, 1 failed"
    Assert-Rejected 'Test gate rejects any failing suite' @{ OnlyPackage = $true } 'reports failures'
    $global:ICReleaseTestState.mockTestOutput = 'Tests: 0 total, 0 passed, 0 failed'
    Assert-Rejected 'Test gate rejects a zero-test summary' @{ OnlyPackage = $true } 'reports failures'
    $global:ICReleaseTestState.mockTestExit = 3
    $global:ICReleaseTestState.mockTestOutput = 'Tests: 5 total, 5 passed, 0 failed'
    Assert-Rejected 'Test gate rejects a runner failure' @{ OnlyPackage = $true } 'exit 3'
    $global:ICReleaseTestState.mockTestExit = 0
    $global:ICReleaseTestState.mockTestOutput = "compiler noise`nno summary line"
    Assert-Rejected 'Test gate rejects a missing summary' @{ OnlyPackage = $true } 'summary is missing'
    $global:ICReleaseTestState.mockTestOutput = ''
    Assert-Rejected 'Test gate rejects an empty test log' @{ OnlyPackage = $true } 'summary is missing'
    if ((Test-Path -LiteralPath $releaseParent) -or $global:ICReleaseTestState.nodeCalls.Count -or (Get-FixtureCycle) -ne 7 -or
        ((Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json).extensionVersion -cne '1.0.3.1')) {
        throw 'A test gate abort staged, packaged, advanced the seed, or touched the cycle counter'
    }
    Add-Pass 'Test gate aborts before staging, packaging, or the seed advance'

    Reset-SecondHalf
    $global:ICReleaseTestState.mockTestOutput = $passingLog
    Assert-ReleaseSucceeded 'A passing summary stages and packages the bundle' @{ OnlyPackage = $true }
    $expectedFiles = @(
        'CHANGELOG.md', 'LICENSE', 'README.md', 'THIRD_PARTY_NOTICES.md', 'build-info.json', 'SHA256SUMS.txt',
        'licenses/bzip2-LICENSE.txt', 'licenses/extension-core-LICENSE.txt', 'licenses/libarchive-COPYING.txt',
        'licenses/libarchive-compress-reader.c.txt', 'licenses/libarchive-compress-writer.c.txt',
        'licenses/lz4-LICENSE.txt', 'licenses/xz-COPYING.0BSD.txt', 'licenses/xz-COPYING.txt',
        'licenses/zlib-LICENSE.txt', 'licenses/zstd-LICENSE.txt',
        'project/extensions/ExtensionCore/ExtensionCore.yy',
        'project/extensions/ExtensionCore/AndroidSource/Java/GMExtUtils.java',
        'project/extensions/ExtensionCore/AndroidSource/Java/GMExtWire.java',
        'project/extensions/ICompression/ICompression.dll', 'project/extensions/ICompression/ICompression.ext',
        'project/extensions/ICompression/ICompression.yy',
        'project/notes/ExtensionCore_readme/ExtensionCore_readme.md',
        'project/notes/ExtensionCore_readme/ExtensionCore_readme.yy',
        'project/scripts/ExtensionCore_api/ExtensionCore_api.gml', 'project/scripts/ExtensionCore_api/ExtensionCore_api.yy',
        'project/scripts/ExtensionCore_exports/ExtensionCore_exports.gml', 'project/scripts/ExtensionCore_exports/ExtensionCore_exports.yy',
        'project/scripts/ICompression_API/ICompression_API.gml', 'project/scripts/ICompression_API/ICompression_API.yy'
    ) | Sort-Object
    $actualFiles = @(Get-ChildItem -LiteralPath $stageDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($actualFiles -join "`n") -cne ($expectedFiles -join "`n")) {
        throw "Stage contents mismatch: $(Compare-Object $expectedFiles $actualFiles | Out-String)"
    }
    Add-Pass 'Stage contains exactly the required release set'
    $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    $stagedExtension = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'project\extensions\ICompression\ICompression.yy') | ConvertFrom-Json
    if ($stagedExtension.extensionVersion -cne '1.0.3.8') { throw 'Staged extension was not stamped to the receipt version' }
    if ((Get-FileHash -LiteralPath (Join-Path $stageDir 'project\extensions\ICompression\ICompression.dll') -Algorithm SHA256).Hash -cne $receipt.sha256) {
        throw 'Staged DLL does not match its receipt'
    }
    Add-Pass 'Staged extension metadata and DLL match the receipt'
    $extractDir = Join-Path $fixture 'verify-extract'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir
    $extracted = @(Get-ChildItem -LiteralPath $extractDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($extractDir.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($extracted -join "`n") -cne ($expectedFiles -join "`n")) {
        throw "ZIP contents mismatch: $(Compare-Object $expectedFiles $extracted | Out-String)"
    }
    Add-Pass 'ZIP contents match the staged set'
    $sumLines = @(Get-Content -LiteralPath (Join-Path $extractDir 'SHA256SUMS.txt'))
    if ($sumLines.Count -ne $expectedFiles.Count - 1) { throw 'SHA256SUMS does not cover the bundle' }
    foreach ($line in $sumLines) {
        if ($line -notmatch '^([0-9A-F]{64})  (.+)$') { throw "Malformed SHA256SUMS line: $line" }
        if ((Get-FileHash -LiteralPath (Join-Path $extractDir $Matches[2]) -Algorithm SHA256).Hash -cne $Matches[1]) {
            throw "Checksum mismatch: $line"
        }
    }
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ((Get-Content -Raw -LiteralPath "$archivePath.sha256").Trim() -cne "$archiveHash  $stageName.zip") {
        throw 'Archive sidecar does not match the ZIP'
    }
    Add-Pass 'SHA256SUMS and the archive sidecar verify against the shipped bytes'
    if (!@($global:ICReleaseTestState.mockLsFiles -split "`n" | Where-Object { $_ -match $bannedPath }).Count) {
        throw 'Fixture offers no credential files to filter'
    }
    if ($global:ICReleaseTestState.resourceSnapshots.Count -ne 1) { throw 'ResourceTool staging copy was not observed' }
    if (@($global:ICReleaseTestState.resourceSnapshots[0] | Where-Object { $_ -match $bannedPath }).Count) {
        throw 'Credential or local-settings files reached the ResourceTool staging copy'
    }
    if (!@($global:ICReleaseTestState.resourceSnapshots[0] | Where-Object { $_ -ceq 'project/ICompression.yyp' }).Count) {
        throw 'Tracked project manifest is missing from the staging copy'
    }
    if (@($actualFiles | Where-Object { $_ -match $bannedPath }).Count -or @($extracted | Where-Object { $_ -match $bannedPath }).Count) {
        throw 'Credential or local-settings files reached the release bundle'
    }
    Add-Pass 'Credential and local-settings files never reach the staging copy or the bundle'
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    foreach ($field in 'extension_version', 'base_version', 'build_number', 'dll_sha256', 'source_revision',
        'source_has_local_changes', 'built_at_utc', 'packaged_at_utc', 'only_package', 'tools', 'generator',
        'configuration', 'platform', 'gamemaker_runtime_versions', 'tests') {
        if ($null -eq $info.PSObject.Properties[$field]) { throw "build-info.json is missing $field" }
    }
    if ($info.extension_version -cne '1.0.3.8' -or $info.base_version -cne '1.0.3' -or $info.build_number -ne 8 -or
        $info.dll_sha256 -cne $receipt.sha256 -or $info.source_revision -notmatch '^[0-9a-f]{40}$' -or
        $info.source_has_local_changes -isnot [bool] -or !$info.built_at_utc -or !$info.packaged_at_utc -or
        $info.only_package -ne $true -or $info.configuration -cne 'Release' -or $info.platform -cne 'windows-x64' -or
        $info.generator -cne 'Visual Studio 18 2026' -or !$info.tools.gm_cli -or !$info.tools.node -or
        !$info.tools.git -or !$info.tools.powershell -or !$info.tools.cxx_compiler -or
        @($info.gamemaker_runtime_versions) -notcontains '2026.0.0.23' -or
        $info.tests.total -ne 12 -or $info.tests.passed -ne 12 -or $info.tests.failed -ne 0) {
        throw 'build-info.json fields are inconsistent'
    }
    Add-Pass 'build-info.json records the required release fields'
    if (((Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json).extensionVersion) -cne '1.0.3.8') {
        throw 'Source seed was not advanced to the released version'
    }
    if ($global:ICReleaseTestState.nodeCalls.Count -ne 2 -or
        $global:ICReleaseTestState.nodeCalls[0][0] -notlike '*release-resources-*' -or $global:ICReleaseTestState.nodeCalls[0][1] -cne '1.0.3.8' -or
        $global:ICReleaseTestState.nodeCalls[1][0] -cne $global:ICReleaseTestState.sourceProject -or $global:ICReleaseTestState.nodeCalls[1][1] -cne '1.0.3.8') {
        throw 'ResourceTool was not invoked for both the staged edit and the seed advance'
    }
    Add-Pass 'Source seed advanced to the released version through ResourceTool'
    if ((Get-FixtureCycle) -ne 0 -or $global:ICReleaseTestState.cycleAtCompress -ne 7 -or
        (Get-FixtureCounter).last_builds['1.0.3'] -ne 8) {
        throw 'Release did not reset the cycle counter after packaging, or rewrote other state'
    }
    Add-Pass 'Release resets the cycle counter only after the archive and sidecar exist'
    $verified = & (Join-Path $fixtureScripts 'validate-package.ps1') -Archive $archivePath -ExpectedVersion '1.0.3.8' -StageDirectory $stageDir
    if ($verified.Version -cne '1.0.3.8' -or $verified.Files -ne 30 -or $verified.CheckedFileHashes -ne 29 -or $verified.Tests -cne '12/12') {
        throw 'Package validator reported unexpected results'
    }
    Add-Pass 'Package validator accepts the freshly built archive'

    Set-FixtureCycle 7
    Reset-SecondHalf
    $global:ICReleaseTestState.mockTestOutput = 'Tests: 2 total, 2 passed, 0 failed'
    Assert-Rejected 'A missing runtime version aborts packaging' @{ OnlyPackage = $true } 'runtime version is missing'
    if ((Test-Path -LiteralPath $archivePath) -or $global:ICReleaseTestState.nodeCalls.Count -ne 1 -or (Get-FixtureCycle) -ne 7) {
        throw 'Runtime scrape failure still produced an archive, advanced the seed, or touched the cycle counter'
    }
    Add-Pass 'Runtime scrape failure leaves no archive and keeps the seed'

    Set-FixtureVersion '1.0.3.1'
    Set-FixtureCycle 7
    Reset-SecondHalf
    $global:ICReleaseTestState.mockTestOutput = $passingLog
    $global:ICReleaseTestState.mockSeedFail = $true
    Assert-Rejected 'Seed advance failure aborts before packaging' @{ OnlyPackage = $true } 'failed to advance the source extension version seed'
    $global:ICReleaseTestState.mockSeedFail = $false
    if ((Test-Path -LiteralPath $archivePath) -or $global:ICReleaseTestState.nodeCalls.Count -ne 2 -or (Get-FixtureCycle) -ne 7 -or
        ((Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json).extensionVersion -cne '1.0.3.1')) {
        throw 'Seed advance failure still produced an archive, touched the cycle counter, or modified the source metadata'
    }
    Add-Pass 'Seed advance failure leaves no archive and keeps the source seed'

    Set-FixtureCycle 7
    Reset-SecondHalf
    $global:ICReleaseTestState.allowGeneration = $true
    Assert-ReleaseSucceeded 'A full release builds, tests, stages, and advances the seed' @{ Version = '1.0.3.8' }
    $global:ICReleaseTestState.allowGeneration = $false
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    if ($info.only_package -ne $false -or $global:ICReleaseTestState.nodeCalls.Count -ne 2 -or (Get-FixtureCycle) -ne 0 -or
        ((Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json).extensionVersion -cne '1.0.3.8')) {
        throw 'Full release did not record provenance, advance the seed, or reset the cycle counter'
    }
    Add-Pass 'Full release records build provenance and advances the seed'

    Set-FixtureVersion '1.0.3.1'
    Reset-SecondHalf
    $archiveBefore = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    $global:ICReleaseTestState.allowGeneration = $true
    $global:ICReleaseTestState.mockBuildSync = $false
    Assert-Rejected 'A stale extension DLL aborts before the tests' @{ Version = '1.0.3.8' } 'did not sync to the extension folder' $true
    $global:ICReleaseTestState.allowGeneration = $false
    $global:ICReleaseTestState.mockBuildSync = $true
    if ($global:ICReleaseTestState.gmRunCalls -ne 0 -or
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -cne $archiveBefore) {
        throw 'Unsynced build output still ran the tests or touched the archive'
    }
    Add-Pass 'Unsynced build output aborts before the tests run'

    Set-FixtureVersion '1.0.3.9'
    Set-FixtureCycle 7
    Reset-SecondHalf
    Assert-ReleaseSucceeded 'Repackaging an older build never rewinds the seed' @{ OnlyPackage = $true }
    if ($global:ICReleaseTestState.nodeCalls.Count -ne 1 -or (Get-FixtureCycle) -ne 0 -or
        ((Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json).extensionVersion -cne '1.0.3.9') -or
        !(Test-Path -LiteralPath $archivePath)) {
        throw 'Repackaging an older build rewound the seed or skipped the archive'
    }
    Add-Pass 'Seed stays put when repackaging an older build'

    $cacheFile = Join-Path $packageBuild 'CMakeCache.txt'
    $cacheLines = @(Get-Content -LiteralPath $cacheFile)
    try {
        @($cacheLines) + "IC_BUILD_STATE_DIR:PATH=$(Join-Path $fixture 'no-such-state')" |
            Set-Content -LiteralPath $cacheFile -Encoding utf8NoBOM
        Set-FixtureCycle 7
        Reset-SecondHalf
        Assert-ReleaseSucceeded 'A missing counter state directory only warns' @{ OnlyPackage = $true }
        if (!@($global:ICReleaseTestState.hostMessages | Where-Object { $_ -like '*release cycle counter was not reset*' }).Count) {
            throw 'Cycle reset failure was not reported'
        }
        if (!(Test-Path -LiteralPath $archivePath) -or (Get-FixtureCycle) -ne 7) {
            throw 'Cycle reset failure affected the archive or the counter state'
        }
    }
    finally { $cacheLines | Set-Content -LiteralPath $cacheFile -Encoding utf8NoBOM }
    Add-Pass 'Cycle reset failure warns without failing the release'

    Set-FixtureCycle 7
    Reset-SecondHalf
    $global:ICReleaseTestState.tamperStagedFile = $true
    Assert-Rejected 'Post-archive verification rejects tampered bytes' @{ OnlyPackage = $true } 'checksum does not match'
    $global:ICReleaseTestState.tamperStagedFile = $false
    if (!(Test-Path -LiteralPath $archivePath)) { throw 'Tampered archive was not left in place for diagnosis' }
    Add-Pass 'Post-archive verification fails the release but keeps the archive'

    # Opt-in YYC second pass: parameter validation, native run shape, gating,
    # and the antivirus hint. The VsDevCmd fixture is never executed.
    $yycVsDevCmd = Join-Path $fixture 'vs\VsDevCmd.bat'
    Assert-Rejected 'YYC tests require the toolchain path' @{ OnlyPackage = $true; YycTests = $true } 'YycVsDevCmd is required'
    Assert-Rejected 'YYC toolchain path must exist' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = (Join-Path $fixture 'missing\VsDevCmd.bat') } 'must point at an existing VsDevCmd.bat'
    Assert-Rejected 'YYC toolchain path must name VsDevCmd.bat' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = (Join-Path $source 'README.md') } 'must point at an existing VsDevCmd.bat'
    Assert-Rejected 'YYC toolchain path requires the switch' @{ OnlyPackage = $true; YycVsDevCmd = $yycVsDevCmd } 'requires -YycTests'

    Set-FixtureCycle 7
    Reset-SecondHalf
    Assert-ReleaseSucceeded 'YYC tests run natively with the selected toolchain' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = $yycVsDevCmd }
    $expectedToolchain = '--toolchain-options={"windows":{"visualStudioSdk":"' + ($yycVsDevCmd -replace '\\', '/') + '"}}'
    if ($global:ICReleaseTestState.gmRunCalls -ne 2 -or
        @($global:ICReleaseTestState.gmRunArgs[0] | Where-Object { $_ -eq '--runtime=vm' }).Count -ne 1 -or
        @($global:ICReleaseTestState.gmRunArgs[0] | Where-Object { $_ -like '--toolchain-options*' }).Count -ne 0 -or
        @($global:ICReleaseTestState.gmRunArgs[1] | Where-Object { $_ -eq '--runtime=native' }).Count -ne 1 -or
        @($global:ICReleaseTestState.gmRunArgs[1] | Where-Object { $_ -eq $expectedToolchain }).Count -ne 1 -or
        !(Test-Path -LiteralPath (Join-Path $packageBuild 'gamemaker-tests-yyc.log'))) {
        throw 'YYC run did not receive the native runtime and the toolchain options'
    }
    Add-Pass 'YYC run receives the native runtime and the toolchain options'
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    $verified = & (Join-Path $fixtureScripts 'validate-package.ps1') -Archive $archivePath -ExpectedVersion '1.0.3.8' -StageDirectory $stageDir
    if ($info.tests.total -ne 12 -or $info.tests.failed -ne 0 -or $verified.Tests -cne '12/12' -or
        $null -eq $info.PSObject.Properties['yyc_tests'] -or
        $info.yyc_tests.total -ne 12 -or $info.yyc_tests.passed -ne 12 -or $info.yyc_tests.failed -ne 0) {
        throw 'build-info.json or the package validator did not record both test runs'
    }
    Add-Pass 'build-info.json records the YYC run and passes the package validator'

    Reset-SecondHalf
    $archiveBefore = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    $global:ICReleaseTestState.mockYycOutput = 'Tests: 5 total, 4 passed, 1 failed'
    Assert-Rejected 'YYC gate rejects failed tests' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = $yycVsDevCmd } 'YYC test summary reports failures'
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -cne $archiveBefore -or $global:ICReleaseTestState.gmRunCalls -ne 2) {
        throw 'YYC failure still touched the archive or skipped a run'
    }
    Add-Pass 'YYC gate aborts after both runs and leaves the archive alone'
    $global:ICReleaseTestState.mockYycOutput = 'compiler noise without a summary'
    Assert-Rejected 'YYC gate rejects a missing summary' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = $yycVsDevCmd } 'YYC test summary is missing'
    $global:ICReleaseTestState.mockYycExit = 1
    $global:ICReleaseTestState.mockYycOutput = "Igor.Windows executed`nSystem.ComponentModel.Win32Exception (5): Access is denied."
    Assert-Rejected 'YYC failure hints at antivirus quarantine' @{ OnlyPackage = $true; YycTests = $true; YycVsDevCmd = $yycVsDevCmd } 'quarantined by heuristic antivirus'
    Reset-SecondHalf
    $global:ICReleaseTestState.mockYycExit = 1
    $global:ICReleaseTestState.mockYycOutput = 'generic build break'
    $failure = $null
    try { & $fixtureRelease -OnlyPackage -YycTests -YycVsDevCmd $yycVsDevCmd | Out-Null }
    catch { $failure = $_.Exception.Message }
    if (!$failure -or $failure -notlike '*YYC tests failed (exit 1)*' -or $failure -like '*quarantined*') {
        throw "YYC failure without the AV signature misfired the hint: $failure"
    }
    Add-Pass 'YYC failure without the AV signature skips the hint'

    # Optional macOS binary inclusion: validation, staging, build-info, and
    # the package validator's conditional requirement.
    $macOsFixture = Join-Path $fixture 'macho\libICompression.dylib'
    Assert-Rejected 'MacOsBinary path must exist' @{ OnlyPackage = $true; MacOsBinary = (Join-Path $fixture 'missing\libICompression.dylib') } 'MacOsBinary does not exist'
    Assert-Rejected 'MacOsBinary must be named for the extension' @{ OnlyPackage = $true; MacOsBinary = (Join-Path $fixture 'macho\foo.dylib') } 'must be named libICompression.dylib'
    Assert-Rejected 'MacOsBinary must be a Mach-O' @{ OnlyPackage = $true; MacOsBinary = (Join-Path $fixture 'bad\libICompression.dylib') } 'not a Mach-O'

    Set-FixtureCycle 7
    Reset-SecondHalf
    Assert-ReleaseSucceeded 'A macOS binary stages alongside the Windows files' @{ OnlyPackage = $true; MacOsBinary = $macOsFixture }
    $macExpected = @($expectedFiles) + 'project/extensions/ICompression/libICompression.dylib' | Sort-Object
    $macActual = @(Get-ChildItem -LiteralPath $stageDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($macActual -join "`n") -cne ($macExpected -join "`n")) {
        throw "macOS bundle file set mismatch: $(Compare-Object $macExpected $macActual | Out-String)"
    }
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    $verified = & (Join-Path $fixtureScripts 'validate-package.ps1') -Archive $archivePath -ExpectedVersion '1.0.3.8' -StageDirectory $stageDir
    if ($null -eq $info.PSObject.Properties['macos_binary'] -or
        $info.macos_binary.sha256 -cne (Get-FileHash -LiteralPath $macOsFixture -Algorithm SHA256).Hash -or
        $verified.Files -ne 31 -or $verified.CheckedFileHashes -ne 30) {
        throw 'macOS binary was not staged, recorded, and validated'
    }
    Add-Pass 'macOS binary stages, records its checksum, and passes the validator'

    # Optional Linux binary inclusion, mirroring the macOS parameter.
    $linuxFixture = Join-Path $fixture 'elf\libICompression.so'
    Assert-Rejected 'LinuxBinary path must exist' @{ OnlyPackage = $true; LinuxBinary = (Join-Path $fixture 'missing\libICompression.so') } 'LinuxBinary does not exist'
    Assert-Rejected 'LinuxBinary must be named for the extension' @{ OnlyPackage = $true; LinuxBinary = (Join-Path $fixture 'elf\foo.so') } 'must be named libICompression.so'
    Assert-Rejected 'LinuxBinary must be an ELF shared object' @{ OnlyPackage = $true; LinuxBinary = (Join-Path $fixture 'badelf\libICompression.so') } 'not an ELF 64-bit x86-64 shared object'

    Set-FixtureCycle 7
    Reset-SecondHalf
    Assert-ReleaseSucceeded 'A Linux binary stages alongside the Windows files' @{ OnlyPackage = $true; LinuxBinary = $linuxFixture }
    $linuxExpected = @($expectedFiles) + 'project/extensions/ICompression/libICompression.so' | Sort-Object
    $linuxActual = @(Get-ChildItem -LiteralPath $stageDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($linuxActual -join "`n") -cne ($linuxExpected -join "`n")) {
        throw "Linux bundle file set mismatch: $(Compare-Object $linuxExpected $linuxActual | Out-String)"
    }
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    $verified = & (Join-Path $fixtureScripts 'validate-package.ps1') -Archive $archivePath -ExpectedVersion '1.0.3.8' -StageDirectory $stageDir
    if ($null -eq $info.PSObject.Properties['linux_binary'] -or
        $info.linux_binary.sha256 -cne (Get-FileHash -LiteralPath $linuxFixture -Algorithm SHA256).Hash -or
        $null -ne $info.PSObject.Properties['macos_binary'] -or
        $verified.Files -ne 31 -or $verified.CheckedFileHashes -ne 30) {
        throw 'Linux binary was not staged, recorded, and validated'
    }
    Add-Pass 'Linux binary stages, records its checksum, and passes the validator'

    Set-FixtureCycle 7
    Reset-SecondHalf
    Assert-ReleaseSucceeded 'Linux and macOS binaries stage together' @{ OnlyPackage = $true; MacOsBinary = $macOsFixture; LinuxBinary = $linuxFixture }
    $bothExpected = @($linuxExpected) + 'project/extensions/ICompression/libICompression.dylib' | Sort-Object
    $bothActual = @(Get-ChildItem -LiteralPath $stageDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($bothActual -join "`n") -cne ($bothExpected -join "`n")) {
        throw "Combined bundle file set mismatch: $(Compare-Object $bothExpected $bothActual | Out-String)"
    }
    $info = Get-Content -Raw -LiteralPath (Join-Path $stageDir 'build-info.json') | ConvertFrom-Json
    $verified = & (Join-Path $fixtureScripts 'validate-package.ps1') -Archive $archivePath -ExpectedVersion '1.0.3.8' -StageDirectory $stageDir
    if ($null -eq $info.PSObject.Properties['linux_binary'] -or $null -eq $info.PSObject.Properties['macos_binary'] -or
        $info.linux_binary.sha256 -cne (Get-FileHash -LiteralPath $linuxFixture -Algorithm SHA256).Hash -or
        $info.macos_binary.sha256 -cne (Get-FileHash -LiteralPath $macOsFixture -Algorithm SHA256).Hash -or
        $verified.Files -ne 32 -or $verified.CheckedFileHashes -ne 31) {
        throw 'Linux and macOS binaries were not staged, recorded, and validated'
    }
    Add-Pass 'Linux and macOS binaries stage together and both pass the validator'
    Write-Output "Release preflight checks: $($global:ICReleaseTestState.passed) passed"
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $allowedParent = [IO.Path]::GetFullPath((Join-Path $repository 'out')) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedFixture.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    # Release pending archive handles, then retry removal; a locked leftover
    # (observed on hosted runners after a green run) gets reported by name.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $removed = $false
    foreach ($attempt in 1..3) {
        try {
            Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction Stop
            $removed = $true
            break
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (!$removed) {
        Get-ChildItem -LiteralPath $resolvedFixture -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $locked = $false
                try { $stream = [IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $stream.Dispose() } catch { $locked = $true }
                Write-Output ("leftover{0}: {1}" -f ($(if ($locked) { ' LOCKED' } else { '' }), $_.FullName))
            }
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
    Write-Output 'fixture cleanup complete'
}
exit 0
