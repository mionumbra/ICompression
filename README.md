# ICompression

ICompression is a native compression, decompression, and archive extension for GameMaker.

## Support

- Platform: Windows x64
- GameMaker: tested with IDE 2026.0.0.16 and Runtime 2026.0.0.23
- Runner: Windows VM tested; YYC requires a configured GameMaker C++ toolchain
- Functional version: 1.0.3; CMake assigns the fourth field on each successful DLL build (see Building below).

Supported stream filters are gzip, bzip2, zstd, LZ4, and xz. ZIP, 7z, and tar archives can be created and read. RAR is detection/read-only through libarchive; RAR creation is not supported.

## Installation

The generated ZIP is a versioned resource bundle, not a `.yymps` file. To install it, copy the extension and script resource directories into a GameMaker project and add the three resources to that project's `.yyp`, or use GameMaker's Local Package workflow to create/import a `.yymps` from the staged resources. A complete release contains:

- `ICompression.dll`
- `ICompression.ext`
- the `ICompression` extension resource
- the `ICompression_API` generated script
- the `GMExtCore` generated runtime script

Do not copy only the DLL. The generated scripts provide the public typed GML API and native wire runtime.

## Examples

Text compression uses Base64 so the result is safe to store in a GameMaker string:

```gml
var compressed = ic_compress("Hello, GameMaker!", CompressionFormat.Zstd, CompressionLevel.Default);
var restored = ic_decompress(compressed, CompressionFormat.Zstd);
```

Use the range APIs for arbitrary binary data. String APIs are text-only and must not be used for data containing NUL bytes.

Decompression requires the supplied format to match the input and removes exactly one compression layer. ZIP/TAR bytes or a second compressed stream inside gzip, bzip2, zstd, LZ4, or xz are returned unchanged after that outer layer is removed. `Raw` copies bytes without interpreting them. Pass the actual compressed byte count to the range APIs; spare buffer capacity and trailing garbage are not part of a compressed stream. A valid compressed empty stream succeeds with zero output bytes, while missing or mismatched framing fails.

When explicitly using `Zip`, `SevenZ`, `Tar`, or `Rar` with the decompression APIs, the result is the first regular entry. Use archive extraction APIs when you need named entries or the complete archive.

```gml
var input = buffer_load("input.bin");
var compressed = buffer_create(buffer_get_size(input) + 1024, buffer_grow, 1);

var result = ic_compress_buf_range(
    input,
    0,
    buffer_get_size(input),
    compressed,
    0,
    CompressionFormat.Zstd,
    CompressionLevel.Default
);

if (!result.success) {
    show_debug_message(result.error_message);
}
```

Create an archive with binary data:

```gml
var handle = ic_create("save.zip", CompressionFormat.Zip);
if (handle >= 0) {
    ic_add_buf(handle, "save.dat", input, 0, buffer_get_size(input));
    ic_close(handle);
}
```

Large archive listings are paginated to keep native return values bounded:

```gml
var offset = 0;
repeat (65535) {
    var page = ic_list_page("save.zip", offset);
    if (!page.success) break;

    for (var i = 0; i < array_length(page.entries); ++i) {
        show_debug_message(page.entries[i].filename);
    }

    if (!page.has_more) break;
    offset = page.next_offset;
}
```

`ic_list()` remains available as a convenience for the first page only. Use `ic_list_page()` when archives may contain more than 16 entries. `has_more` is false on the final page, including a full 16-entry page.

## Limits And Safety

- Maximum decompressed size per entry: 256 MiB, including sparse-file holes
- Maximum total full-extraction output: 1 GiB, including sparse-file holes
- Maximum entries scanned: 65,535
- Maximum extraction path length: 4,096 UTF-8 bytes
- Maximum simultaneously open archive writers: 64
- Listing page size: 16 entries
- Listing path limit: 256 UTF-8 bytes
- Full extraction rejects absolute paths, `..`, symlinks, hardlinks, and special files

Extraction failure can leave files already written before the failure. Extract untrusted archives into a new temporary directory and rename it only after `ic_extract()` reports success.

## Building

Required tools:

- PowerShell 7 or newer and Git
- `extgen v1.d8c68bd`; the previously verified `v1.225bddc` is also accepted
- CMake 4.2 or newer for the default Visual Studio 2026 generator
- Visual Studio 2026 with the C++ toolset and a Windows SDK
- `gm-cli` (validated with 2.3.0) with a configured GameMaker account and license; the default runtime is downloaded automatically when needed

