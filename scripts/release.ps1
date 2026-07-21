param(
    [string]$Version = "1.0.1",
    [string]$Generator = "Visual Studio 18 2026"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "project\ICompression.yyp"
$stage = Join-Path $root "release\ICompression-$Version-windows-x64"
$archive = "$stage.zip"
$build = Join-Path $root "out\release-build"

$extgenVersion = (& extgen --version 2>&1 | Out-String).Trim()
if ($extgenVersion -notmatch "extgen v1\.225bddc") {
    throw "Expected extgen v1.225bddc, found: $extgenVersion"
}

& extgen --config (Join-Path $root "config.json")
if ($LASTEXITCODE -ne 0) { throw "extgen failed" }

if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Recurse -Force }
& cmake -S $root -B $build -G $Generator -A x64 `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL `
    -DEXT_OUTPUT_DIR="$root\project\extensions\ICompression"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
& cmake --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }

& gm-cli run $project --target=windows --runtime=vm
if ($LASTEXITCODE -ne 0) { throw "GameMaker VM tests failed" }

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

$files = @(
    "README.md",
    "LICENSE",
    "CHANGELOG.md",
    "THIRD_PARTY_NOTICES.md",
    "project\extensions\ICompression\ICompression.yy",
    "project\extensions\ICompression\ICompression.ext",
    "project\extensions\ICompression\ICompression.dll",
    "project\scripts\ICompression_API\ICompression_API.yy",
    "project\scripts\ICompression_API\ICompression_API.gml",
    "project\scripts\GMExtCore\GMExtCore.yy",
    "project\scripts\GMExtCore\GMExtCore.gml"
)

foreach ($relative in $files) {
    $source = Join-Path $root $relative
    if (!(Test-Path -LiteralPath $source)) { throw "Missing release file: $relative" }
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

$licenses = @{
    "zlib-LICENSE.txt" = "out\release-build\_deps\zlib-src\LICENSE"
    "bzip2-LICENSE.txt" = "out\release-build\_deps\bzip2-src\LICENSE"
    "zstd-LICENSE.txt" = "out\release-build\_deps\zstd-src\LICENSE"
    "lz4-LICENSE.txt" = "out\release-build\_deps\lz4-src\lib\LICENSE"
    "xz-COPYING.txt" = "out\release-build\_deps\xz-src\COPYING"
    "libarchive-COPYING.txt" = "out\release-build\_deps\libarchive-src\COPYING"
}

$licenseDir = Join-Path $stage "licenses"
New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
foreach ($item in $licenses.GetEnumerator()) {
    $source = Join-Path $root $item.Value
    if (!(Test-Path -LiteralPath $source)) { throw "Missing dependency license: $($item.Value)" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $licenseDir $item.Key)
}

Get-ChildItem -LiteralPath $stage -Recurse -File |
    Get-FileHash -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash)  $($_.Path.Substring($stage.Length + 1).Replace('\', '/'))" } |
    Set-Content -LiteralPath (Join-Path $stage "SHA256SUMS.txt") -Encoding ascii

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archive -CompressionLevel Optimal
$archiveHash = Get-FileHash -Algorithm SHA256 -LiteralPath $archive
"$($archiveHash.Hash)  $(Split-Path -Leaf $archive)" |
    Set-Content -LiteralPath "${archive}.sha256" -Encoding ascii
$archiveHash
