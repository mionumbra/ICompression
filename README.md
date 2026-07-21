# ICompression

ICompression is a native compression, decompression, and archive extension for GameMaker.

## Support

- Platform: Windows x64
- GameMaker: tested with IDE 2026.0.0.16 and Runtime 2026.0.0.23
- Runner: Windows VM tested; YYC requires a configured GameMaker C++ toolchain
- Extension version: 1.0.1

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

`ic_list()` remains available as a convenience for the first page only. Use `ic_list_page()` when archives may contain more than 16 entries.

## Limits And Safety

- Maximum decompressed size per entry: 256 MiB
- Maximum total full-extraction output: 1 GiB
- Maximum entries scanned: 65,535
- Maximum extraction path length: 4,096 UTF-8 bytes
- Maximum simultaneously open archive writers: 64
- Listing page size: 16 entries
- Listing path limit: 256 UTF-8 bytes
- Full extraction rejects absolute paths, `..`, symlinks, hardlinks, and special files

Extraction failure can leave files already written before the failure. Extract untrusted archives into a new temporary directory and rename it only after `ic_extract()` reports success.

## Building

Required tools:

- `extgen v1.225bddc` (GM-ExtensionGenerator v1.0.1)
- CMake 3.21 or newer
- Visual Studio 2026 with the current C++ toolset and a Windows SDK for the included release script
- `gm-cli` 2.2.0 for GameMaker validation

The DLL uses the dynamic Microsoft C/C++ runtime. End-user machines need a compatible Microsoft Visual C++ Redistributable; test the final archive on a clean Windows x64 machine before publishing.

The authoritative clean build and release command is:

```powershell
pwsh -File "scripts/release.ps1"
```

This command regenerates bindings, creates a fresh independent CMake tree, builds the DLL, and runs the project test suite. The test runner exits automatically; a failed assertion terminates the Runner with a nonzero result.

For development iteration against an already configured build tree:

```powershell
extgen --config "config.json"
cmake --build --preset win-x64-release
gm-cli run "project/ICompression.yyp" --target=windows --runtime=vm
```

The script verifies extgen, regenerates bindings, performs a clean independent build, runs the VM test suite, and creates a staged package with SHA-256 checksums under `release/`. CI may pass a different installed Visual Studio generator with `-Generator`.

## Source Ownership

- Edit `api.gmidl`, `src/`, and `third_party/CMakeLists.txt`.
- Do not edit `code_gen/`, generated GML, root CMake files, or generated injector files manually.
- Regenerate after every GMIDL change.

Dependencies and immutable revisions are listed in `THIRD_PARTY_NOTICES.md`.

## License

ICompression is licensed under the MIT License. See `LICENSE`.
