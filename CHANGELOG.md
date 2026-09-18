# Changelog

## 1.0.10.1 — Pre-release (2026-09-18)

- Test the suite under GameMaker YYC in addition to the VM (39/39 each); both runners are now covered.
- Add opt-in `-YycTests`/`-YycVsDevCmd` to the release script: runs the suite a second time under YYC with the same gating, records `yyc_tests` in build-info, validates that the VsDevCmd.bat file (not the VS root) is given, and hints at antivirus quarantine when a fresh YYC exe is blocked from starting.
- Extend release preflight to 82 checks.

## 1.0.9.1 — Pre-release (2026-09-18)

- Document that archive reading accepts every libarchive format (cpio, ISO 9660, CAB, LHA, XAR, mtree, WARC, and more), while creation stays ZIP/7z/tar and detection reports other formats as `Raw`.
- Add a cpio read/extract regression test pinning the documented reading capability (39 tests total).

## 1.0.8.4 — Pre-release (2026-09-18)

- Stream file API operations in 1 MiB blocks instead of reading whole files into memory; the 1 GiB input cap is removed.
- Write file API outputs to a temporary file and rename on success, so failures never leave partial or clobbered outputs.
- Keep single-layer decompression semantics identical in the streaming path (one filter, format match, full consumption, trailing-data rejection, valid empty streams).
- Add a 300 MiB file round-trip test, Raw byte-copy test, and failure-cleanliness tests (38 tests total).

## 1.0.7.1 — Pre-release (2026-09-18)

- Clarify that `IC_BUILD_STATE_DIR` is a CMake cache variable passed with `-D` at configure time, not an environment variable.
- Document the 256 MiB Raw decompression output cap.

## 1.0.6.1 — Pre-release (2026-09-18)

- Detect a broken build-output sync before packaging: hash the build-tree DLL against the extension-folder DLL and abort when they differ.
- Re-verify every produced archive after creation (sidecar hash, per-file manifest checksums, required-resource list, version agreement); a failed check fails the release.
- Add negative tar-header detection tests (wrong checksum, truncated header, zero block) for both buffer and file detection (35 tests total).
- Extend release preflight to 70 checks.

## 1.0.5.2 — Pre-release (2026-09-18)

- Keep the specific scan-limit error when `ic_extract_buf` also misses the requested entry, instead of overwriting it with "not found".
- Truncate entry paths embedded in extraction error messages to 256 bytes (UTF-8 boundary safe) so crafted archives cannot produce megabyte-long messages.
- Reject NTFS alternate-data-stream syntax, DOS device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9), and trailing dot/space segments in extraction entry paths.
- Document that listed `compressed_size`/`crc32` are always unknown (-1/0) because libarchive exposes neither per entry.
- Add regression coverage for all of the above (34 tests total).

## 1.0.4.5 — Pre-release (2026-09-17)

- Add regression tests for extraction rejection of absolute paths, `..` traversal, symlinks, hardlinks, and special files, plus boundary tests for entry path length, listing path length, entry scan count, and non-sparse entry size limits.
- Guard every exported function so no exception can escape into the GameMaker runner, and reject file API inputs larger than 1 GiB before reading them.
- Extend release preflight to 62 checks covering the test-summary gate, credential exclusion, staging contents, checksums, and build information.
- Advance the source extension version seed to the shipped version after each successful release, never rewinding a newer seed, so fresh clones cannot re-issue a released build number.
- Fail the release when the GameMaker runtime version is missing from the test log.
- Rewrite the stale diagnostics script for the buffer-based detection API and align the generated API script path casing.
- Work around a Windows VM runner crash when probing overlong paths in tests.

## 1.0.3.2 — Pre-release (2026-09-16)

- Automatically increment the fourth version field after each successful DLL link, including local builds.
- Keep counters outside build directories; share them between configurations and build trees, and start new functional versions at build 1.
- Preserve the counter on failed and unchanged builds, and reject missing or corrupt recorded state.
- Add DLL build receipts with version, hash and source provenance; package existing artifacts with `-OnlyPackage` without increasing the count.
- Update staged extension versions through ResourceTool MCP while preserving source resource files.

## 1.0.3.1 — Pre-release (2026-09-15)

- Count sparse file holes toward extraction limits before creating or extending output files.
- Add real sparse-archive boundary tests covering exactly 1 GiB and rejection before a fifth 256 MiB file.
- Preserve all four version fields (project.version1.version2.build) across extension metadata, DLL, and package names; validate the release toolchain and package contents.
- Fetch pinned dependency commits without shallow-clone restrictions.
- Preserve arbitrary binary data and nested archives/streams during single-layer decompression.
- Use a seekable memory reader so 7z buffer compression/decompression can round-trip.
- Reject mismatched formats, absent frames, and trailing data instead of treating them as raw input.
- Separate compression failure from valid empty output, including unsupported RAR writes.
- Report the correct final-page status for archive listings with multiples of 16 entries.
- Detect empty ZIP archives and validate complete tar headers in both buffer and file detection.
- Patch libarchive's LZ4 writer to initialize empty streams before finalizing their checksums.
- Add regression coverage for binary payloads, empty streams, nested compression, invalid input, and pagination boundaries.

## 1.0.1

- Added binary-safe range compression, decompression, archive-add, and extraction APIs.
- Added paginated archive listing.
- Added extraction size, entry count, path length, and open-handle limits.
- Rejected traversal, symlink, hardlink, and special-file extraction.
- Added extension-shutdown cleanup for abandoned archive handles.
- Improved Base64 validation and native I/O error handling.
- Renamed the generated API resource to `ICompression_API`.
- Removed unused large archive fixtures from the distributable project.
- Added deterministic dependency revisions and release automation.
