// Native smoke test for the ICompression extension binary.
//
// The GameMaker runner needs a windowed GUI session, which headless CI
// runners cannot provide (the macOS VM runner dies in GR_D3D_Init with a
// null OpenGL context before any test code runs). This harness validates the
// built library directly: dlopen, call the exported C ABI for archive and
// stream round-trips, and compare bytes. No GameMaker runtime required.
//
// Usage: native-smoke <path-to-library> <workdir>
// Exit code 0 and "SMOKE PASS" on success; non-zero otherwise.

#include <dlfcn.h>
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

typedef double (*fn_ssd_d)(const char*, const char*, double, double);
typedef double (*fn_ssd)(const char*, const char*, double);
typedef double (*fn_sd_d)(const char*, double);
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

    fn_sd_d ic_create = (fn_sd_d)require_symbol(lib, "__EXT_NATIVE__ic_create");
    fn_dss ic_add_data = (fn_dss)require_symbol(lib, "__EXT_NATIVE__ic_add_data");
    fn_d ic_close = (fn_d)require_symbol(lib, "__EXT_NATIVE__ic_close");
    fn_ss_s ic_extract_mem = (fn_ss_s)require_symbol(lib, "__EXT_NATIVE__ic_extract_mem");
    fn_sss ic_extract_file = (fn_sss)require_symbol(lib, "__EXT_NATIVE__ic_extract_file");
    fn_ssd_d ic_compress_file = (fn_ssd_d)require_symbol(lib, "__EXT_NATIVE__ic_compress_file");
    fn_ssd ic_decompress_file = (fn_ssd)require_symbol(lib, "__EXT_NATIVE__ic_decompress_file");
    fn_v ic_shutdown = (fn_v)require_symbol(lib, "__EXT_NATIVE__ic_shutdown");
    puts("SMOKE OK   all symbols resolve");

    const double zip_format = 0.0; // CompressionFormat.Zip
    const double zstd_format = 3.0; // CompressionFormat.Zstd
    const double default_level = 1.0; // CompressionLevel.Default

    double handle = ic_create(zip_path, zip_format);
    check(handle >= 0.0, "ic_create returns a handle");
    check(ic_add_data(handle, "hello.txt", "Hello, macOS!") == 1.0, "ic_add_data hello.txt");
    check(ic_add_data(handle, "dir/note.txt", "nested data") == 1.0, "ic_add_data dir/note.txt");
    check(ic_close(handle) == 1.0, "ic_close finalizes the archive");

    const char* mem = ic_extract_mem(zip_path, "dir/note.txt");
    check(mem && strcmp(mem, "nested data") == 0, "ic_extract_mem round-trips a nested entry");

    check(ic_extract_file(zip_path, "hello.txt", mem_out) == 1.0, "ic_extract_file writes the entry");
    char buf[64];
    check(read_file(mem_out, buf, sizeof buf) == 13 && memcmp(buf, "Hello, macOS!", 13) == 0,
        "extracted bytes match the original");

    unsigned char src[65537];
    for (size_t i = 0; i < sizeof src; ++i) src[i] = (unsigned char)(i * 31u + 7u);
    check(write_file(raw_src, src, sizeof src), "fixture source written");
    check(ic_compress_file(raw_src, raw_gz, zstd_format, default_level) == 1.0,
        "ic_compress_file zstd succeeds");
    check(ic_decompress_file(raw_gz, raw_back, zstd_format) == 1.0,
        "ic_decompress_file zstd succeeds");
    unsigned char back[sizeof src];
    check(read_file(raw_back, back, sizeof back) == (long)sizeof src && memcmp(src, back, sizeof src) == 0,
        "stream round-trip is byte identical");

    check(ic_decompress_file(zip_path, raw_back, zstd_format) == 0.0,
        "mismatched format is rejected, not treated as raw");

    ic_shutdown();
    puts("SMOKE OK   ic_shutdown");

    if (failures) {
        printf("SMOKE RESULT: %d check(s) failed\n", failures);
        return 1;
    }
    puts("SMOKE PASS");
    return 0;
}
