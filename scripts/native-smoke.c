// Native smoke test for the ICompression extension binary.
//
// The GameMaker runner needs a windowed GUI session, which headless CI
// runners cannot provide (the macOS VM runner dies in GR_D3D_Init with a
// null OpenGL context before any test code runs). This harness validates the
// built library directly through the exported C ABI — the same calls the
// generated GameMaker wrappers make, including the packed-arguments wire
// protocol (u32 length + NUL-terminated string, u64 enum/real, s32 int32,
// no per-field tags). No GameMaker runtime required.
//
// Usage: native-smoke <path-to-library> <workdir>
// Exit code 0 and "SMOKE PASS" on success; non-zero otherwise.

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

static void check(int condition, const char* what)
{
    if (condition) {
        printf("SMOKE OK   %s\n", what);
    } else {
        printf("SMOKE FAIL %s\n", what);
        failures++;
    }
}

static void* require_symbol(void* lib, const char* name)
{
    void* p = dlsym(lib, name);
    if (!p) {
        fprintf(stderr, "SMOKE FAIL missing symbol %s\n", name);
        exit(2);
    }
    return p;
}

// ---- packed-args wire writer (matches the generated GML wrappers) ----

static uint8_t args_buf[8192];
static size_t args_len;

static void args_reset(void) { args_len = 0; }

static void args_u32(uint32_t v)
{
    memcpy(args_buf + args_len, &v, sizeof v);
    args_len += sizeof v;
}

static void args_u64(uint64_t v)
{
    memcpy(args_buf + args_len, &v, sizeof v);
    args_len += sizeof v;
}

static void args_s32(int32_t v)
{
    memcpy(args_buf + args_len, &v, sizeof v);
    args_len += sizeof v;
}

static void args_string(const char* s)
{
    const size_t n = strlen(s);
    args_u32((uint32_t)n);
    memcpy(args_buf + args_len, s, n);
    args_len += n;
    args_buf[args_len++] = 0;
}

static int write_file(const char* path, const void* data, size_t size)
{
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    const int ok = fwrite(data, 1, size, f) == size;
    fclose(f);
    return ok;
}

static long read_file(const char* path, void* data, long capacity)
{
    FILE* f = fopen(path, "rb");
    if (!f) return -1;
    const long size = (long)fread(data, 1, (size_t)capacity, f);
    fclose(f);
    return size;
}

typedef double (*fn_wire_d)(char*, double);
typedef char* (*fn_wire_s)(char*, double);
typedef double (*fn_d)(double);
typedef double (*fn_dss)(double, const char*, const char*);
typedef double (*fn_sss)(const char*, const char*, const char*);
typedef char* (*fn_ss_s)(const char*, const char*);
typedef double (*fn_v)(void);