The DLL uses the dynamic Microsoft C/C++ runtime. End-user machines need a compatible Microsoft Visual C++ Redistributable; test the final archive on a clean Windows x64 machine before publishing.

Create a local release ZIP with:

```powershell
pwsh -File "scripts/release.ps1"
```

Version tags use `v<project>.<version1>.<version2>.<build>` (项目版本.版本号1.版本号2.编译次数). Project version `1` stays fixed; the next two fields identify the functional version. The fourth field counts successful DLL builds in this checkout, including local development builds. The leading `v` is used only for the Git tag.

CMake assigns the build number after a successful link. An unchanged build or a failed compilation does not increment it; a clean rebuild does. Debug/Release and different build directories for the same source checkout share the counter. Each new three-field base starts at build 1; returning to an older base resumes its recorded count to avoid duplicate numbers. On first adoption, the fourth field in the checked-in extension metadata is used as the existing build count, so the next build after `1.0.3.1` is `1.0.3.2`.

Counter state lives in `.build-state/counter.json`, outside `out/`, and survives clearing build directories. Back up `.build-state` when moving the checkout; it is local state, not synchronized between separate clones or computers. `IC_BUILD_STATE_DIR` can explicitly select a shared persistent location. Do not delete it to reset numbers: missing state with existing build receipts and corrupt state both stop the build. Increase the functional version instead. Counts cannot reconstruct builds made before this mechanism was enabled.

The source extension `.yy` supplies the first three fields and the bootstrap count. It is not rewritten after each compilation. The compiled DLL and its `.dll.build.json` receipt record the actual full version and SHA-256. Packaging checks the receipt and uses GameMaker's resource tool to set the staged extension metadata to that version. DLL, packaged extension, package filename and build information therefore agree. The optional `-Version` argument must match the compiled DLL's complete version.

The release script uses incremental builds, verifies the DLL version and x64 architecture, and runs the complete VM test suite. Both the process exit status and a successful, nonempty test summary are required. GameMaker uses the runtime selected by the user's gm-cli configuration; the script does not pin a runtime version.

To reuse an existing CMake tree and its downloaded dependencies:

```powershell
pwsh -File "scripts/release.ps1" -BuildDirectory "out/release-build"
```

The selected tree must be within the Git workspace and already configured for the same source directory and generator. A source copy may use a matching sibling build directory within the workspace. `-GameMakerCacheDirectory "project/.gmcache"` optionally shares an existing GameMaker cache within the workspace; cache credentials are never packaged. CI may pass another installed generator with `-Generator`; CMake 3.21 or newer is sufficient for Visual Studio 2022.

To package an existing Release DLL without generating or compiling anything, use:

```powershell
pwsh -File "scripts/release.ps1" -OnlyPackage -BuildDirectory "out/release-build"
```

This still verifies the DLL receipt and runs VM tests; the build count remains unchanged. `-ResourceToolPath` may select an already installed official `ResourceTool.exe`; otherwise gm-cli starts the resource MCP. The staged project is temporary and the source `.yy` is left untouched. Normal release generation can rewrite generated source files and cause a real rebuild; use `-OnlyPackage` when reusing an existing build is intended.

The staged bundle and ZIP are written under `release/`; nothing is uploaded. The bundle includes dependency license texts, `build-info.json` with source revision, tool/compiler versions, the GameMaker runtime used, and test counts, plus SHA-256 checksums. A separate `.zip.sha256` checks the complete archive. Timestamps and compiler output mean repeated builds are not promised to produce identical ZIP bytes.

Run isolated release preflight checks without compiling or running GameMaker:

```powershell
pwsh -File "scripts/test-release-preflight.ps1"
```

Exercise automatic numbering with small, real CMake/MSVC builds (including failure, clean rebuild, another build directory, and version reset):

```powershell
pwsh -File "scripts/test-build-counter.ps1"
```

For development iteration against an already configured build tree:

```powershell
extgen --config "config.json"
cmake --build --preset win-x64-release
gm-cli run "project/ICompression.yyp" --target=windows --runtime=vm
```

## Source Ownership

- Edit `api.gmidl`, `src/`, and `third_party/CMakeLists.txt`.
- Do not edit `code_gen/`, generated GML, root CMake files, or generated injector files manually.
- Regenerate after every GMIDL change.

Dependencies and immutable revisions are listed in `THIRD_PARTY_NOTICES.md`.

## License

ICompression is licensed under the MIT License. See `LICENSE`.
