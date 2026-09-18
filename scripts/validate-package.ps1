#requires -Version 7.0
# Re-verify a packaged release archive: sidecar hash, every SHA256SUMS.txt
# entry against the archived bytes, manifest completeness, the required
# resource list, version agreement, and test metadata. With -StageDirectory,
# the staged bytes must also match the archived bytes exactly. Any mismatch
# throws; the archive is left in place for diagnosis.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [string]$StageDirectory
)
$ErrorActionPreference = 'Stop'
if ($ExpectedVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw "ExpectedVersion must use project.version1.version2.build: $ExpectedVersion"
}
if (!(Test-Path -LiteralPath $Archive -PathType Leaf)) { throw "Archive is missing: $Archive" }
if (!(Test-Path -LiteralPath "$Archive.sha256" -PathType Leaf)) { throw "Archive sidecar is missing: $Archive.sha256" }
if ($StageDirectory -and !(Test-Path -LiteralPath $StageDirectory -PathType Container)) {
    throw "Stage directory is missing: $StageDirectory"
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$expectedArchiveHash = (Get-Content -LiteralPath "$Archive.sha256" -Raw).Trim().Split(' ')[0]
$actualArchiveHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
if ($expectedArchiveHash -cne $actualArchiveHash) { throw 'ZIP checksum does not match its sidecar' }
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
    $files = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries) {
        if ($entry.Name -eq '') { continue }
        if (!$files.TryAdd($entry.FullName, $entry)) { throw "Duplicate ZIP entry: $($entry.FullName)" }
    }
    function Read-ZipText([string]$Path) {
        if (!$files.ContainsKey($Path)) { throw "Missing ZIP file: $Path" }
        $reader = [IO.StreamReader]::new($files[$Path].Open())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    function Get-ZipHash([string]$Path) {
        $stream = $files[$Path].Open()
        try { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) }
        finally { $stream.Dispose() }
    }
    $manifest = Read-ZipText 'SHA256SUMS.txt'
    $listed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in ($manifest -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $match = [regex]::Match($line, '^([0-9A-F]{64})  (.+)$')
        if (!$match.Success) { throw "Invalid checksum line: $line" }
        $path = $match.Groups[2].Value
        if (!$listed.Add($path) -or !$files.ContainsKey($path)) { throw "Missing or duplicate manifest entry: $path" }
        if ((Get-ZipHash $path) -cne $match.Groups[1].Value) { throw "ZIP file checksum does not match: $path" }
    }
    if ($files.Count -ne $listed.Count + 1) { throw 'ZIP contains files outside its checksum manifest' }
    foreach ($path in @('README.md', 'LICENSE', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md',
        'project/extensions/ICompression/ICompression.yy', 'project/extensions/ICompression/ICompression.ext',
        'project/extensions/ICompression/ICompression.dll', 'project/scripts/ICompression_API/ICompression_API.yy',
        'project/scripts/ICompression_API/ICompression_API.gml', 'project/scripts/GMExtCore/GMExtCore.yy',
        'project/scripts/GMExtCore/GMExtCore.gml', 'licenses/xz-COPYING.0BSD.txt',
        'licenses/libarchive-compress-reader.c.txt', 'licenses/libarchive-compress-writer.c.txt', 'build-info.json')) {
        if (!$files.ContainsKey($path)) { throw "Required release resource missing: $path" }
    }
    $metadata = (Read-ZipText 'project/extensions/ICompression/ICompression.yy') | ConvertFrom-Json
    $buildInfo = (Read-ZipText 'build-info.json') | ConvertFrom-Json
    if ($metadata.extensionVersion -cne $buildInfo.extension_version) { throw 'Package versions disagree' }
    if ($buildInfo.extension_version -cne $ExpectedVersion) { throw "Unexpected release version: $($buildInfo.extension_version)" }
    if ($buildInfo.tests.failed -ne 0 -or $buildInfo.tests.total -le 0 -or $buildInfo.tests.passed -ne $buildInfo.tests.total) {
        throw 'Release metadata does not record a fully passing test run'
    }
    if ($null -ne $buildInfo.PSObject.Properties['yyc_tests'] -and
        ($buildInfo.yyc_tests.failed -ne 0 -or $buildInfo.yyc_tests.total -le 0 -or $buildInfo.yyc_tests.passed -ne $buildInfo.yyc_tests.total)) {
        throw 'Release metadata does not record a fully passing YYC test run'
    }
    if (@($files.Keys | Where-Object { $_ -match '(^|/)(\.git|\.gmcache|\.mcp\.json|AGENTS\.md|CLAUDE\.md|gm-options\.json)(/|$)|licence\.plist' }).Count) {
        throw 'Cache, local settings, or a private license was packaged'
    }
    if ($StageDirectory) {
        $staged = @{}
        foreach ($item in (Get-ChildItem -LiteralPath $StageDirectory -Recurse -File)) {
            $staged[$item.FullName.Substring($StageDirectory.Length + 1).Replace('\', '/')] =
                (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
        if ($staged.Count -ne $files.Count) { throw 'Stage directory and ZIP contain different file sets' }
        foreach ($path in $staged.Keys) {
            if (!$files.ContainsKey($path)) { throw "Staged file is missing from the ZIP: $path" }
            if ($staged[$path] -cne (Get-ZipHash $path)) { throw "Staged file differs from its archived bytes: $path" }
        }
    }
    [pscustomobject]@{ Archive = $Archive; Version = $buildInfo.extension_version; Files = $files.Count
        CheckedFileHashes = $listed.Count; Tests = "$($buildInfo.tests.passed)/$($buildInfo.tests.total)"; SHA256 = $actualArchiveHash }
} finally { $zip.Dispose() }
