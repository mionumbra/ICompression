#include "ICompression_native.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#ifdef OS_WINDOWS
#include <windows.h>
#endif

using namespace gm::wire;
using namespace gm_structs;
using namespace gm_enums;

// =============================================================================
// Internal helpers
// =============================================================================

#ifdef OS_WINDOWS
// Convert UTF-8 path to wide string for Windows Unicode APIs
static std::wstring utf8_to_wide(std::string_view utf8)
{
    if (utf8.empty()) return {};
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    if (len <= 0) return {};
    std::wstring wide(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), wide.data(), len);
    return wide;
}

#define OPEN_ARCHIVE_READ(a, path, block) \
    archive_read_open_filename_w((a), utf8_to_wide(path).c_str(), (block))

#define OPEN_ARCHIVE_WRITE(a, path) \
    archive_write_open_filename_w((a), utf8_to_wide(path).c_str())

// On Windows, std::ifstream/ofstream accept wchar_t* (MSVC extension)
#define FOPEN_IFSTREAM(var, path, mode) std::ifstream var(utf8_to_wide(path).c_str(), mode)
#define FOPEN_OFSTREAM(var, path, mode) std::ofstream var(utf8_to_wide(path).c_str(), mode)
#else
#define OPEN_ARCHIVE_READ(a, path, block) \
    archive_read_open_filename((a), std::string(path).c_str(), (block))

#define OPEN_ARCHIVE_WRITE(a, path) \
    archive_write_open_filename((a), std::string(path).c_str())

#define FOPEN_IFSTREAM(var, path, mode) std::ifstream var(std::string(path), mode)
#define FOPEN_OFSTREAM(var, path, mode) std::ofstream var(std::string(path), mode)
#endif

// Map CompressionFormat to libarchive filter code
static int format_to_filter(CompressionFormat fmt)
{
    switch (fmt)
    {
    case CompressionFormat::Gzip:   return ARCHIVE_FILTER_GZIP;
    case CompressionFormat::Zstd:   return ARCHIVE_FILTER_ZSTD;
    case CompressionFormat::Lz4:    return ARCHIVE_FILTER_LZ4;
    case CompressionFormat::Xz:     return ARCHIVE_FILTER_XZ;
    case CompressionFormat::Raw:
    case CompressionFormat::Tar:    return ARCHIVE_FILTER_NONE;
    case CompressionFormat::Zip:
    case CompressionFormat::SevenZ: return ARCHIVE_FILTER_NONE;
    default:                        return ARCHIVE_FILTER_NONE;
    }
}

// Map CompressionFormat to libarchive format code
static int format_to_format_code(CompressionFormat fmt)
{
    switch (fmt)
    {
    case CompressionFormat::Zip:    return ARCHIVE_FORMAT_ZIP;
    case CompressionFormat::SevenZ: return ARCHIVE_FORMAT_7ZIP;
    case CompressionFormat::Tar:    return ARCHIVE_FORMAT_TAR;
    case CompressionFormat::Raw:    return ARCHIVE_FORMAT_RAW;
    default:                        return ARCHIVE_FORMAT_TAR_USTAR;
    }
}

// Map libarchive compression level
static int level_to_archive(int32_t level)
{
    return std::clamp(static_cast<int>(level), 1, 9);
}

// CompressionFormat to string
static const char* format_to_str(CompressionFormat fmt)
{
    switch (fmt)
    {
    case CompressionFormat::Zip:    return "ZIP";
    case CompressionFormat::SevenZ: return "7z";
    case CompressionFormat::Gzip:   return "gzip";
    case CompressionFormat::Zstd:   return "zstd";
    case CompressionFormat::Lz4:    return "lz4";
    case CompressionFormat::Xz:     return "xz";
    case CompressionFormat::Tar:    return "tar";
    case CompressionFormat::Raw:    return "raw";
    default:                        return "unknown";
    }
}

