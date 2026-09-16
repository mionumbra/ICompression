#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Binary,
    [Parameter(Mandatory)][string]$MetadataPath,
    [Parameter(Mandatory)][string]$StateDirectory,
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$Configuration = 'Release',
    [string]$CompilerVersion = '',
    [string]$Generator = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsWindows) { throw 'Automatic DLL build numbering currently requires Windows.' }
$Binary = [IO.Path]::GetFullPath($Binary)
$MetadataPath = [IO.Path]::GetFullPath($MetadataPath)
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (!(Test-Path -LiteralPath $Binary -PathType Leaf)) { throw "Linked DLL is missing: $Binary" }
if ([IO.Path]::GetExtension($Binary) -ine '.dll') { throw 'Build counter only stamps DLL artifacts.' }
$fields = [regex]::Matches([IO.File]::ReadAllText($MetadataPath), '"extensionVersion"\s*:\s*"([^"]*)"')
if ($fields.Count -ne 1) { throw 'Expected one extensionVersion in extension metadata.' }
$metadataVersion = $fields[0].Groups[1].Value
if ($metadataVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw 'extensionVersion must use project.version1.version2.build.'
}
$parts = $metadataVersion.Split('.')
foreach ($part in $parts) { if ($part.Length -gt 5 -or [int]$part -gt 65535) { throw 'Version fields must be at most 65535.' } }
$baseVersion = $parts[0..2] -join '.'
$binaryVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Binary).FileVersion
if (!$binaryVersion -or ($binaryVersion.Split('.')[0..2] -join '.') -cne $baseVersion) {
    throw 'The linked DLL base version does not match the source metadata.'
}