int main(int argc, char** argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: native-smoke <library> <workdir>\n");
        return 2;
    }
    char zip_path[1024], mem_out[1024], raw_src[1024], raw_gz[1024], raw_back[1024];
    snprintf(zip_path, sizeof zip_path, "%s/smoke.zip", argv[2]);
    snprintf(mem_out, sizeof mem_out, "%s/hello.txt", argv[2]);
    snprintf(raw_src, sizeof raw_src, "%s/source.bin", argv[2]);
    snprintf(raw_gz, sizeof raw_gz, "%s/source.zst", argv[2]);
    snprintf(raw_back, sizeof raw_back, "%s/restored.bin", argv[2]);

    void* lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "SMOKE FAIL dlopen(%s): %s\n", argv[1], dlerror());
        return 1;
    }
    puts("SMOKE OK   dlopen");

    fn_wire_d ic_create = (fn_wire_d)require_symbol(lib, "__EXT_NATIVE__ic_create");
    fn_dss ic_add_data = (fn_dss)require_symbol(lib, "__EXT_NATIVE__ic_add_data");
    fn_d ic_close = (fn_d)require_symbol(lib, "__EXT_NATIVE__ic_close");
    fn_ss_s ic_extract_mem = (fn_ss_s)require_symbol(lib, "__EXT_NATIVE__ic_extract_mem");
    fn_sss ic_extract_file = (fn_sss)require_symbol(lib, "__EXT_NATIVE__ic_extract_file");
    fn_wire_s ic_compress = (fn_wire_s)require_symbol(lib, "__EXT_NATIVE__ic_compress");
    fn_wire_s ic_decompress = (fn_wire_s)require_symbol(lib, "__EXT_NATIVE__ic_decompress");
    fn_wire_d ic_compress_file = (fn_wire_d)require_symbol(lib, "__EXT_NATIVE__ic_compress_file");
    fn_wire_d ic_decompress_file = (fn_wire_d)require_symbol(lib, "__EXT_NATIVE__ic_decompress_file");
    fn_v ic_shutdown = (fn_v)require_symbol(lib, "__EXT_NATIVE__ic_shutdown");
    puts("SMOKE OK   all symbols resolve");

    const uint64_t zip_format = 0; // CompressionFormat.Zip
    const uint64_t zstd_format = 3; // CompressionFormat.Zstd
    const int32_t default_level = 1; // CompressionLevel.Default

    // Archive write path through the wire protocol.
    args_reset();
    args_string(zip_path);
    args_u64(zip_format);
    double handle = ic_create((char*)args_buf, (double)args_len);
    check(handle >= 0.0, "ic_create returns a handle");
    check(ic_add_data(handle, "hello.txt", "Hello, macOS!") == 1.0, "ic_add_data hello.txt");
    check(ic_add_data(handle, "dir/note.txt", "nested data") == 1.0, "ic_add_data dir/note.txt");
    check(ic_close(handle) == 1.0, "ic_close finalizes the archive");

    // Archive read path through the direct exports.
    const char* mem = ic_extract_mem(zip_path, "dir/note.txt");
    check(mem && strcmp(mem, "nested data") == 0, "ic_extract_mem round-trips a nested entry");
    check(ic_extract_file(zip_path, "hello.txt", mem_out) == 1.0, "ic_extract_file writes the entry");
    char buf[64];
    check(read_file(mem_out, buf, sizeof buf) == 13 && memcmp(buf, "Hello, macOS!", 13) == 0,
        "extracted bytes match the original");

    // String stream round-trip through the wire protocol (Base64 text API).
    const char* text = "Hello, GameMaker smoke test!";
    args_reset();
    args_string(text);
    args_u64(zstd_format);
    args_s32(default_level);
    const char* packed = ic_compress((char*)args_buf, (double)args_len);
    check(packed && packed[0] != '\0' && strcmp(packed, text) != 0, "ic_compress returns Base64 text");
    args_reset();
    args_string(packed ? packed : "");
    args_u64(zstd_format);
    const char* restored = ic_decompress((char*)args_buf, (double)args_len);
    check(restored && strcmp(restored, text) == 0, "ic_decompress round-trips the string");

    // Mismatched format must fail, not pass data through.
    args_reset();
    args_string(packed ? packed : "");
    args_u64(2); // CompressionFormat.Gzip
    const char* wrong = ic_decompress((char*)args_buf, (double)args_len);
    check(wrong && wrong[0] == '\0', "mismatched format is rejected");

    // Streaming file APIs through the wire protocol.
    unsigned char src[65537];
    for (size_t i = 0; i < sizeof src; ++i) src[i] = (unsigned char)(i * 31u + 7u);
    check(write_file(raw_src, src, sizeof src), "fixture source written");
    args_reset();
    args_string(raw_src);
    args_string(raw_gz);
    args_u64(zstd_format);
    args_s32(default_level);
    check(ic_compress_file((char*)args_buf, (double)args_len) == 1.0, "ic_compress_file zstd succeeds");
    args_reset();
    args_string(raw_gz);
    args_string(raw_back);
    args_u64(zstd_format);
    check(ic_decompress_file((char*)args_buf, (double)args_len) == 1.0, "ic_decompress_file zstd succeeds");
    unsigned char back[sizeof src];
    check(read_file(raw_back, back, sizeof back) == (long)sizeof src && memcmp(src, back, sizeof src) == 0,
        "file stream round-trip is byte identical");

    // A ZIP file fed to the zstd decompressor must fail (single-layer rule).
    args_reset();
    args_string(zip_path);
    args_string(raw_back);
    args_u64(zstd_format);
    check(ic_decompress_file((char*)args_buf, (double)args_len) == 0.0,
        "zip-as-zstd is rejected, not treated as raw");

    ic_shutdown();
    puts("SMOKE OK   ic_shutdown");

    if (failures) {
        printf("SMOKE RESULT: %d check(s) failed\n", failures);
        return 1;
    }
    puts("SMOKE PASS");
    return 0;
}