// Detect format from magic bytes
static CompressionFormat detect_from_magic(const std::string_view& data)
{
    if (data.size() < 4) return CompressionFormat::Raw;

    const auto* buf = reinterpret_cast<const uint8_t*>(data.data());

    if (data.size() >= 4 && buf[0] == 0x50 && buf[1] == 0x4B && buf[2] == 0x03 && buf[3] == 0x04)
        return CompressionFormat::Zip;

    if (data.size() >= 6 && buf[0] == 0x37 && buf[1] == 0x7A && buf[2] == 0xBC && buf[3] == 0xAF && buf[4] == 0x27 && buf[5] == 0x1C)
        return CompressionFormat::SevenZ;

    if (data.size() >= 2 && buf[0] == 0x1F && buf[1] == 0x8B)
        return CompressionFormat::Gzip;

    if (data.size() >= 4 && buf[0] == 0x28 && buf[1] == 0xB5 && buf[2] == 0x2F && buf[3] == 0xFD)
        return CompressionFormat::Zstd;

    if (data.size() >= 4 && buf[0] == 0x04 && buf[1] == 0x22 && buf[2] == 0x4D && buf[3] == 0x18)
        return CompressionFormat::Lz4;

    if (data.size() >= 6 && buf[0] == 0xFD && buf[1] == 0x37 && buf[2] == 0x7A && buf[3] == 0x58 && buf[4] == 0x5A && buf[5] == 0x00)
        return CompressionFormat::Xz;

    return CompressionFormat::Raw;
}

// Detect from file extension
static CompressionFormat detect_from_ext(const std::string_view& name)
{
    std::string ext;
    auto pos = name.rfind('.');
    if (pos != std::string_view::npos)
    {
        ext = std::string(name.substr(pos));
        std::transform(ext.begin(), ext.end(), ext.begin(),
            [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    }

    if (ext == ".zip")   return CompressionFormat::Zip;
    if (ext == ".7z")    return CompressionFormat::SevenZ;
    if (ext == ".gz" || ext == ".gzip") return CompressionFormat::Gzip;
    if (ext == ".zst" || ext == ".zstd") return CompressionFormat::Zstd;
    if (ext == ".lz4")   return CompressionFormat::Lz4;
    if (ext == ".xz")    return CompressionFormat::Xz;
    if (ext == ".tar")   return CompressionFormat::Tar;
    return CompressionFormat::Raw;
}

// Write callback for libarchive: writes to std::string
struct StringWriter
{
    std::string data;
};

static la_ssize_t string_writer_cb(struct archive*, void* client_data,
    const void* buf, size_t length)
{
    auto* sw = static_cast<StringWriter*>(client_data);
    sw->data.append(static_cast<const char*>(buf), length);
    return static_cast<la_ssize_t>(length);
}

static int string_writer_open_cb(struct archive*, void*) { return ARCHIVE_OK; }
static int string_writer_close_cb(struct archive*, void*) { return ARCHIVE_OK; }

// Read callback for libarchive: reads from std::string_view
struct StringReader
{
    std::string_view data;
    size_t pos = 0;
};

static la_ssize_t string_reader_cb(struct archive*, void* client_data,
    const void** buf)
{
    auto* sr = static_cast<StringReader*>(client_data);
    if (sr->pos >= sr->data.size())
    {
        *buf = nullptr;
        return 0;
    }
    *buf = sr->data.data() + sr->pos;
    la_ssize_t remaining = static_cast<la_ssize_t>(sr->data.size() - sr->pos);
    sr->pos = sr->data.size();
    return remaining;
}

static int string_reader_open_cb(struct archive*, void*) { return ARCHIVE_OK; }
static int string_reader_close_cb(struct archive*, void*) { return ARCHIVE_OK; }

// =============================================================================
// Stream compression / decompression
// =============================================================================

std::string ic_compress(std::string_view data, CompressionFormat format, int32_t level)
{
    struct archive* a = archive_write_new();
    if (!a)
    {
        LOG_ERROR("ic_compress: archive_write_new() returned null");
        return {};
    }

    if (format == CompressionFormat::Zip)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_zip(a);
        archive_write_set_format_option(a, "zip", "compression", "deflate");
        archive_write_set_format_option(a, "zip", "compression-level", std::to_string(level_to_archive(level)).c_str());
    }
    else if (format == CompressionFormat::SevenZ)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_7zip(a);
        archive_write_set_format_option(a, "7zip", "compression-level", std::to_string(level_to_archive(level)).c_str());
    }
    else if (format == CompressionFormat::Tar)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_pax_restricted(a);
    }
    else
    {
        // Stream compression (gzip, zstd, lz4, xz)
        archive_write_add_filter(a, format_to_filter(format));
        archive_write_set_format_raw(a);
        archive_write_set_bytes_per_block(a, 0);
        archive_write_set_bytes_in_last_block(a, 0);
        int c_level = level_to_archive(level);
        archive_write_set_filter_option(a, nullptr, "compression-level", std::to_string(c_level).c_str());
    }

    StringWriter sw;
    int r = archive_write_open(a, &sw, string_writer_open_cb, string_writer_cb, string_writer_close_cb);
    if (r != ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress: archive_write_open failed: %s", archive_error_string(a));
        archive_write_free(a);
        return {};
    }

    struct archive_entry* entry = archive_entry_new();
    archive_entry_set_pathname_utf8(entry, "data");
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_size(entry, static_cast<la_int64_t>(data.size()));
    archive_entry_set_perm(entry, 0644);
    archive_write_header(a, entry);
    archive_write_data(a, data.data(), data.size());
    archive_entry_free(entry);
    archive_write_close(a);
    archive_write_free(a);

    return sw.data;
}