function Write-AtomicText([string]$Path, [string]$Text) {
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Copy-IfChanged([string]$From, [string]$To) {
    if ([IO.Path]::GetFullPath($From) -ieq [IO.Path]::GetFullPath($To)) { return }
    if ((Test-Path -LiteralPath $To -PathType Leaf) -and
        (Get-FileHash -LiteralPath $From -Algorithm SHA256).Hash -ceq (Get-FileHash -LiteralPath $To -Algorithm SHA256).Hash) { return }
    $temporary = $To + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try { [IO.File]::Copy($From, $temporary); [IO.File]::Move($temporary, $To, $true) }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Sync-Artifacts($Receipt) {
    $json = $Receipt | ConvertTo-Json -Depth 12
    $receiptPath = "$Binary.build.json"
    if (!(Test-Path -LiteralPath $receiptPath) -or [IO.File]::ReadAllText($receiptPath) -cne $json) {
        Write-AtomicText $receiptPath $json
    }
    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $destination = Join-Path $OutputDirectory ([IO.Path]::GetFileName($Binary))
    Copy-IfChanged $Binary $destination
    Copy-IfChanged $receiptPath "$destination.build.json"
}

[IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
$statePath = Join-Path $StateDirectory 'counter.json'
$lockPath = Join-Path $StateDirectory 'counter.lock'
$lock = $null
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while (!$lock) {
    try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch [IO.IOException] {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for another build to finish assigning its version.' }
        Start-Sleep -Milliseconds 100
    }
}
try {
    $freshState = !(Test-Path -LiteralPath $statePath -PathType Leaf)
    if ($freshState) {
        $outputReceipt = Join-Path $OutputDirectory ([IO.Path]::GetFileName($Binary) + '.build.json')
        if ((Test-Path -LiteralPath "$Binary.build.json") -or (Test-Path -LiteralPath $outputReceipt)) {
            throw "Build history exists but $statePath is missing. Restore the counter state before building; numbering will not silently restart."
        }
        $state = @{ schema_version = 1; last_builds = @{}; artifacts = @{} }
    }
    else {
        try { $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json -AsHashtable }
        catch { throw "Cannot read build counter; restore $statePath rather than silently restarting numbering." }
        if (!$state.Contains('schema_version') -or $state.schema_version -ne 1 -or
            !$state.Contains('last_builds') -or $state.last_builds -isnot [Collections.IDictionary] -or
            !$state.Contains('artifacts') -or $state.artifacts -isnot [Collections.IDictionary]) { throw 'Invalid build counter state; refusing to reset it.' }
    }
    $artifactKey = $Binary.ToLowerInvariant()
    $currentHash = (Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash
    $currentTicks = [IO.File]::GetLastWriteTimeUtc($Binary).Ticks.ToString()
    if ($state.artifacts.Contains($artifactKey)) {
        $previous = $state.artifacts[$artifactKey]
        if ($previous.sha256 -ceq $currentHash -and $previous.binary_write_ticks -ceq $currentTicks -and
            $previous.base_version -ceq $baseVersion -and $previous.version -ceq $binaryVersion) {
            Sync-Artifacts $previous
            Write-Output "ICompression build unchanged: $($previous.version)"
            return
        }
    }
    # Bootstrap from the last checked-in version on first adoption. Once state
    # exists, an unseen three-field base starts at 1 regardless of its old suffix.
    $last = 0
    if ($state.last_builds.Contains($baseVersion)) {
        $lastText = [string]$state.last_builds[$baseVersion]
        if ($lastText -notmatch '^(0|[1-9][0-9]*)$' -or $lastText.Length -gt 5 -or [int]$lastText -gt 65535) {
            throw 'Invalid persisted build number; refusing to reset it.'
        }
        $last = [int]$lastText
    } elseif ($freshState) { $last = [int]$parts[3] }
    if ($last -ge 65535) { throw 'Build number exhausted; increment the functional version before compiling again.' }
    $next = $last + 1
    $version = "$baseVersion.$next"
    $temporaryDll = Join-Path ([IO.Path]::GetDirectoryName($Binary)) ('.ic-stamp-' + [guid]::NewGuid().ToString('N') + '.dll')
    $backupDll = "$temporaryDll.backup"
    $replaced = $false
    $committed = $false
    try {
        [IO.File]::Copy($Binary, $temporaryDll)
        Add-Type -Path (Join-Path $PSScriptRoot 'VersionResource.cs')
        [ICompressionBuild.VersionResource]::Stamp($temporaryDll, $version)
        $stampedVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($temporaryDll)
        if ($stampedVersion.FileVersion -cne $version -or $stampedVersion.ProductVersion -cne $version) {
            throw 'Stamped DLL version did not verify.'
        }
        $revision = $null
        $dirty = $true
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $revisionOutput = & git -C $SourceDirectory rev-parse --verify HEAD 2>$null
            if ($LASTEXITCODE -eq 0) {
                $revision = ($revisionOutput | Out-String).Trim()
                $statusOutput = & git -C $SourceDirectory status --porcelain --untracked-files=normal 2>$null
                if ($LASTEXITCODE -eq 0) { $dirty = ![string]::IsNullOrWhiteSpace(($statusOutput | Out-String)) }
            }
        }
        $receipt = [ordered]@{
            schema_version = 1
            base_version = $baseVersion
            version = $version
            build_number = $next
            sha256 = (Get-FileHash -LiteralPath $temporaryDll -Algorithm SHA256).Hash
            configuration = $Configuration
            source_revision = $revision
            source_has_local_changes = $dirty
            built_at_utc = [DateTime]::UtcNow.ToString('o')
            cxx_compiler = $CompilerVersion
            generator = $Generator
            binary_write_ticks = ''
        }
        [IO.File]::Replace($temporaryDll, $Binary, $backupDll)
        $replaced = $true
        $receipt.binary_write_ticks = [IO.File]::GetLastWriteTimeUtc($Binary).Ticks.ToString()
        $state.last_builds[$baseVersion] = $next
        $state.artifacts[$artifactKey] = $receipt
        Write-AtomicText $statePath ($state | ConvertTo-Json -Depth 20)
        $committed = $true
        # A later copy failure can be retried from this receipt without counting
        # the same already-linked artifact again.
        Sync-Artifacts $receipt
        Write-Output "ICompression compiled version: $version"
    } catch {
        if ($replaced -and !$committed -and [IO.File]::Exists($backupDll)) { [IO.File]::Move($backupDll, $Binary, $true) }
        throw
    } finally {
        foreach ($temporary in @($temporaryDll, $backupDll)) { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    }
} finally { $lock.Dispose() }
