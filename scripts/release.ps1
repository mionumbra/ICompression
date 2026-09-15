#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Generator = "Visual Studio 18 2026",
    [string]$BuildDirectory,
    [string]$GameMakerCacheDirectory
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

# Reject invalid versions and unsafe destinations before generation or writes.
# Preserve all four user-defined project.version1.version2.build fields.
$extensionText = Get-Content -Raw -LiteralPath $extensionPath
$versionFields = [regex]::Matches($extensionText, '"extensionVersion"\s*:\s*"([^"]*)"')
if ($versionFields.Count -ne 1) { throw "Expected exactly one extensionVersion in $extensionPath" }
$sourceVersion = $versionFields[0].Groups[1].Value
if ($sourceVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw "extensionVersion must use project.version1.version2.build: $sourceVersion"
}
foreach ($part in $sourceVersion.Split('.')) {
    if ($part.Length -gt 5 -or [int]$part -gt 65535) { throw "Version components must be at most 65535" }
}
if ($PSBoundParameters.ContainsKey('Version') -and $Version -cne $sourceVersion) {
    throw "Version must match extensionVersion $sourceVersion; received '$Version'"
}
$Version = $sourceVersion
$extension = $extensionText | ConvertFrom-Json
$stage = Assert-ChildPath (Join-Path $root "release\ICompression-$Version-windows-x64") (Join-Path $root 'release')
$archive = "$stage.zip"
$reuseBuild = $PSBoundParameters.ContainsKey('BuildDirectory')
$workspace = Read-ToolOutput 'git' @('-C', $root, 'rev-parse', '--show-toplevel')
$workspace = [IO.Path]::GetFullPath($workspace)
if ($reuseBuild -and [string]::IsNullOrWhiteSpace($BuildDirectory)) { throw 'BuildDirectory must not be empty' }
$build = Assert-ChildPath $(if ($reuseBuild) { $BuildDirectory } else { Join-Path $root 'out\release-build' }) $workspace
if ($build -ieq $root) { throw 'BuildDirectory must not be the source directory' }
if ($PSBoundParameters.ContainsKey('GameMakerCacheDirectory')) {
    if ([string]::IsNullOrWhiteSpace($GameMakerCacheDirectory)) { throw 'GameMakerCacheDirectory must not be empty' }
    $GameMakerCacheDirectory = Assert-ChildPath $GameMakerCacheDirectory $workspace
    if (!(Test-Path -LiteralPath $GameMakerCacheDirectory -PathType Container)) {
        throw "GameMakerCacheDirectory must be an existing cache directory: $GameMakerCacheDirectory"
    }
}
$cachePath = Join-Path $build 'CMakeCache.txt'
if ($reuseBuild) {
    if (!(Test-Path -LiteralPath $cachePath -PathType Leaf)) { throw "BuildDirectory must be an existing configured CMake tree: $build" }
    $cache = Get-Content -Raw -LiteralPath $cachePath
    $cachedSource = Read-CacheValue $cache 'CMAKE_HOME_DIRECTORY'
    if (!$cachedSource -or [IO.Path]::GetFullPath($cachedSource).TrimEnd('\', '/') -ine $root) {
        throw "BuildDirectory belongs to a different source directory: $cachedSource"
    }
    if ((Read-CacheValue $cache 'CMAKE_GENERATOR') -cne $Generator) { throw "BuildDirectory generator does not match $Generator" }
}

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
$gmCliVersion = Read-ToolOutput 'gm-cli' @('--version')
$gitVersion = Read-ToolOutput 'git' @('--version')

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

if (!$reuseBuild) { Remove-ReleaseDirectory $build $workspace }
$configureArgs = @('-S', $root, '-B', $build, '-G', $Generator, '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL', "-DEXT_OUTPUT_DIR=$root\project\extensions\ICompression")
if ($Generator -like 'Visual Studio *') { $configureArgs += @('-A', 'x64') }
& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }
$buildArgs = @('--build', $build, '--config', 'Release')
if ($reuseBuild) { $buildArgs += '--clean-first' }
& cmake @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'CMake build failed' }

$dllPath = Join-Path $root 'project\extensions\ICompression\ICompression.dll'
$dllVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($dllPath)
if ($dllVersion.FileVersion -cne $Version -or $dllVersion.ProductVersion -cne $Version) {
    throw "DLL version does not match extensionVersion $Version"
}
$dllBytes = [IO.File]::ReadAllBytes($dllPath)
$peOffset = [BitConverter]::ToInt32($dllBytes, 0x3c)
if ($peOffset -lt 0 -or $peOffset + 6 -gt $dllBytes.Length -or
    [BitConverter]::ToUInt32($dllBytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($dllBytes, $peOffset + 4) -ne 0x8664) { throw 'Release DLL is not Windows x64' }

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

$revision = Read-ToolOutput 'git' @('-C', $root, 'rev-parse', '--verify', 'HEAD')
$dirty = (Read-ToolOutput 'git' @('-C', $root, 'status', '--porcelain', '--untracked-files=normal')).Length -gt 0
$runtimeVersions = @([regex]::Matches($testOutput, 'runtime-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$compilerInfo = Get-ChildItem -LiteralPath (Join-Path $build 'CMakeFiles') -Filter CMakeCXXCompiler.cmake -Recurse |
    Select-Object -First 1 | Get-Content -Raw
$compilerVersion = [regex]::Match($compilerInfo, 'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)').Groups[1].Value
$cache = Get-Content -Raw -LiteralPath $cachePath
[ordered]@{
    extension_version = $Version
    source_revision = $revision
    source_has_local_changes = $dirty
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    tools = [ordered]@{ extgen = $extgenVersion; cmake = $cmakeVersion; gm_cli = $gmCliVersion
        powershell = $PSVersionTable.PSVersion.ToString(); git = $gitVersion; cxx_compiler = $compilerVersion }
    generator = $Generator
    platform = 'windows-x64'
    visual_studio_toolset = Read-CacheValue $cache 'CMAKE_VS_PLATFORM_TOOLSET'
    gamemaker_runtime_versions = $runtimeVersions
    tests = [ordered]@{ total = [int]$summaries[-1].Groups[1].Value; passed = [int]$summaries[-1].Groups[2].Value; failed = 0 }
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stage 'build-info.json') -Encoding utf8NoBOM

Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName |
    Get-FileHash -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash)  $($_.Path.Substring($stage.Length + 1).Replace('\', '/'))" } |
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Encoding ascii
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -CompressionLevel Optimal
$archiveHash = Get-FileHash -Algorithm SHA256 -LiteralPath $archive
"$($archiveHash.Hash)  $(Split-Path -Leaf $archive)" |
    Set-Content -LiteralPath "${archive}.sha256" -Encoding ascii
$archiveHash