std::string ic_decompress(std::string_view data, CompressionFormat format)
{
    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    StringReader sr{data, 0};
    if (archive_read_open(a, &sr, string_reader_open_cb, string_reader_cb, string_reader_close_cb) != ARCHIVE_OK)
    {
        archive_read_free(a);
        return "";
    }

    std::string result;
    struct archive_entry* entry;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK)
    {
        if (archive_entry_filetype(entry) != AE_IFREG)
        {
            archive_read_data_skip(a);
            continue;
        }

        std::string chunk(65536, '\0');
        la_ssize_t read;
        while ((read = archive_read_data(a, chunk.data(), chunk.size())) > 0)
        {
            result.append(chunk.data(), static_cast<size_t>(read));
        }
    }

    archive_read_close(a);
    archive_read_free(a);
    return result;
}

bool ic_compress_file(std::string_view src, std::string_view dst, CompressionFormat format, int32_t level)
{
    FOPEN_IFSTREAM(in, src, std::ios::binary | std::ios::ate);
    if (!in) return false;

    auto file_size = in.tellg();
    in.seekg(0);

    std::string file_data(static_cast<size_t>(file_size), '\0');
    in.read(file_data.data(), file_size);
    in.close();

    std::string compressed = ic_compress(file_data, format, level);
    if (compressed.empty() && file_size > 0) return false;

    FOPEN_OFSTREAM(out, dst, std::ios::binary);
    if (!out) return false;
    out.write(compressed.data(), static_cast<std::streamsize>(compressed.size()));
    out.close();
    return true;
}

bool ic_decompress_file(std::string_view src, std::string_view dst, CompressionFormat format)
{
    FOPEN_IFSTREAM(in, src, std::ios::binary | std::ios::ate);
    if (!in) return false;

    auto file_size = in.tellg();
    in.seekg(0);

    std::string file_data(static_cast<size_t>(file_size), '\0');
    in.read(file_data.data(), file_size);
    in.close();

    std::string decompressed = ic_decompress(file_data, format);
    if (decompressed.empty() && file_size > 0) return false;

    FOPEN_OFSTREAM(out, dst, std::ios::binary);
    if (!out) return false;
    out.write(decompressed.data(), static_cast<std::streamsize>(decompressed.size()));
    out.close();
    return true;
}

