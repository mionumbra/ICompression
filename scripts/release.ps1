#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Generator = "Visual Studio 18 2026",
    [string]$BuildDirectory,
    [string]$GameMakerCacheDirectory,
    [switch]$OnlyPackage,
    [string]$ResourceToolPath,
    [switch]$YycTests,
    [string]$YycVsDevCmd
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$project = Join-Path $root "project\ICompression.yyp"
$extensionPath = Join-Path $root "project\extensions\ICompression\ICompression.yy"

function Assert-ChildPath([string]$Path, [string]$Parent) {
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path, $root).TrimEnd('\', '/')
    if (!$fullPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be a child of ${parentPath}: $fullPath"
    }
    $cursor = $fullPath
    while ($cursor.Length -ge $parentPath.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not permitted in release paths: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    return $fullPath
}

function Remove-ReleaseDirectory([string]$Path, [string]$Parent) {
    $safePath = Assert-ChildPath $Path $Parent
    if (Test-Path -LiteralPath $safePath) {
        $links = @(Get-ChildItem -LiteralPath $safePath -Recurse -Force -Attributes ReparsePoint)
        if ($links.Count) { throw "Refusing recursive cleanup of a directory containing reparse points: $safePath" }
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }
}

function Read-ToolOutput([string]$Tool, [string[]]$Arguments) {
    Get-Command $Tool -ErrorAction Stop | Out-Null
    $global:LASTEXITCODE = 0
    $text = (& $Tool @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed (exit $LASTEXITCODE): $text" }
    return $text
}

function Read-CacheValue([string]$Cache, [string]$Name) {
    $match = [regex]::Match($Cache, '(?m)^' + [regex]::Escape($Name) + ':[^=]+=(.*)$')
    return $match.Groups[1].Value.Trim()
}

function Get-ExtensionAbi($Extension) {
    return @($Extension.files | ForEach-Object {
        $file = $_
        [ordered]@{
            filename = $file.filename; kind = $file.kind; init = $file.init; final = $file.final
            functions = @($file.functions | Sort-Object name | ForEach-Object {
                [ordered]@{ name = $_.name; externalName = $_.externalName; kind = $_.kind
                    argCount = $_.argCount; args = @($_.args); returnType = $_.returnType; hidden = $_.hidden }
            })
        }
    }) | ConvertTo-Json -Depth 20 -Compress
}

function Assert-Version([string]$Value, [string]$Label) {
    if ($Value -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "$Label must use project.version1.version2.build: $Value"
    }
    foreach ($part in $Value.Split('.')) {
        if ($part.Length -gt 5 -or [int]$part -gt 65535) { throw 'Version components must be at most 65535' }
    }
}

function Get-VersionBase([string]$Value) { return ($Value.Split('.')[0..2] -join '.') }

# Source metadata owns the first three fields. Its fourth field is a historical
# seed; only a successful DLL build owns the compiled fourth field.
$extensionText = Get-Content -Raw -LiteralPath $extensionPath
$versionFields = [regex]::Matches($extensionText, '"extensionVersion"\s*:\s*"([^"]*)"')
if ($versionFields.Count -ne 1) { throw "Expected exactly one extensionVersion in $extensionPath" }
$sourceVersion = $versionFields[0].Groups[1].Value
Assert-Version $sourceVersion 'extensionVersion'
$sourceBase = Get-VersionBase $sourceVersion
$requestedVersion = $Version
if ($PSBoundParameters.ContainsKey('Version')) {
    Assert-Version $requestedVersion 'Version'
    if ((Get-VersionBase $requestedVersion) -cne $sourceBase) { throw "Version must match source base $sourceBase" }
}
$extension = $extensionText | ConvertFrom-Json
$workspace = [IO.Path]::GetFullPath((Read-ToolOutput 'git' @('-C', $root, 'rev-parse', '--show-toplevel')))
$explicitBuild = $PSBoundParameters.ContainsKey('BuildDirectory')
if ($explicitBuild -and [string]::IsNullOrWhiteSpace($BuildDirectory)) { throw 'BuildDirectory must not be empty' }
$build = Assert-ChildPath $(if ($explicitBuild) { $BuildDirectory } else { Join-Path $root 'out\release-build' }) $workspace
if ($build -ieq $root) { throw 'BuildDirectory must not be the source directory' }
if ($PSBoundParameters.ContainsKey('GameMakerCacheDirectory')) {
    if ([string]::IsNullOrWhiteSpace($GameMakerCacheDirectory)) { throw 'GameMakerCacheDirectory must not be empty' }
    $GameMakerCacheDirectory = Assert-ChildPath $GameMakerCacheDirectory $workspace
    if (!(Test-Path -LiteralPath $GameMakerCacheDirectory -PathType Container)) {
        throw "GameMakerCacheDirectory must be an existing cache directory: $GameMakerCacheDirectory"
    }
}
if ($PSBoundParameters.ContainsKey('ResourceToolPath')) {
    if ([string]::IsNullOrWhiteSpace($ResourceToolPath)) { throw 'ResourceToolPath must not be empty' }
    $ResourceToolPath = [IO.Path]::GetFullPath($ResourceToolPath, $root)
    if (!(Test-Path -LiteralPath $ResourceToolPath -PathType Leaf)) { throw "ResourceToolPath does not exist: $ResourceToolPath" }
}
if ($YycTests) {
    if ([string]::IsNullOrWhiteSpace($YycVsDevCmd)) { throw 'YycVsDevCmd is required with -YycTests' }
    $YycVsDevCmd = [IO.Path]::GetFullPath($YycVsDevCmd, $root)
    # The runtime's toolchain default names the VsDevCmd.bat file itself; a
    # Visual Studio root makes the asset compiler report no VS location is set.
    if (!(Test-Path -LiteralPath $YycVsDevCmd -PathType Leaf) -or [IO.Path]::GetFileName($YycVsDevCmd) -ine 'VsDevCmd.bat') {
        throw "YycVsDevCmd must point at an existing VsDevCmd.bat (not the Visual Studio root): $YycVsDevCmd"
    }
}
elseif ($PSBoundParameters.ContainsKey('YycVsDevCmd')) { throw 'YycVsDevCmd requires -YycTests' }
$cachePath = Join-Path $build 'CMakeCache.txt'
if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    $cache = Get-Content -Raw -LiteralPath $cachePath
    $cachedSource = Read-CacheValue $cache 'CMAKE_HOME_DIRECTORY'
    if (!$cachedSource -or [IO.Path]::GetFullPath($cachedSource).TrimEnd('\', '/') -ine $root) {
        throw "BuildDirectory belongs to a different source directory: $cachedSource"
    }
    if (!$OnlyPackage -and (Read-CacheValue $cache 'CMAKE_GENERATOR') -cne $Generator) { throw "BuildDirectory generator does not match $Generator" }
}
elseif ($explicitBuild -or $OnlyPackage) { throw "BuildDirectory must be an existing configured CMake tree: $build" }

$extgenVersion = $null
$cmakeVersion = $null
if (!$OnlyPackage) {
# extgen exposes its version through the supported help command; --version exits 1.
$extgenOutput = Read-ToolOutput 'extgen' @('--help')
$extgenMatch = [regex]::Match($extgenOutput, '\bextgen (v1\.(?:d8c68bd|225bddc))\b')
if (!$extgenMatch.Success) { throw "Expected extgen v1.d8c68bd or v1.225bddc; found: $extgenOutput" }
$extgenVersion = $extgenMatch.Groups[1].Value
$cmakeOutput = Read-ToolOutput 'cmake' @('--version')
$cmakeMatch = [regex]::Match($cmakeOutput, '^cmake version ([0-9]+\.[0-9]+\.[0-9]+)')
if (!$cmakeMatch.Success) { throw "Cannot read CMake version: $cmakeOutput" }
$cmakeVersion = $cmakeMatch.Groups[1].Value
$minimumCmake = if ($Generator -eq 'Visual Studio 18 2026') { [version]'4.2' } else { [version]'3.21' }
if ([version]$cmakeVersion -lt $minimumCmake) { throw "$Generator requires CMake $minimumCmake or newer" }
$capabilities = Read-ToolOutput 'cmake' @('-E', 'capabilities') | ConvertFrom-Json
if ($Generator -cnotin @($capabilities.generators.name)) { throw "Installed CMake does not support generator: $Generator" }
}
$gmCliVersion = Read-ToolOutput 'gm-cli' @('--version')
$gitVersion = Read-ToolOutput 'git' @('--version')
$nodeVersion = Read-ToolOutput 'node' @('--version')

if (!$OnlyPackage) {

# Generate extension metadata into a temporary copy and compare its ABI. This
# keeps the checked-in .yy untouched while detecting stale native declarations.
$generationDir = Assert-ChildPath (Join-Path $root ('out\release-generation-' + [guid]::NewGuid().ToString('N'))) $root
try {
    New-Item -ItemType Directory -Path $generationDir -Force | Out-Null
    $generatedExtension = Join-Path $generationDir 'ICompression.yy'
    Copy-Item -LiteralPath $extensionPath -Destination $generatedExtension
    $generationConfig = Get-Content -Raw -LiteralPath (Join-Path $root 'config.json') | ConvertFrom-Json
    $generationConfig.root = $root
    $generationConfig.input = Join-Path $root 'api.gmidl'
    $generationConfig.gamemaker.extension.outputFile = $generatedExtension
    $generationConfigPath = Join-Path $generationDir 'config.json'
    $generationConfig | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $generationConfigPath -Encoding utf8NoBOM
    & extgen --config $generationConfigPath
    if ($LASTEXITCODE -ne 0) { throw 'extgen failed' }
    $generatedMetadata = Get-Content -Raw -LiteralPath $generatedExtension | ConvertFrom-Json
    if ((Get-ExtensionAbi $extension) -cne (Get-ExtensionAbi $generatedMetadata)) {
        throw 'Extension ABI is stale. Run extgen --config config.json, review its resource changes, then release again.'
    }
}
finally {
    Remove-ReleaseDirectory $generationDir $root
}

$configureArgs = @('-S', $root, '-B', $build, '-G', $Generator, '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL', "-DEXT_OUTPUT_DIR=$root\project\extensions\ICompression")
if ($Generator -like 'Visual Studio *') { $configureArgs += @('-A', 'x64') }
& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }
$buildArgs = @('--build', $build, '--config', 'Release')
& cmake @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake build failed' }
# A broken EXT_OUTPUT_DIR bridge leaves a stale but self-consistent DLL+receipt
# in the extension folder; the just-built DLL must match what gets packaged.
$builtDll = Join-Path $build 'Release\ICompression.dll'
$syncedDll = Join-Path $root 'project\extensions\ICompression\ICompression.dll'
if (!(Test-Path -LiteralPath $builtDll -PathType Leaf)) { throw "Build-tree DLL is missing: $builtDll" }
if (!(Test-Path -LiteralPath $syncedDll -PathType Leaf) -or
    (Get-FileHash -LiteralPath $builtDll -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $syncedDll -Algorithm SHA256).Hash) {
    throw 'Build output did not sync to the extension folder; fix the EXT_OUTPUT_DIR bridge and rebuild'
}
}

$dllPath = Join-Path $root 'project\extensions\ICompression\ICompression.dll'
$receiptPath = "$dllPath.build.json"
if (!(Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Compiled DLL is missing: $dllPath" }
if (!(Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "DLL build receipt is missing: $receiptPath" }
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
Assert-Version $receipt.version 'Compiled version'
$Version = $receipt.version
if ($receipt.schema_version -ne 1 -or $receipt.base_version -cne $sourceBase -or
    (Get-VersionBase $Version) -cne $sourceBase -or
    $receipt.build_number -ne [int]$Version.Split('.')[3]) { throw 'DLL build receipt version/base is inconsistent' }
if ($receipt.configuration -cne 'Release') { throw 'Only a Release DLL may be packaged' }
if ($receipt.source_revision -notmatch '^[0-9a-fA-F]{40}$' -or
    $receipt.source_has_local_changes -isnot [bool] -or
    [string]::IsNullOrWhiteSpace($receipt.cxx_compiler) -or [string]::IsNullOrWhiteSpace($receipt.generator)) {
    throw 'DLL build receipt is missing valid source/compiler provenance'
}
$buildTimestamp = [DateTimeOffset]::MinValue
if (![DateTimeOffset]::TryParse($receipt.built_at_utc, [ref]$buildTimestamp)) { throw 'DLL build receipt timestamp is invalid' }
if ($requestedVersion -and $requestedVersion -cne $Version) { throw "Version must match compiled DLL $Version; received '$requestedVersion'" }
$dllHash = (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash
if ($receipt.sha256 -cnotmatch '^[0-9A-F]{64}$' -or $receipt.sha256 -cne $dllHash) { throw 'DLL build receipt SHA-256 does not match the DLL' }
$dllVersion = (Get-Item -LiteralPath $dllPath).VersionInfo
if ($dllVersion.FileVersion -cne $Version -or $dllVersion.ProductVersion -cne $Version) { throw 'DLL version does not match its build receipt' }
$dllBytes = [IO.File]::ReadAllBytes($dllPath)
if ($dllBytes.Length -lt 64) { throw 'Release DLL is not a valid PE file' }
$peOffset = [BitConverter]::ToInt32($dllBytes, 0x3c)
if ($peOffset -lt 0 -or [long]$peOffset + 6 -gt $dllBytes.Length -or
    [BitConverter]::ToUInt32($dllBytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($dllBytes, $peOffset + 4) -ne 0x8664) { throw 'Release DLL is not Windows x64' }
$stage = Assert-ChildPath (Join-Path $root "release\ICompression-$Version-windows-x64") (Join-Path $root 'release')
$archive = "$stage.zip"
# --runtime=vm chooses the runner type; omit any runtime-version override so
# gm-cli uses the user's configured/default GameMaker runtime.
$testLog = Join-Path $build 'gamemaker-tests.log'
$gmArgs = @('run', $project, '--target=windows', '--runtime=vm')
if ($GameMakerCacheDirectory) { $gmArgs += "--cache-dir=$GameMakerCacheDirectory" }
& gm-cli @gmArgs 2>&1 | Tee-Object -FilePath $testLog
$testExitCode = $LASTEXITCODE
$testOutput = Get-Content -Raw -LiteralPath $testLog
if ($testExitCode -ne 0) { throw "GameMaker VM tests failed (exit $testExitCode); see $testLog" }
$summaries = [regex]::Matches($testOutput, 'Tests:\s*(\d+) total,\s*(\d+) passed,\s*(\d+) failed')
if (!$summaries.Count) { throw "GameMaker test summary is missing; see $testLog" }
foreach ($summary in $summaries) {
    if ([int]$summary.Groups[1].Value -le 0 -or $summary.Groups[1].Value -ne $summary.Groups[2].Value -or
        [int]$summary.Groups[3].Value -ne 0) { throw "GameMaker test summary reports failures; see $testLog" }
}

# Optional second pass: the same suite under YYC (native), gated identically.
$yycSummaries = $null
if ($YycTests) {
    $yycLog = Join-Path $build 'gamemaker-tests-yyc.log'
    $yycToolchain = (@{ windows = @{ visualStudioSdk = ($YycVsDevCmd -replace '\\', '/') } } | ConvertTo-Json -Compress)
    $yycArgs = @('run', $project, '--target=windows', '--runtime=native', "--toolchain-options=$yycToolchain")
    if ($GameMakerCacheDirectory) { $yycArgs += "--cache-dir=$GameMakerCacheDirectory" }
    & gm-cli @yycArgs 2>&1 | Tee-Object -FilePath $yycLog
    $yycExitCode = $LASTEXITCODE
    $yycOutput = Get-Content -Raw -LiteralPath $yycLog
    # A fresh unsigned YYC exe can be quarantined by heuristic antivirus; Igor
    # then dies with a Win32 access-denied error when starting the game.
    $yycHint = ''
    if ($yycOutput -match 'Win32Exception|Access is denied|access is denied') {
        $yycHint = ' A fresh unsigned YYC executable may have been quarantined by heuristic antivirus; allowlist the build output and retry.'
    }
    if ($yycExitCode -ne 0) { throw "GameMaker YYC tests failed (exit $yycExitCode); see $yycLog.$yycHint" }
    $yycSummaries = [regex]::Matches($yycOutput, 'Tests:\s*(\d+) total,\s*(\d+) passed,\s*(\d+) failed')
    if (!$yycSummaries.Count) { throw "GameMaker YYC test summary is missing; see $yycLog.$yycHint" }
    foreach ($summary in $yycSummaries) {
        if ([int]$summary.Groups[1].Value -le 0 -or $summary.Groups[1].Value -ne $summary.Groups[2].Value -or
            [int]$summary.Groups[3].Value -ne 0) { throw "GameMaker YYC test summary reports failures; see $yycLog.$yycHint" }
    }
}

Remove-ReleaseDirectory $stage (Join-Path $root 'release')
foreach ($oldFile in @($archive, "${archive}.sha256")) {
    $safeFile = Assert-ChildPath $oldFile (Join-Path $root 'release')
    if (Test-Path -LiteralPath $safeFile) { Remove-Item -LiteralPath $safeFile -Force }
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files = @(
    'README.md', 'LICENSE', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md',
    'project\extensions\ICompression\ICompression.yy',
    'project\extensions\ICompression\ICompression.ext',
    'project\extensions\ICompression\ICompression.dll',
    'project\scripts\ICompression_API\ICompression_API.yy',
    'project\scripts\ICompression_API\ICompression_API.gml',
    'project\scripts\GMExtCore\GMExtCore.yy',
    'project\scripts\GMExtCore\GMExtCore.gml'
)
foreach ($relative in $files) {
    $source = Join-Path $root $relative
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing release file: $relative" }
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

# ResourceTool needs the complete project context. Copy tracked resources from
# this source tree and add generated runtime files; local settings/cache stay out.
$resourceCache = if ($GameMakerCacheDirectory) { $GameMakerCacheDirectory } else { Join-Path $root 'project\.gmcache' }
$resourceTemp = Assert-ChildPath (Join-Path $root ('out\release-resources-' + [guid]::NewGuid().ToString('N'))) $root
try {
    $trackedProject = Read-ToolOutput 'git' @('-C', $workspace, '-c', 'core.quotepath=false', 'ls-files', '--', 'project')
    $resourceFiles = @($trackedProject -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '(^|/)(\.git|\.gmcache|\.mcp\.json|AGENTS\.md|CLAUDE\.md|gm-options\.json)(/|$)'
    })
    if ('project/ICompression.yyp' -cnotin $resourceFiles) { throw 'Tracked GameMaker project manifest is missing' }
    $resourceFiles = @($resourceFiles + @($files | Where-Object { $_ -like 'project\*' })) | Sort-Object -Unique
    foreach ($relative in $resourceFiles) {
        $resourceSource = Assert-ChildPath (Join-Path $root $relative) $root
        if (!(Test-Path -LiteralPath $resourceSource -PathType Leaf)) { throw "Missing project resource: $relative" }
        $resourceDestination = Assert-ChildPath (Join-Path $resourceTemp $relative) $resourceTemp
        New-Item -ItemType Directory -Path (Split-Path -Parent $resourceDestination) -Force | Out-Null
        Copy-Item -LiteralPath $resourceSource -Destination $resourceDestination
    }
    $resourceArgs = @((Join-Path $PSScriptRoot 'set-extension-version.cjs'), '--project', (Join-Path $resourceTemp 'project\ICompression.yyp'),
        '--version', $Version, '--cache-dir', $resourceCache)
    if ($ResourceToolPath) { $resourceArgs += @('--resource-tool', $ResourceToolPath) }
    & node @resourceArgs
    if ($LASTEXITCODE -ne 0) { throw 'ResourceTool failed to set the staged extension version' }
    $updatedExtensionPath = Join-Path $resourceTemp 'project\extensions\ICompression\ICompression.yy'
    $updatedExtension = Get-Content -Raw -LiteralPath $updatedExtensionPath | ConvertFrom-Json
    if ($updatedExtension.extensionVersion -cne $Version -or (Get-ExtensionAbi $extension) -cne (Get-ExtensionAbi $updatedExtension)) {
        throw 'ResourceTool changed the extension ABI or failed to set the compiled version'
    }
    Copy-Item -LiteralPath $updatedExtensionPath -Destination (Join-Path $stage 'project\extensions\ICompression\ICompression.yy')
}
finally { Remove-ReleaseDirectory $resourceTemp $root }

# Detect concurrent builds or artifact replacement while the tests/staging ran.
if ((Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash -cne $dllHash -or
    (Get-FileHash -LiteralPath (Join-Path $stage 'project\extensions\ICompression\ICompression.dll') -Algorithm SHA256).Hash -cne $dllHash) {
    throw 'DLL changed during release; rerun against the completed build'
}
$licenses = [ordered]@{
    'zlib-LICENSE.txt' = 'zlib-src\LICENSE'
    'bzip2-LICENSE.txt' = 'bzip2-src\LICENSE'
    'zstd-LICENSE.txt' = 'zstd-src\LICENSE'
    'lz4-LICENSE.txt' = 'lz4-src\lib\LICENSE'
    'xz-COPYING.txt' = 'xz-src\COPYING'
    'xz-COPYING.0BSD.txt' = 'xz-src\COPYING.0BSD'
    'libarchive-COPYING.txt' = 'libarchive-src\COPYING'
    'libarchive-compress-reader.c.txt' = 'libarchive-src\libarchive\archive_read_support_filter_compress.c'
    'libarchive-compress-writer.c.txt' = 'libarchive-src\libarchive\archive_write_add_filter_compress.c'
}
$licenseDir = Join-Path $stage 'licenses'
New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
foreach ($item in $licenses.GetEnumerator()) {
    $source = Join-Path (Join-Path $build '_deps') $item.Value
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing dependency license: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $licenseDir $item.Key)
}

$runtimeVersions = @([regex]::Matches($testOutput, 'runtime-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
# The shipped build-info must name the runtime that ran the tests; a silently
# empty list would hide a scrape regression, so fail like the summary gate.
if (!$runtimeVersions.Count) { throw "GameMaker runtime version is missing from the test log; see $testLog" }
$buildInfo = [ordered]@{
    extension_version = $Version
    base_version = $receipt.base_version
    build_number = $receipt.build_number
    dll_sha256 = $dllHash
    source_revision = $receipt.source_revision
    source_has_local_changes = $receipt.source_has_local_changes
    built_at_utc = $receipt.built_at_utc
    packaged_at_utc = [DateTime]::UtcNow.ToString('o')
    only_package = [bool]$OnlyPackage
    tools = [ordered]@{ extgen = $extgenVersion; cmake = $cmakeVersion; gm_cli = $gmCliVersion
        node = $nodeVersion; powershell = $PSVersionTable.PSVersion.ToString(); git = $gitVersion; cxx_compiler = $receipt.cxx_compiler }
    generator = $receipt.generator
    configuration = $receipt.configuration
    platform = 'windows-x64'
    gamemaker_runtime_versions = $runtimeVersions
    tests = [ordered]@{ total = [int]$summaries[-1].Groups[1].Value; passed = [int]$summaries[-1].Groups[2].Value; failed = 0 }
}
if ($yycSummaries) {
    $buildInfo.yyc_tests = [ordered]@{ total = [int]$yycSummaries[-1].Groups[1].Value; passed = [int]$yycSummaries[-1].Groups[2].Value; failed = 0 }
}
$buildInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stage 'build-info.json') -Encoding utf8NoBOM
Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName |
    Get-FileHash -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash)  $($_.Path.Substring($stage.Length + 1).Replace('\', '/'))" } |
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Encoding ascii
# Fresh clones seed their build counter from the source metadata's fourth
# field, so it must reach the shipped version before the archive exists: a
# ResourceTool failure aborts with no ZIP, and a later packaging failure still
# leaves a correct seed because this exact DLL passed every gate. Never rewind:
# repackaging an older build keeps the newer seed.
if ($receipt.build_number -ge [int]$sourceVersion.Split('.')[3]) {
    $seedArgs = @((Join-Path $PSScriptRoot 'set-extension-version.cjs'), '--project', $project,
        '--version', $Version, '--cache-dir', $resourceCache)
    if ($ResourceToolPath) { $seedArgs += @('--resource-tool', $ResourceToolPath) }
    & node @seedArgs
    if ($LASTEXITCODE -ne 0) { throw 'ResourceTool failed to advance the source extension version seed' }
    $seededExtension = Get-Content -Raw -LiteralPath $extensionPath | ConvertFrom-Json
    if ($seededExtension.extensionVersion -cne $Version -or (Get-ExtensionAbi $extension) -cne (Get-ExtensionAbi $seededExtension)) {
        throw 'ResourceTool changed the source extension ABI or failed to persist the version seed'
    }
}
else { Write-Host "Source seed $sourceVersion is newer than the packaged build $Version; leaving the seed unchanged" }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -CompressionLevel Optimal
$archiveHash = Get-FileHash -Algorithm SHA256 -LiteralPath $archive
"$($archiveHash.Hash)  $(Split-Path -Leaf $archive)" |
    Set-Content -LiteralPath "${archive}.sha256" -Encoding ascii
# The release cycle is closed: reset the build counter's cycle count so the next
# functional version starts counting from zero. The state directory is resolved
# like the build does (IC_BUILD_STATE_DIR in the build tree's CMake cache,
# falling back to .build-state). Best-effort: the ZIP and sidecar are already
# written, so any failure here only warns.
try {
    $counterStateDir = Join-Path $root '.build-state'
    $releaseCachePath = Join-Path $build 'CMakeCache.txt'
    if (Test-Path -LiteralPath $releaseCachePath -PathType Leaf) {
        $stateDirSetting = Read-CacheValue (Get-Content -Raw -LiteralPath $releaseCachePath) 'IC_BUILD_STATE_DIR'
        if ($stateDirSetting) { $counterStateDir = [IO.Path]::GetFullPath($stateDirSetting, $root) }
    }
    $counterStatePath = Join-Path $counterStateDir 'counter.json'
    if (!(Test-Path -LiteralPath $counterStateDir -PathType Container)) { throw "Build counter state directory is missing: $counterStateDir" }
    if (!(Test-Path -LiteralPath $counterStatePath -PathType Leaf)) { throw "Build counter state is missing: $counterStatePath" }
    $counterLockPath = Join-Path $counterStateDir 'counter.lock'
    $counterLock = $null
    $counterDeadline = [DateTime]::UtcNow.AddSeconds(60)
    while (!$counterLock) {
        try { $counterLock = [IO.File]::Open($counterLockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $counterDeadline) { throw "Timed out waiting for the build counter lock: $counterLockPath" }
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        $counterState = [IO.File]::ReadAllText($counterStatePath) | ConvertFrom-Json -AsHashtable
        $counterState.cycle_builds = 0
        $counterTemporary = $counterStatePath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [IO.File]::WriteAllText($counterTemporary, ($counterState | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
            [IO.File]::Move($counterTemporary, $counterStatePath, $true)
        } finally { if ([IO.File]::Exists($counterTemporary)) { [IO.File]::Delete($counterTemporary) } }
    } finally { $counterLock.Dispose() }
} catch { Write-Host "WARNING: the release cycle counter was not reset: $($_.Exception.Message)" }
# Re-verify the finished archive before reporting success. A bad archive is
# left in place for diagnosis; the non-zero exit is the failure signal.
& (Join-Path $PSScriptRoot 'validate-package.ps1') -Archive $archive -ExpectedVersion $Version -StageDirectory $stage | Out-Null
$archiveHash
