# Changelog

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