CompressResult ic_compress_buf(GMBuffer input, GMBuffer output, CompressionFormat format, int32_t level)
{
    CompressResult result{};
    result.format = format;

    auto* input_data = static_cast<const char*>(input.data());
    auto  input_len = static_cast<size_t>(input.length());

    std::string_view sv(input_data, input_len);
    std::string compressed = ic_compress(sv, format, level);

    if (compressed.empty())
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = 0;
        result.ratio = 0.0f;
        return result;
    }

    size_t copy_len = std::min(compressed.size(), static_cast<size_t>(output.length()));
    std::memcpy(output.data(), compressed.data(), copy_len);

    result.success = true;
    result.original_size = static_cast<int64_t>(input_len);
    result.compressed_size = static_cast<int64_t>(copy_len);
    result.ratio = (input_len > 0) ? (static_cast<float>(copy_len) / static_cast<float>(input_len)) : 1.0f;
    return result;
}

CompressResult ic_decompress_buf(GMBuffer input, GMBuffer output, CompressionFormat format)
{
    CompressResult result{};
    result.format = format;

    auto* input_data = static_cast<const char*>(input.data());
    auto  input_len = static_cast<size_t>(input.length());

    std::string_view sv(input_data, input_len);
    std::string decompressed = ic_decompress(sv, format);

    if (decompressed.empty())
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = 0;
        result.ratio = 0.0f;
        return result;
    }

    size_t copy_len = std::min(decompressed.size(), static_cast<size_t>(output.length()));
    std::memcpy(output.data(), decompressed.data(), copy_len);

    result.success = true;
    result.original_size = static_cast<int64_t>(input_len);
    result.compressed_size = static_cast<int64_t>(copy_len);
    result.ratio = (input_len > 0) ? (static_cast<float>(copy_len) / static_cast<float>(input_len)) : 1.0f;
    return result;
}

// =============================================================================
// Archive operations
// =============================================================================

ArrayStream ic_list(std::string_view archive)
{
    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        LOG_ERROR("ic_list: archive_read_open_filename failed: %s (path=%s)", archive_error_string(a), std::string(archive).c_str());
        archive_read_free(a);
        return ArrayStream{};
    }

    std::vector<ArchiveEntry> entries;
    struct archive_entry* entry;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK)
    {
        ArchiveEntry ae;
        ae.filename = archive_entry_pathname_utf8(entry) ? archive_entry_pathname_utf8(entry) : "";
        ae.compressed_size = static_cast<int64_t>(archive_entry_size_is_set(entry) ? archive_entry_size(entry) : 0);
        ae.uncompressed_size = ae.compressed_size;
        ae.is_directory = (archive_entry_filetype(entry) == AE_IFDIR);
        ae.crc32 = 0;
        entries.push_back(std::move(ae));
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);

    // Encode as a DataStream that can be decoded by GM
    gm::wire::ArrayStream arr;
    for (const auto& e : entries)
    {
        arr << e;
    }
    return arr;
}

ExtractResult ic_extract(std::string_view archive, std::string_view output_dir)
{
    ExtractResult result{};
    result.files_extracted = 0;

    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    struct archive* ext = archive_write_disk_new();
    archive_write_disk_set_options(ext, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        result.error_message = archive_error_string(a);
        result.success = false;
        archive_read_free(a);
        archive_write_free(ext);
        return result;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK)
    {
        std::string outpath = std::string(output_dir) + "/" +         archive_entry_pathname_utf8(entry);
        archive_entry_set_pathname_utf8(entry, outpath.c_str());

        int r = archive_write_header(ext, entry);
        if (r == ARCHIVE_OK)
        {
            const void* buff;
            size_t size;
            la_int64_t offset;
            while (archive_read_data_block(a, &buff, &size, &offset) == ARCHIVE_OK)
            {
                archive_write_data_block(ext, buff, size, offset);
            }
            result.files_extracted++;
        }
        else
        {
            archive_read_data_skip(a);
        }
    }

    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);

    result.success = true;
    return result;
}

