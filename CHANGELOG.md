# Changelog

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