bool ic_extract_file(std::string_view archive, std::string_view entry, std::string_view output)
{
    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        archive_read_free(a);
        return false;
    }

    bool found = false;
    struct archive_entry* ae;
    while (archive_read_next_header(a, &ae) == ARCHIVE_OK)
    {
        std::string pathname =         archive_entry_pathname_utf8(ae) ?         archive_entry_pathname_utf8(ae) : "";
        if (pathname == entry && archive_entry_filetype(ae) == AE_IFREG)
        {
            la_int64_t size = archive_entry_size(ae);
            std::string data;
            const void* buff;
            size_t bsize;
            la_int64_t offset;
            std::string chunk(65536, '\0');
            la_ssize_t read;
            while ((read = archive_read_data(a, chunk.data(), chunk.size())) > 0)
            {
                data.append(chunk.data(), static_cast<size_t>(read));
            }

            FOPEN_OFSTREAM(out, output, std::ios::binary);
            if (out)
            {
                out.write(data.data(), static_cast<std::streamsize>(data.size()));
                out.close();
                found = true;
            }
            break;
        }
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);
    return found;
}

// =============================================================================
// Debug file logger (for diagnosing DLL issues from GameMaker)
// =============================================================================
static void dbg_log(const char* fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    FILE* f = fopen("ic_debug.log", "a");
    if (f) { fprintf(f, "%s\n", buf); fclose(f); }
}

std::string ic_extract_mem(std::string_view archive, std::string_view entry)
{
    dbg_log("=== ic_extract_mem START ===");
    dbg_log("archive='%.*s' entry='%.*s'", (int)archive.size(), archive.data(), (int)entry.size(), entry.data());
    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    int r = archive_read_open_filename(a, std::string(archive).c_str(), 10240);
    dbg_log("open result=%d error=%s", r, r != ARCHIVE_OK ? archive_error_string(a) : "OK");

    if (r != ARCHIVE_OK)
    {
        archive_read_free(a);
        dbg_log("=== ic_extract_mem END (open failed) ===");
        return "";
    }

    std::string result;
    struct archive_entry* ae;
    int entry_count = 0;
    while (archive_read_next_header(a, &ae) == ARCHIVE_OK)
    {
        entry_count++;
        std::string pathname =         archive_entry_pathname_utf8(ae) ?         archive_entry_pathname_utf8(ae) : "";
        int filetype = archive_entry_filetype(ae);
        la_int64_t size = archive_entry_size(ae);
        dbg_log("  entry#%d path='%s' type=%d size=%lld match=%d",
            entry_count, pathname.c_str(), filetype, (long long)size,
            (pathname == entry && filetype == AE_IFREG));

        if (pathname != entry || filetype != AE_IFREG)
        {
            archive_read_data_skip(a);
            continue;
        }

        const void* buff;
        size_t bsize;
        la_int64_t offset;
        std::string chunk(65536, '\0');
        la_ssize_t read;
        int blocks = 0;
        while ((read = archive_read_data(a, chunk.data(), chunk.size())) > 0)
        {
            blocks++;
            result.append(chunk.data(), static_cast<size_t>(read));
            dbg_log("    block#%d read=%lld total=%zu", blocks, (long long)read, result.size());
        }
        if (read < 0)
            dbg_log("    archive_read_data ERROR: %s", archive_error_string(a));
        else if (blocks == 0)
            dbg_log("    archive_read_data returned 0 immediately (no data)");
        dbg_log("  done reading: %d blocks, total=%zu bytes", blocks, result.size());
        break;
    }
    dbg_log("total entries=%d, matched_result_len=%zu", entry_count, result.size());

    archive_read_close(a);
    archive_read_free(a);
    dbg_log("=== ic_extract_mem END ===");
    return result;
}

// =============================================================================
// Archive creation (handle-based)
// =============================================================================

static std::map<int32_t, struct archive*> g_archive_writers;
static int32_t g_next_handle = 1;

int32_t ic_create(std::string_view archive, CompressionFormat format)
{
    struct archive* a = archive_write_new();
    if (!a)
    {
        LOG_ERROR("ic_create: archive_write_new() returned null");
        return -1;
    }

    if (format == CompressionFormat::Zip)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_zip(a);
        archive_write_set_format_option(a, "zip", "compression", "deflate");
    }
    else if (format == CompressionFormat::SevenZ)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_7zip(a);
    }
    else if (format == CompressionFormat::Tar)
    {
        archive_write_add_filter_none(a);
        archive_write_set_format_pax_restricted(a);
    }
    else
    {
        archive_write_add_filter(a, format_to_filter(format));
        archive_write_set_format_raw(a);
    }

    int r = OPEN_ARCHIVE_WRITE(a, archive);
    if (r != ARCHIVE_OK)
    {
        LOG_ERROR("ic_create: archive_write_open_filename failed: %s (path=%s)", archive_error_string(a), std::string(archive).c_str());
        archive_write_free(a);
        return -1;
    }

    int32_t handle = g_next_handle++;
    g_archive_writers[handle] = a;
    return handle;
}

bool ic_add_file(int32_t handle, std::string_view path, std::string_view entry)
{
    auto it = g_archive_writers.find(handle);
    if (it == g_archive_writers.end()) return false;

    struct archive* a = it->second;

    FOPEN_IFSTREAM(in, path, std::ios::binary | std::ios::ate);
    if (!in)
    {
        LOG_ERROR("ic_add_file: failed to open source: %s", std::string(path).c_str());
        return false;
    }

    auto file_size = in.tellg();
    in.seekg(0);

    std::string file_data(static_cast<size_t>(file_size), '\0');
    in.read(file_data.data(), file_size);
    in.close();

    struct archive_entry* ae = archive_entry_new();
    archive_entry_set_pathname_utf8(ae, std::string(entry).c_str());
    archive_entry_set_filetype(ae, AE_IFREG);
    archive_entry_set_size(ae, static_cast<la_int64_t>(file_data.size()));
    archive_entry_set_perm(ae, 0644);

    int r = archive_write_header(a, ae);
    if (r != ARCHIVE_OK)
    {
        archive_entry_free(ae);
        return false;
    }

    archive_write_data(a, file_data.data(), file_data.size());
    archive_entry_free(ae);
    return true;
}

bool ic_add_data(int32_t handle, std::string_view entry, std::string_view data)
{
    auto it = g_archive_writers.find(handle);
    if (it == g_archive_writers.end()) return false;

    struct archive* a = it->second;

    struct archive_entry* ae = archive_entry_new();
    archive_entry_set_pathname_utf8(ae, std::string(entry).c_str());
    archive_entry_set_filetype(ae, AE_IFREG);
    archive_entry_set_size(ae, static_cast<la_int64_t>(data.size()));
    archive_entry_set_perm(ae, 0644);

    int r = archive_write_header(a, ae);
    if (r != ARCHIVE_OK)
    {
        archive_entry_free(ae);
        return false;
    }

    archive_write_data(a, data.data(), data.size());
    archive_entry_free(ae);
    return true;
}

bool ic_close(int32_t handle)
{
    auto it = g_archive_writers.find(handle);
    if (it == g_archive_writers.end()) return false;

    struct archive* a = it->second;
    archive_write_close(a);
    archive_write_free(a);
    g_archive_writers.erase(it);
    return true;
}

// =============================================================================
// Utility functions
// =============================================================================

CompressionFormat ic_detect(std::string_view data)
{
    return detect_from_magic(data);
}

CompressionFormat ic_detect_file(std::string_view path)
{
    FOPEN_IFSTREAM(in, path, std::ios::binary);
    if (!in) return CompressionFormat::Raw;

    char buf[256];
    in.read(buf, sizeof(buf));
    std::streamsize read = in.gcount();
    in.close();

    if (read <= 0) return CompressionFormat::Raw;

    std::string_view sv(buf, static_cast<size_t>(read));
    return detect_from_magic(sv);
}

CompressionFormat ic_from_ext(std::string_view name)
{
    return detect_from_ext(name);
}

std::string ic_to_str(CompressionFormat format)
{
    return format_to_str(format);
}