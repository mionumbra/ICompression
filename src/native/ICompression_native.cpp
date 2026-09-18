#include "ICompression_native.h"

#include <archive.h>
#include <archive_entry.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <limits>
#include <map>
#include <memory>
#include <new>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

using namespace gm::wire;
using namespace gm_structs;
using namespace gm_enums;

static constexpr size_t MAX_ENTRY_SIZE = 256ull * 1024ull * 1024ull;
static constexpr uint64_t MAX_TOTAL_EXTRACT_SIZE = 1024ull * 1024ull * 1024ull;
static constexpr size_t FILE_STREAM_CHUNK_SIZE = 1024ull * 1024ull;
static constexpr size_t MAX_ARCHIVE_ENTRIES = 65535;
static constexpr size_t MAX_ENTRY_PATH_SIZE = 4096;
static constexpr size_t MAX_LIST_PATH_SIZE = 256;
static constexpr size_t MAX_MESSAGE_PATH_SIZE = 256;
static constexpr size_t MAX_LIST_PAGE_ENTRIES = 16;
static constexpr size_t MAX_OPEN_ARCHIVES = 64;

// =============================================================================
// Internal helpers
// =============================================================================

#ifdef _WIN32
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

// All-or-nothing file outputs are written beside their destination so the
// final rename stays on one volume.
static std::string make_temp_path(std::string_view dst)
{
    static uint32_t sequence = 0;
    return std::string(dst) + ".tmp" + std::to_string(++sequence);
}

static void delete_file(std::string_view path)
{
#ifdef _WIN32
    DeleteFileW(utf8_to_wide(path).c_str());
#else
    std::remove(std::string(path).c_str());
#endif
}

// Overwrite an existing destination, matching ofstream truncation semantics.
static bool replace_file(std::string_view temp, std::string_view dst)
{
#ifdef _WIN32
    return MoveFileExW(utf8_to_wide(temp).c_str(), utf8_to_wide(dst).c_str(),
        MOVEFILE_REPLACE_EXISTING) != 0;
#else
    return std::rename(std::string(temp).c_str(), std::string(dst).c_str()) == 0;
#endif
}

// Map CompressionFormat to libarchive filter code
static int format_to_filter(CompressionFormat fmt)
{
    switch (fmt)
    {
    case CompressionFormat::Gzip:   return ARCHIVE_FILTER_GZIP;
    case CompressionFormat::Zstd:   return ARCHIVE_FILTER_ZSTD;
    case CompressionFormat::Lz4:    return ARCHIVE_FILTER_LZ4;
    case CompressionFormat::Xz:     return ARCHIVE_FILTER_XZ;
    case CompressionFormat::Bzip2:  return ARCHIVE_FILTER_BZIP2;
    case CompressionFormat::Raw:
    case CompressionFormat::Tar:    return ARCHIVE_FILTER_NONE;
    case CompressionFormat::Zip:
    case CompressionFormat::SevenZ: return ARCHIVE_FILTER_NONE;
    default:                        return ARCHIVE_FILTER_NONE;
    }
}

// Map libarchive compression level
static int level_to_archive(int32_t level)
{
    switch (level)
    {
    case 0: return 1; // CompressionLevel.Fastest
    case 1: return 6; // CompressionLevel.Default
    case 2: return 9; // CompressionLevel.Optimal
    default:
        return std::clamp(static_cast<int>(level), 1, 9);
    }
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
    case CompressionFormat::Bzip2:  return "bzip2";
    case CompressionFormat::Rar:    return "rar";
    default:                        return "unknown";
    }
}

static bool archive_status_ok(struct archive* a, int status, const char* operation)
{
    if (status >= ARCHIVE_OK)
        return true;

    LOG_ERROR("%s failed: %s", operation, archive_error_string(a));
    return false;
}

static bool configure_archive_writer(struct archive* a, CompressionFormat format, int32_t level)
{
    const int archive_level = level_to_archive(level);

    switch (format)
    {
    case CompressionFormat::Zip:
        return archive_status_ok(a, archive_write_add_filter_none(a), "archive_write_add_filter_none")
            && archive_status_ok(a, archive_write_set_format_zip(a), "archive_write_set_format_zip")
            && archive_status_ok(a, archive_write_set_format_option(a, "zip", "compression", "deflate"), "zip compression option")
            && archive_status_ok(a, archive_write_set_format_option(a, "zip", "compression-level", std::to_string(archive_level).c_str()), "zip compression-level option");

    case CompressionFormat::SevenZ:
        return archive_status_ok(a, archive_write_add_filter_none(a), "archive_write_add_filter_none")
            && archive_status_ok(a, archive_write_set_format_7zip(a), "archive_write_set_format_7zip")
            && archive_status_ok(a, archive_write_set_format_option(a, "7zip", "compression-level", std::to_string(archive_level).c_str()), "7zip compression-level option");

    case CompressionFormat::Tar:
        return archive_status_ok(a, archive_write_add_filter_none(a), "archive_write_add_filter_none")
            && archive_status_ok(a, archive_write_set_format_pax_restricted(a), "archive_write_set_format_pax_restricted");

    case CompressionFormat::Raw:
        return archive_status_ok(a, archive_write_add_filter_none(a), "archive_write_add_filter_none")
            && archive_status_ok(a, archive_write_set_format_raw(a), "archive_write_set_format_raw");

    case CompressionFormat::Gzip:
    case CompressionFormat::Zstd:
    case CompressionFormat::Lz4:
    case CompressionFormat::Xz:
    case CompressionFormat::Bzip2:
        return archive_status_ok(a, archive_write_add_filter(a, format_to_filter(format)), "archive_write_add_filter")
            && archive_status_ok(a, archive_write_set_format_raw(a), "archive_write_set_format_raw")
            && archive_status_ok(a, archive_write_set_filter_option(a, nullptr, "compression-level", std::to_string(archive_level).c_str()), "compression-level filter option");

    default:
        LOG_ERROR("Unsupported compression format: %lld", static_cast<long long>(format));
        return false;
    }
}

static std::string entry_pathname_utf8(struct archive_entry* entry)
{
    const char* pathname = archive_entry_pathname_utf8(entry);
    return pathname ? pathname : "";
}

static const char* archive_error_or(struct archive* a, const char* fallback)
{
    const char* error = a ? archive_error_string(a) : nullptr;
    return error ? error : fallback;
}

static bool get_buffer_range(GMBuffer buffer, int64_t offset, int64_t length,
    const char*& data, size_t& size)
{
    if (offset < 0 || length < 0)
        return false;

    const uint64_t buffer_size = buffer.length();
    const uint64_t range_offset = static_cast<uint64_t>(offset);
    const uint64_t range_length = static_cast<uint64_t>(length);
    if (range_offset > buffer_size || range_length > buffer_size - range_offset ||
        range_length > static_cast<uint64_t>(std::numeric_limits<size_t>::max()) ||
        (!buffer.data() && range_length != 0))
        return false;

    data = range_length == 0
        ? static_cast<const char*>(buffer.data())
        : static_cast<const char*>(buffer.data()) + static_cast<size_t>(range_offset);
    size = static_cast<size_t>(range_length);
    return true;
}

static bool get_buffer_output(GMBuffer buffer, int64_t offset, char*& data, size_t& size)
{
    if (offset < 0)
        return false;

    const uint64_t buffer_size = buffer.length();
    const uint64_t range_offset = static_cast<uint64_t>(offset);
    if (range_offset > buffer_size ||
        buffer_size - range_offset > static_cast<uint64_t>(std::numeric_limits<size_t>::max()) ||
        (!buffer.data() && buffer_size != 0))
        return false;

    data = range_offset == buffer_size
        ? static_cast<char*>(buffer.data())
        : static_cast<char*>(buffer.data()) + static_cast<size_t>(range_offset);
    size = static_cast<size_t>(buffer_size - range_offset);
    return true;
}

static bool read_current_entry(struct archive* a, std::string& output, size_t limit,
    std::string& error)
{
    output.clear();
    std::string chunk(65536, '\0');
    la_ssize_t read;
    while ((read = archive_read_data(a, chunk.data(), chunk.size())) > 0)
    {
        const size_t count = static_cast<size_t>(read);
        if (output.size() > limit || count > limit - output.size())
        {
            error = "Decompressed data exceeds the configured limit";
            return false;
        }
        output.append(chunk.data(), count);
    }

    if (read < 0)
    {
        error = archive_error_string(a) ? archive_error_string(a) : "Failed to read archive data";
        return false;
    }
    return true;
}

// Copy a plain file into the current archive entry in fixed-size blocks.
static bool stream_file_to_entry(std::ifstream& in, struct archive* a, int64_t file_size)
{
    std::string chunk(FILE_STREAM_CHUNK_SIZE, '\0');
    int64_t remaining = file_size;
    while (remaining > 0)
    {
        const auto want = static_cast<std::streamsize>(std::min<int64_t>(remaining, static_cast<int64_t>(chunk.size())));
        in.read(chunk.data(), want);
        const std::streamsize got = in.gcount();
        if (got != want)
            return false;
        if (archive_write_data(a, chunk.data(), static_cast<size_t>(got)) != static_cast<la_ssize_t>(got))
            return false;
        remaining -= got;
    }
    return true;
}

// Copy the remainder of a plain input file into a plain output file.
static bool stream_file_to_file(std::ifstream& in, std::ofstream& out)
{
    std::string chunk(FILE_STREAM_CHUNK_SIZE, '\0');
    for (;;)
    {
        in.read(chunk.data(), static_cast<std::streamsize>(chunk.size()));
        const std::streamsize got = in.gcount();
        if (got > 0)
        {
            out.write(chunk.data(), got);
            if (!out)
                return false;
        }
        if (got < static_cast<std::streamsize>(chunk.size()))
            break;
    }
    return !in.bad();
}

// Copy the current reader entry into a plain file, preserving block order.
static bool stream_entry_to_file(struct archive* a, std::ofstream& out)
{
    const void* block;
    size_t block_size;
    la_int64_t block_offset;
    int status;
    while ((status = archive_read_data_block(a, &block, &block_size, &block_offset)) == ARCHIVE_OK)
    {
        if (block_size == 0)
            continue;
        out.write(static_cast<const char*>(block), static_cast<std::streamsize>(block_size));
        if (!out)
            return false;
    }
    return status == ARCHIVE_EOF;
}

// Match a reserved DOS device name on the segment stem before the first dot,
// so both "NUL" and "NUL.txt" collide with the Windows device.
static bool is_reserved_device_name(std::string_view segment)
{
    const std::string_view stem = segment.substr(0, segment.find('.'));
    if (stem.size() < 3 || stem.size() > 4)
        return false;

    char upper[4];
    for (size_t i = 0; i < stem.size(); ++i)
        upper[i] = static_cast<char>(std::toupper(static_cast<unsigned char>(stem[i])));

    const std::string_view name(upper, stem.size());
    if (name == "CON" || name == "PRN" || name == "AUX" || name == "NUL")
        return true;
    if (stem.size() == 4 && name[3] >= '1' && name[3] <= '9')
        return name.substr(0, 3) == "COM" || name.substr(0, 3) == "LPT";
    return false;
}

static bool is_safe_archive_entry_path(std::string_view path)
{
    if (path.empty())
        return false;

    if (path.front() == '/' || path.front() == '\\')
        return false;

    if (path.size() >= 2 && path[1] == ':')
        return false;

    size_t start = 0;
    while (start <= path.size())
    {
        size_t end = path.find_first_of("/\\", start);
        if (end == std::string_view::npos)
            end = path.size();

        std::string_view segment = path.substr(start, end - start);
        if (segment == "..")
            return false;

        // Windows name rules: a ':' is NTFS ADS syntax, and the OS silently
        // strips trailing dots and spaces, collapsing distinct archive names.
        if (segment.find(':') != std::string_view::npos)
            return false;
        if (is_reserved_device_name(segment))
            return false;
        if (!segment.empty() && (segment.back() == '.' || segment.back() == ' '))
            return false;

        if (end == path.size())
            break;
        start = end + 1;
    }

    return true;
}

// Bound an attacker-controlled path before embedding it in an error message.
// Back off to a non-continuation byte so no UTF-8 sequence is split.
static std::string truncate_path_for_message(std::string_view path)
{
    if (path.size() <= MAX_MESSAGE_PATH_SIZE)
        return std::string(path);

    size_t end = MAX_MESSAGE_PATH_SIZE;
    while (end > 0 && (static_cast<unsigned char>(path[end]) & 0xC0) == 0x80)
        --end;
    return std::string(path.substr(0, end)) + "...";
}

static std::string base64_encode(std::string_view input)
{
    static constexpr char table[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    std::string output;
    output.reserve(((input.size() + 2) / 3) * 4);

    const auto* bytes = reinterpret_cast<const unsigned char*>(input.data());
    for (size_t i = 0; i < input.size(); i += 3)
    {
        uint32_t v = static_cast<uint32_t>(bytes[i]) << 16;
        if (i + 1 < input.size()) v |= static_cast<uint32_t>(bytes[i + 1]) << 8;
        if (i + 2 < input.size()) v |= static_cast<uint32_t>(bytes[i + 2]);

        output.push_back(table[(v >> 18) & 0x3F]);
        output.push_back(table[(v >> 12) & 0x3F]);
        output.push_back((i + 1 < input.size()) ? table[(v >> 6) & 0x3F] : '=');
        output.push_back((i + 2 < input.size()) ? table[v & 0x3F] : '=');
    }

    return output;
}

static int base64_value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static bool base64_decode(std::string_view input, std::string& output)
{
    output.clear();
    output.reserve((input.size() / 4) * 3);

    uint32_t value = 0;
    int bits = 0;
    size_t symbols = 0;
    size_t padding = 0;
    bool padded = false;
    for (unsigned char c : input)
    {
        if (std::isspace(c))
            continue;
        if (c == '=')
        {
            padded = true;
            ++padding;
            continue;
        }

        if (padded)
            return false;

        int decoded = base64_value(static_cast<char>(c));
        if (decoded < 0)
            return false;

        value = (value << 6) | static_cast<uint32_t>(decoded);
        bits += 6;
        ++symbols;
        if (bits >= 8)
        {
            bits -= 8;
            output.push_back(static_cast<char>((value >> bits) & 0xFF));
        }

        value &= (bits == 0) ? 0u : ((1u << bits) - 1u);
    }

    if (padding > 2 || (symbols + padding) % 4 != 0)
        return false;

    if (value != 0)
        return false;

    return (padding == 0 && bits == 0) ||
        (padding == 1 && bits == 2) ||
        (padding == 2 && bits == 4);
}

// Validate a complete tar header, including its checksum (also supports old tar).
static bool is_tar_header(std::string_view data)
{
    if (data.size() < 512 || data[0] == '\0')
        return false;

    uint32_t expected = 0;
    bool digit_seen = false;
    bool padding_seen = false;
    for (size_t i = 148; i < 156; ++i)
    {
        const unsigned char c = static_cast<unsigned char>(data[i]);
        if (c == ' ' || c == '\0')
        {
            if (digit_seen) padding_seen = true;
            continue;
        }
        if (padding_seen || c < '0' || c > '7')
            return false;
        digit_seen = true;
        expected = expected * 8 + (c - '0');
    }
    if (!digit_seen)
        return false;

    uint32_t actual = 0;
    for (size_t i = 0; i < 512; ++i)
        actual += (i >= 148 && i < 156) ? ' ' : static_cast<unsigned char>(data[i]);
    return actual == expected;
}

// Detect format from magic bytes
static CompressionFormat detect_from_magic(const std::string_view& data)
{
    const auto* buf = reinterpret_cast<const uint8_t*>(data.data());

    if (data.size() >= 4 && buf[0] == 0x50 && buf[1] == 0x4B &&
        ((buf[2] == 0x03 && buf[3] == 0x04) ||  // Local file header
         (buf[2] == 0x05 && buf[3] == 0x06) ||  // Empty ZIP
         (buf[2] == 0x06 && buf[3] == 0x06) ||  // ZIP64 end record
         (buf[2] == 0x07 && buf[3] == 0x08)))   // Spanned ZIP marker
        return CompressionFormat::Zip;

    if (data.size() >= 6 && buf[0] == 0x37 && buf[1] == 0x7A && buf[2] == 0xBC && buf[3] == 0xAF && buf[4] == 0x27 && buf[5] == 0x1C)
        return CompressionFormat::SevenZ;

    if (data.size() >= 7 && buf[0] == 0x52 && buf[1] == 0x61 && buf[2] == 0x72 && buf[3] == 0x21 && buf[4] == 0x1A && buf[5] == 0x07 && (buf[6] == 0x00 || buf[6] == 0x01))
        return CompressionFormat::Rar;

    if (data.size() >= 2 && buf[0] == 0x1F && buf[1] == 0x8B)
        return CompressionFormat::Gzip;

    if (data.size() >= 3 && buf[0] == 0x42 && buf[1] == 0x5A && buf[2] == 0x68)
        return CompressionFormat::Bzip2;

    if (data.size() >= 4 && buf[0] == 0x28 && buf[1] == 0xB5 && buf[2] == 0x2F && buf[3] == 0xFD)
        return CompressionFormat::Zstd;

    if (data.size() >= 4 && buf[0] == 0x04 && buf[1] == 0x22 && buf[2] == 0x4D && buf[3] == 0x18)
        return CompressionFormat::Lz4;

    if (data.size() >= 6 && buf[0] == 0xFD && buf[1] == 0x37 && buf[2] == 0x7A && buf[3] == 0x58 && buf[4] == 0x5A && buf[5] == 0x00)
        return CompressionFormat::Xz;

    if (is_tar_header(data))
        return CompressionFormat::Tar;

    return CompressionFormat::Raw;
}

// Detect from file extension
static CompressionFormat detect_from_ext(const std::string_view& name)
{
    std::string lower(name);
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    auto ends_with = [](const std::string& value, const char* suffix)
    {
        const size_t suffix_len = std::strlen(suffix);
        return value.size() >= suffix_len && value.compare(value.size() - suffix_len, suffix_len, suffix) == 0;
    };

    if (ends_with(lower, ".tar.gz") || ends_with(lower, ".tgz")) return CompressionFormat::Gzip;
    if (ends_with(lower, ".tar.bz2") || ends_with(lower, ".tbz2") || ends_with(lower, ".tbz")) return CompressionFormat::Bzip2;
    if (ends_with(lower, ".tar.zst") || ends_with(lower, ".tar.zstd") || ends_with(lower, ".tzst") || ends_with(lower, ".tzstd")) return CompressionFormat::Zstd;
    if (ends_with(lower, ".tar.lz4") || ends_with(lower, ".tlz4")) return CompressionFormat::Lz4;
    if (ends_with(lower, ".tar.xz") || ends_with(lower, ".txz")) return CompressionFormat::Xz;

    std::string ext;
    auto pos = lower.rfind('.');
    if (pos != std::string::npos)
        ext = lower.substr(pos);

    if (ext == ".zip")   return CompressionFormat::Zip;
    if (ext == ".rar")   return CompressionFormat::Rar;
    if (ext == ".7z")    return CompressionFormat::SevenZ;
    if (ext == ".gz" || ext == ".gzip") return CompressionFormat::Gzip;
    if (ext == ".bz2" || ext == ".bzip2") return CompressionFormat::Bzip2;
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
    bool failed = false;
};

static la_ssize_t string_writer_cb(struct archive*, void* client_data,
    const void* buf, size_t length)
{
    auto* sw = static_cast<StringWriter*>(client_data);
    try
    {
        sw->data.append(static_cast<const char*>(buf), length);
    }
    catch (...)
    {
        sw->failed = true;
        return -1;
    }
    return static_cast<la_ssize_t>(length);
}

static int string_writer_open_cb(struct archive*, void*) { return ARCHIVE_OK; }
static int string_writer_close_cb(struct archive*, void*) { return ARCHIVE_OK; }

// =============================================================================
// Exception boundary
// =============================================================================

// Failure sentinel for an exported return type, shaped like the ordinary
// failure results of the functions returning it.
template <typename R>
static R failure_sentinel(const char* message)
{
    if constexpr (std::is_same_v<R, bool>)
        return false;
    else if constexpr (std::is_same_v<R, int32_t>)
        return -1;
    else if constexpr (std::is_same_v<R, CompressionFormat>)
        return CompressionFormat::Raw;
    else
    {
        R result{};
        if constexpr (requires { result.error_message = message; })
            result.error_message = message;
        return result;
    }
}

// An exception escaping an exported function would terminate the GameMaker
// runner. Every exported entry point forwards to its _impl through this guard
// and reports a caught exception as its ordinary failure result.
template <typename F>
static std::invoke_result_t<F> exception_guard(const char* name, F&& fn)
{
    using R = std::invoke_result_t<F>;
    [[maybe_unused]] const char* message = nullptr;
    try
    {
        return fn();
    }
    catch (const std::bad_alloc&)
    {
        message = "Out of memory";
        LOG_ERROR("%s: out of memory", name);
    }
    catch (...)
    {
        message = "Unexpected internal error";
        LOG_ERROR("%s: unexpected internal exception", name);
    }

    if constexpr (!std::is_void_v<R>)
        return failure_sentinel<R>(message);
}

// Guard variant for entry points whose failure result carries request details
// that a default-constructed sentinel cannot know.
template <typename R, typename F>
static R exception_guard(const char* name, const R& sentinel, F&& fn)
{
    try
    {
        return fn();
    }
    catch (const std::bad_alloc&)
    {
        LOG_ERROR("%s: out of memory", name);
    }
    catch (...)
    {
        LOG_ERROR("%s: unexpected internal exception", name);
    }
    return sentinel;
}

// =============================================================================
// Stream compression / decompression
// =============================================================================

static bool compress_raw(std::string_view data, CompressionFormat format, int32_t level,
    std::string& result)
{
    result.clear();
    struct archive* a = archive_write_new();
    if (!a)
    {
        LOG_ERROR("ic_compress: archive_write_new() returned null");
        return false;
    }

    if (!configure_archive_writer(a, format, level))
    {
        archive_write_free(a);
        return false;
    }

    archive_write_set_bytes_per_block(a, 0);
    archive_write_set_bytes_in_last_block(a, 0);

    StringWriter sw;
    int r = archive_write_open(a, &sw, string_writer_open_cb, string_writer_cb, string_writer_close_cb);
    if (r != ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress: archive_write_open failed: %s", archive_error_string(a));
        archive_write_free(a);
        return false;
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry)
    {
        archive_write_close(a);
        archive_write_free(a);
        return false;
    }

    archive_entry_set_pathname_utf8(entry, "data");
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_size(entry, static_cast<la_int64_t>(data.size()));
    archive_entry_set_perm(entry, 0644);
    if (archive_write_header(a, entry) < ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress: archive_write_header failed: %s", archive_error_string(a));
        archive_entry_free(entry);
        archive_write_close(a);
        archive_write_free(a);
        return false;
    }

    la_ssize_t written = archive_write_data(a, data.data(), data.size());
    if (sw.failed || written < 0 || static_cast<size_t>(written) != data.size())
    {
        LOG_ERROR("ic_compress: archive_write_data failed: %s", archive_error_string(a));
        archive_entry_free(entry);
        archive_write_close(a);
        archive_write_free(a);
        return false;
    }
    archive_entry_free(entry);
    if (archive_write_close(a) < ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress: archive_write_close failed: %s", archive_error_string(a));
        archive_write_free(a);
        return false;
    }
    archive_write_free(a);

    result = std::move(sw.data);
    return true;
}

static bool decompress_raw(std::string_view data, CompressionFormat format, std::string& result)
{
    result.clear();
    if (format == CompressionFormat::Raw)
    {
        if (data.size() > MAX_ENTRY_SIZE)
        {
            LOG_ERROR("ic_decompress: raw data exceeds the configured limit");
            return false;
        }
        if (!data.empty()) result.assign(data);
        return true;
    }

    int expected_filter = ARCHIVE_FILTER_NONE;
    int expected_format = 0;
    switch (format)
    {
    case CompressionFormat::Gzip:
    case CompressionFormat::Bzip2:
    case CompressionFormat::Zstd:
    case CompressionFormat::Lz4:
    case CompressionFormat::Xz:
        expected_filter = format_to_filter(format);
        expected_format = ARCHIVE_FORMAT_RAW;
        break;
    case CompressionFormat::Zip:    expected_format = ARCHIVE_FORMAT_ZIP; break;
    case CompressionFormat::SevenZ: expected_format = ARCHIVE_FORMAT_7ZIP; break;
    case CompressionFormat::Tar:    expected_format = ARCHIVE_FORMAT_TAR; break;
    case CompressionFormat::Rar:    expected_format = ARCHIVE_FORMAT_RAR; break;
    default:
        LOG_ERROR("ic_decompress: unsupported compression format");
        return false;
    }
    // A compressed empty stream still has a header and trailer.
    if (data.empty())
        return false;

    std::unique_ptr<struct archive, decltype(&archive_read_free)> reader(
        archive_read_new(), &archive_read_free);
    auto* a = reader.get();
    if (!a)
    {
        LOG_ERROR("ic_decompress: archive_read_new() returned null");
        return false;
    }

    const bool stream = expected_filter != ARCHIVE_FILTER_NONE;
    if (stream)
    {
        // Force one filter and a raw container: bidding can recursively decode
        // nested streams or interpret the recovered bytes as another archive.
        if (!archive_status_ok(a, archive_read_set_format(a, ARCHIVE_FORMAT_RAW), "raw reader format") ||
            !archive_status_ok(a, archive_read_append_filter(a, expected_filter), "stream reader filter"))
            return false;
    }
    else
    {
        if (!archive_status_ok(a, archive_read_support_format_by_code(a, expected_format), "archive reader format"))
            return false;
        if (format == CompressionFormat::Rar &&
            !archive_status_ok(a, archive_read_support_format_rar5(a), "RAR5 reader format"))
            return false;
    }

    // The built-in memory reader also supports seeks required by 7z archives.
    if (!archive_status_ok(a, archive_read_open_memory(a, data.data(), data.size()),
            "archive_read_open_memory"))
        return false;

    bool found_entry = false;
    struct archive_entry* entry;
    int header_status;
    size_t scanned = 0;
    while ((header_status = archive_read_next_header(a, &entry)) == ARCHIVE_OK)
    {
        if (++scanned > MAX_ARCHIVE_ENTRIES)
            return false;
        if (archive_entry_filetype(entry) != AE_IFREG)
        {
            if (archive_read_data_skip(a) < ARCHIVE_OK)
                return false;
            continue;
        }

        std::string error;
        if (!read_current_entry(a, result, MAX_ENTRY_SIZE, error))
        {
            LOG_ERROR("ic_decompress: %s", error.c_str());
            result.clear();
            return false;
        }
        found_entry = true;
        break;
    }

    const int actual_format = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK;
    const bool format_matches = actual_format == expected_format ||
        (format == CompressionFormat::Rar && actual_format == ARCHIVE_FORMAT_RAR_V5);
    bool success = format_matches && (found_entry || header_status == ARCHIVE_EOF);
    if (stream)
    {
        // Some filters report EOF for non-matching input. Require a complete
        // frame consumption as well as the explicitly selected filter chain.
        const la_int64_t consumed = archive_filter_bytes(a, -1);
        success = success && archive_filter_count(a) == 2 &&
            archive_filter_code(a, 0) == expected_filter && consumed >= 0 &&
            static_cast<uint64_t>(consumed) == data.size();
    }
    if (archive_read_close(a) < ARCHIVE_OK)
        success = false;
    if (!success)
    {
        LOG_ERROR("ic_decompress: invalid or mismatched compressed input");
        result.clear();
    }
    return success;
}

static std::string ic_compress_impl(std::string_view data, CompressionFormat format, int32_t level)
{
    std::string compressed;
    if (!compress_raw(data, format, level, compressed))
        return {};
    return base64_encode(compressed);
}

std::string ic_compress(std::string_view data, CompressionFormat format, int32_t level)
{
    return exception_guard("ic_compress", [&] { return ic_compress_impl(data, format, level); });
}

static std::string ic_decompress_impl(std::string_view data, CompressionFormat format)
{
    std::string compressed;
    if (!base64_decode(data, compressed))
    {
        LOG_ERROR("ic_decompress: input is not valid base64");
        return {};
    }

    std::string result;
    if (!decompress_raw(compressed, format, result))
        return {};
    return result;
}

std::string ic_decompress(std::string_view data, CompressionFormat format)
{
    return exception_guard("ic_decompress", [&] { return ic_decompress_impl(data, format); });
}

static bool ic_compress_file_impl(std::string_view src, std::string_view dst, CompressionFormat format, int32_t level)
{
    // The single entry is sized up front; the zip and 7z writers require it.
    FOPEN_IFSTREAM(in, src, std::ios::binary | std::ios::ate);
    if (!in) return false;

    const int64_t file_size = static_cast<int64_t>(in.tellg());
    if (file_size < 0)
        return false;
    in.seekg(0);

    struct archive* a = archive_write_new();
    if (!a)
    {
        LOG_ERROR("ic_compress_file: archive_write_new() returned null");
        return false;
    }

    if (!configure_archive_writer(a, format, level))
    {
        archive_write_free(a);
        return false;
    }

    archive_write_set_bytes_per_block(a, 0);
    archive_write_set_bytes_in_last_block(a, 0);

    const std::string temp_path = make_temp_path(dst);
    if (OPEN_ARCHIVE_WRITE(a, temp_path) != ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress_file: archive_write_open_filename failed: %s", archive_error_string(a));
        archive_write_free(a);
        delete_file(temp_path);
        return false;
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry)
    {
        archive_write_close(a);
        archive_write_free(a);
        delete_file(temp_path);
        return false;
    }

    archive_entry_set_pathname_utf8(entry, "data");
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_size(entry, static_cast<la_int64_t>(file_size));
    archive_entry_set_perm(entry, 0644);
    if (archive_write_header(a, entry) < ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress_file: archive_write_header failed: %s", archive_error_string(a));
        archive_entry_free(entry);
        archive_write_close(a);
        archive_write_free(a);
        delete_file(temp_path);
        return false;
    }

    if (!stream_file_to_entry(in, a, file_size))
    {
        LOG_ERROR("ic_compress_file: failed to stream source file: %s", archive_error_string(a));
        archive_entry_free(entry);
        archive_write_close(a);
        archive_write_free(a);
        delete_file(temp_path);
        return false;
    }
    archive_entry_free(entry);
    if (archive_write_close(a) < ARCHIVE_OK)
    {
        LOG_ERROR("ic_compress_file: archive_write_close failed: %s", archive_error_string(a));
        archive_write_free(a);
        delete_file(temp_path);
        return false;
    }
    archive_write_free(a);

    if (!replace_file(temp_path, dst))
    {
        delete_file(temp_path);
        return false;
    }
    return true;
}

bool ic_compress_file(std::string_view src, std::string_view dst, CompressionFormat format, int32_t level)
{
    return exception_guard("ic_compress_file", [&] { return ic_compress_file_impl(src, dst, format, level); });
}

static bool ic_decompress_file_impl(std::string_view src, std::string_view dst, CompressionFormat format)
{
    if (format == CompressionFormat::Raw)
    {
        // A raw stream is a plain byte copy with no container to validate.
        FOPEN_IFSTREAM(in, src, std::ios::binary);
        if (!in) return false;

        const std::string temp_path = make_temp_path(dst);
        FOPEN_OFSTREAM(out, temp_path, std::ios::binary);
        if (!out)
        {
            delete_file(temp_path);
            return false;
        }
        const bool copied = stream_file_to_file(in, out);
        out.close();
        if (!copied || !out)
        {
            delete_file(temp_path);
            return false;
        }
        if (!replace_file(temp_path, dst))
        {
            delete_file(temp_path);
            return false;
        }
        return true;
    }

    int expected_filter = ARCHIVE_FILTER_NONE;
    int expected_format = 0;
    switch (format)
    {
    case CompressionFormat::Gzip:
    case CompressionFormat::Bzip2:
    case CompressionFormat::Zstd:
    case CompressionFormat::Lz4:
    case CompressionFormat::Xz:
        expected_filter = format_to_filter(format);
        expected_format = ARCHIVE_FORMAT_RAW;
        break;
    case CompressionFormat::Zip:    expected_format = ARCHIVE_FORMAT_ZIP; break;
    case CompressionFormat::SevenZ: expected_format = ARCHIVE_FORMAT_7ZIP; break;
    case CompressionFormat::Tar:    expected_format = ARCHIVE_FORMAT_TAR; break;
    case CompressionFormat::Rar:    expected_format = ARCHIVE_FORMAT_RAR; break;
    default:
        LOG_ERROR("ic_decompress: unsupported compression format");
        return false;
    }

    FOPEN_IFSTREAM(size_probe, src, std::ios::binary | std::ios::ate);
    if (!size_probe) return false;
    const auto source_size = size_probe.tellg();
    if (source_size < 0)
        return false;
    size_probe.close();
    // A compressed empty stream still has a header and trailer.
    if (source_size == 0)
        return false;

    std::unique_ptr<struct archive, decltype(&archive_read_free)> reader(
        archive_read_new(), &archive_read_free);
    auto* a = reader.get();
    if (!a)
    {
        LOG_ERROR("ic_decompress: archive_read_new() returned null");
        return false;
    }

    const bool stream = expected_filter != ARCHIVE_FILTER_NONE;
    if (stream)
    {
        // Force one filter and a raw container: bidding can recursively decode
        // nested streams or interpret the recovered bytes as another archive.
        if (!archive_status_ok(a, archive_read_set_format(a, ARCHIVE_FORMAT_RAW), "raw reader format") ||
            !archive_status_ok(a, archive_read_append_filter(a, expected_filter), "stream reader filter"))
            return false;
    }
    else
    {
        if (!archive_status_ok(a, archive_read_support_format_by_code(a, expected_format), "archive reader format"))
            return false;
        if (format == CompressionFormat::Rar &&
            !archive_status_ok(a, archive_read_support_format_rar5(a), "RAR5 reader format"))
            return false;
    }

    if (!archive_status_ok(a, OPEN_ARCHIVE_READ(a, src, 10240), "archive_read_open_filename"))
        return false;

    const std::string temp_path = make_temp_path(dst);
    FOPEN_OFSTREAM(out, temp_path, std::ios::binary);
    if (!out)
    {
        delete_file(temp_path);
        return false;
    }

    bool found_entry = false;
    bool read_ok = true;
    struct archive_entry* entry;
    int header_status;
    size_t scanned = 0;
    while ((header_status = archive_read_next_header(a, &entry)) == ARCHIVE_OK)
    {
        if (++scanned > MAX_ARCHIVE_ENTRIES)
        {
            read_ok = false;
            break;
        }
        if (archive_entry_filetype(entry) != AE_IFREG)
        {
            if (archive_read_data_skip(a) < ARCHIVE_OK)
            {
                read_ok = false;
                break;
            }
            continue;
        }

        read_ok = stream_entry_to_file(a, out);
        found_entry = true;
        break;
    }

    out.close();
    const int actual_format = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK;
    const bool format_matches = actual_format == expected_format ||
        (format == CompressionFormat::Rar && actual_format == ARCHIVE_FORMAT_RAR_V5);
    bool success = read_ok && static_cast<bool>(out) && format_matches &&
        (found_entry || header_status == ARCHIVE_EOF);
    if (stream)
    {
        // Some filters report EOF for non-matching input. Require a complete
        // frame consumption as well as the explicitly selected filter chain.
        const la_int64_t consumed = archive_filter_bytes(a, -1);
        success = success && archive_filter_count(a) == 2 &&
            archive_filter_code(a, 0) == expected_filter && consumed >= 0 &&
            static_cast<uint64_t>(consumed) == static_cast<uint64_t>(source_size);
    }
    if (archive_read_close(a) < ARCHIVE_OK)
        success = false;
    if (!success)
    {
        LOG_ERROR("ic_decompress: invalid or mismatched compressed input");
        delete_file(temp_path);
        return false;
    }
    if (!replace_file(temp_path, dst))
    {
        delete_file(temp_path);
        return false;
    }
    return true;
}

bool ic_decompress_file(std::string_view src, std::string_view dst, CompressionFormat format)
{
    return exception_guard("ic_decompress_file", [&] { return ic_decompress_file_impl(src, dst, format); });
}

static CompressResult ic_compress_buf_impl(GMBuffer input, GMBuffer output, CompressionFormat format, int32_t level)
{
    CompressResult result{};
    result.format = format;

    auto* input_data = static_cast<const char*>(input.data());
    auto  input_len = static_cast<size_t>(input.length());

    std::string_view sv(input_data, input_len);
    std::string compressed;
    if (!compress_raw(sv, format, level, compressed))
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = 0;
        result.ratio = 0.0f;
        return result;
    }

    if (compressed.size() > static_cast<size_t>(output.length()))
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = static_cast<int64_t>(compressed.size());
        result.ratio = (input_len > 0) ? (static_cast<float>(compressed.size()) / static_cast<float>(input_len)) : 1.0f;
        return result;
    }

    if (!compressed.empty())
        std::memcpy(output.data(), compressed.data(), compressed.size());

    result.success = true;
    result.original_size = static_cast<int64_t>(input_len);
    result.compressed_size = static_cast<int64_t>(compressed.size());
    result.ratio = (input_len > 0) ? (static_cast<float>(compressed.size()) / static_cast<float>(input_len)) : 1.0f;
    return result;
}

CompressResult ic_compress_buf(GMBuffer input, GMBuffer output, CompressionFormat format, int32_t level)
{
    CompressResult sentinel{};
    sentinel.format = format;
    return exception_guard("ic_compress_buf", sentinel,
        [&] { return ic_compress_buf_impl(input, output, format, level); });
}

static BufferResult ic_compress_buf_range_impl(GMBuffer input, int64_t input_offset, int64_t input_length,
    GMBuffer output, int64_t output_offset, CompressionFormat format, int32_t level)
{
    BufferResult result{};
    const char* input_data = nullptr;
    size_t input_size = 0;
    char* output_data = nullptr;
    size_t output_size = 0;
    if (!get_buffer_range(input, input_offset, input_length, input_data, input_size) ||
        !get_buffer_output(output, output_offset, output_data, output_size))
    {
        result.error_message = "Invalid buffer range";
        return result;
    }

    std::string compressed;
    if (!compress_raw(std::string_view(input_data, input_size), format, level, compressed))
    {
        result.error_message = "Failed to compress input";
        return result;
    }

    result.bytes_required = static_cast<int64_t>(compressed.size());
    if (compressed.size() > output_size)
    {
        result.error_message = "Output buffer is too small";
        return result;
    }

    if (!compressed.empty())
        std::memcpy(output_data, compressed.data(), compressed.size());
    result.success = true;
    result.bytes_written = static_cast<int64_t>(compressed.size());
    return result;
}

BufferResult ic_compress_buf_range(GMBuffer input, int64_t input_offset, int64_t input_length,
    GMBuffer output, int64_t output_offset, CompressionFormat format, int32_t level)
{
    return exception_guard("ic_compress_buf_range",
        [&] { return ic_compress_buf_range_impl(input, input_offset, input_length, output, output_offset, format, level); });
}

static CompressResult ic_decompress_buf_impl(GMBuffer input, GMBuffer output, CompressionFormat format)
{
    CompressResult result{};
    result.format = format;

    auto* input_data = static_cast<const char*>(input.data());
    auto  input_len = static_cast<size_t>(input.length());

    std::string_view sv(input_data, input_len);
    std::string decompressed;
    if (!decompress_raw(sv, format, decompressed))
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = 0;
        result.ratio = 0.0f;
        return result;
    }

    if (decompressed.size() > static_cast<size_t>(output.length()))
    {
        result.success = false;
        result.original_size = static_cast<int64_t>(input_len);
        result.compressed_size = static_cast<int64_t>(decompressed.size());
        result.ratio = (input_len > 0) ? (static_cast<float>(decompressed.size()) / static_cast<float>(input_len)) : 1.0f;
        return result;
    }

    if (!decompressed.empty())
        std::memcpy(output.data(), decompressed.data(), decompressed.size());

    result.success = true;
    result.original_size = static_cast<int64_t>(input_len);
    result.compressed_size = static_cast<int64_t>(decompressed.size());
    result.ratio = (input_len > 0) ? (static_cast<float>(decompressed.size()) / static_cast<float>(input_len)) : 1.0f;
    return result;
}

CompressResult ic_decompress_buf(GMBuffer input, GMBuffer output, CompressionFormat format)
{
    CompressResult sentinel{};
    sentinel.format = format;
    return exception_guard("ic_decompress_buf", sentinel,
        [&] { return ic_decompress_buf_impl(input, output, format); });
}

static BufferResult ic_decompress_buf_range_impl(GMBuffer input, int64_t input_offset, int64_t input_length,
    GMBuffer output, int64_t output_offset, CompressionFormat format)
{
    BufferResult result{};
    const char* input_data = nullptr;
    size_t input_size = 0;
    char* output_data = nullptr;
    size_t output_size = 0;
    if (!get_buffer_range(input, input_offset, input_length, input_data, input_size) ||
        !get_buffer_output(output, output_offset, output_data, output_size))
    {
        result.error_message = "Invalid buffer range";
        return result;
    }

    std::string decompressed;
    if (!decompress_raw(std::string_view(input_data, input_size), format, decompressed))
    {
        result.error_message = "Failed to decompress input";
        return result;
    }

    result.bytes_required = static_cast<int64_t>(decompressed.size());
    if (decompressed.size() > output_size)
    {
        result.error_message = "Output buffer is too small";
        return result;
    }

    if (!decompressed.empty())
        std::memcpy(output_data, decompressed.data(), decompressed.size());
    result.success = true;
    result.bytes_written = static_cast<int64_t>(decompressed.size());
    return result;
}

BufferResult ic_decompress_buf_range(GMBuffer input, int64_t input_offset, int64_t input_length,
    GMBuffer output, int64_t output_offset, CompressionFormat format)
{
    return exception_guard("ic_decompress_buf_range",
        [&] { return ic_decompress_buf_range_impl(input, input_offset, input_length, output, output_offset, format); });
}

// =============================================================================
// Archive operations
// =============================================================================

static ListResult ic_list_page_impl(std::string_view archive, int32_t offset);

static std::vector<ArchiveEntry> ic_list_impl(std::string_view archive)
{
    ListResult page = ic_list_page_impl(archive, 0);
    return page.success ? std::move(page.entries) : std::vector<ArchiveEntry>{};
}

std::vector<ArchiveEntry> ic_list(std::string_view archive)
{
    return exception_guard("ic_list", [&] { return ic_list_impl(archive); });
}

static ListResult ic_list_page_impl(std::string_view archive, int32_t offset)
{
    ListResult result{};
    result.next_offset = offset;
    if (offset < 0)
    {
        result.error_message = "Offset must not be negative";
        return result;
    }

    struct archive* a = archive_read_new();
    if (!a)
    {
        result.error_message = "Failed to allocate libarchive reader";
        return result;
    }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        result.error_message = archive_error_or(a, "Failed to open archive");
        LOG_ERROR("ic_list_page: %s (path=%s)", result.error_message.c_str(), std::string(archive).c_str());
        archive_read_free(a);
        return result;
    }

    struct archive_entry* entry;
    int header_status;
    size_t scanned = 0;
    while ((header_status = archive_read_next_header(a, &entry)) == ARCHIVE_OK)
    {
        if (scanned >= MAX_ARCHIVE_ENTRIES)
        {
            result.error_message = "Archive contains too many entries";
            break;
        }
        // A full page is followed by another page only if another header exists.
        // This lookahead is not consumed in next_offset.
        if (result.entries.size() == MAX_LIST_PAGE_ENTRIES)
        {
            result.has_more = true;
            result.next_offset = static_cast<int32_t>(scanned);
            break;
        }
        ++scanned;

        if (scanned <= static_cast<size_t>(offset))
        {
            if (archive_read_data_skip(a) < ARCHIVE_OK)
            {
                result.error_message = archive_error_or(a, "Failed to skip archive data");
                break;
            }
            continue;
        }

        ArchiveEntry ae;
        ae.filename = archive_entry_pathname_utf8(entry) ? archive_entry_pathname_utf8(entry) : "";
        if (ae.filename.size() > MAX_LIST_PATH_SIZE)
        {
            result.error_message = "Archive entry path is too long to list";
            break;
        }
        // libarchive 3.8.8 exposes no per-entry compressed size or CRC32
        // through its public reader API; -1 and 0 mean unknown.
        ae.compressed_size = -1;
        ae.uncompressed_size = static_cast<int64_t>(archive_entry_size_is_set(entry) ? archive_entry_size(entry) : -1);
        ae.is_directory = (archive_entry_filetype(entry) == AE_IFDIR);
        ae.crc32 = 0;
        result.entries.push_back(std::move(ae));
        if (archive_read_data_skip(a) < ARCHIVE_OK)
        {
            result.error_message = archive_error_or(a, "Failed to skip archive data");
            break;
        }
    }

    if (result.error_message.empty() && !result.has_more && header_status != ARCHIVE_EOF)
        result.error_message = archive_error_or(a, "Failed to read archive header");

    archive_read_close(a);
    archive_read_free(a);
    result.success = result.error_message.empty();
    if (result.success && !result.has_more)
        result.next_offset = static_cast<int32_t>(scanned);
    return result;
}

ListResult ic_list_page(std::string_view archive, int32_t offset)
{
    return exception_guard("ic_list_page", [&] { return ic_list_page_impl(archive, offset); });
}

static ExtractResult ic_extract_impl(std::string_view archive, std::string_view output_dir)
{
    ExtractResult result{};
    result.files_extracted = 0;

    if (output_dir.empty())
    {
        result.error_message = "Output directory must not be empty";
        result.success = false;
        return result;
    }

    struct archive* a = archive_read_new();
    if (!a)
    {
        result.error_message = "Failed to allocate libarchive reader";
        result.success = false;
        return result;
    }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    struct archive* ext = archive_write_disk_new();
    if (!ext)
    {
        result.error_message = "Failed to allocate libarchive handles";
        result.success = false;
        archive_read_free(a);
        return result;
    }

    archive_write_disk_set_options(ext,
        ARCHIVE_EXTRACT_TIME |
        ARCHIVE_EXTRACT_PERM |
        ARCHIVE_EXTRACT_SECURE_NODOTDOT |
        ARCHIVE_EXTRACT_SECURE_SYMLINKS);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        result.error_message = archive_error_or(a, "Failed to open archive");
        result.success = false;
        archive_read_free(a);
        archive_write_free(ext);
        return result;
    }

    struct archive_entry* entry;
    int header_status;
    size_t entry_count = 0;
    uint64_t total_extracted = 0; // Logical bytes, including sparse holes.
    uint64_t total_data_written = 0;
    while ((header_status = archive_read_next_header(a, &entry)) == ARCHIVE_OK)
    {
        std::string entry_path = entry_pathname_utf8(entry);
        const auto filetype = archive_entry_filetype(entry);
        if (++entry_count > MAX_ARCHIVE_ENTRIES ||
            entry_path.size() > MAX_ENTRY_PATH_SIZE ||
            !is_safe_archive_entry_path(entry_path) ||
            archive_entry_hardlink(entry) != nullptr ||
            archive_entry_symlink(entry) != nullptr ||
            (filetype != AE_IFREG && filetype != AE_IFDIR))
        {
            archive_read_data_skip(a);
            result.error_message = "Archive contains an unsafe entry: " + truncate_path_for_message(entry_path);
            result.success = false;
            archive_read_close(a);
            archive_read_free(a);
            archive_write_close(ext);
            archive_write_free(ext);
            return result;
        }

        const bool size_known = archive_entry_size_is_set(entry);
        uint64_t entry_logical_size = 0;
        if (size_known)
        {
            const la_int64_t declared_size = archive_entry_size(entry);
            if (declared_size < 0 || static_cast<uint64_t>(declared_size) > MAX_ENTRY_SIZE ||
                static_cast<uint64_t>(declared_size) > MAX_TOTAL_EXTRACT_SIZE - total_extracted)
            {
                result.error_message = "Archive entry exceeds the configured extraction limit";
                result.success = false;
                archive_read_close(a);
                archive_read_free(a);
                archive_write_close(ext);
                archive_write_free(ext);
                return result;
            }
            entry_logical_size = static_cast<uint64_t>(declared_size);
        }
        // The disk writer may extend a sparse file to its declared size when
        // finishing or closing, even if it receives no data blocks. Reserve
        // that complete size before handing the header to the disk writer.
        total_extracted += entry_logical_size;

        std::string outpath = std::string(output_dir) + "/" + entry_path;
        archive_entry_set_pathname_utf8(entry, outpath.c_str());

        int r = archive_write_header(ext, entry);
        if (r == ARCHIVE_OK)
        {
            const void* buff;
            size_t size;
            la_int64_t offset;
            int read_status;
            uint64_t entry_extracted = 0;
            while ((read_status = archive_read_data_block(a, &buff, &size, &offset)) == ARCHIVE_OK)
            {
                const uint64_t block_size = static_cast<uint64_t>(size);
                if (offset < 0 || block_size > MAX_ENTRY_SIZE - entry_extracted ||
                    static_cast<uint64_t>(offset) > MAX_ENTRY_SIZE - block_size ||
                    block_size > MAX_TOTAL_EXTRACT_SIZE - total_data_written)
                {
                    result.error_message = "Archive exceeds the configured extraction limit";
                    result.success = false;
                    archive_read_close(a);
                    archive_read_free(a);
                    archive_write_close(ext);
                    archive_write_free(ext);
                    return result;
                }
                const uint64_t block_end = static_cast<uint64_t>(offset) + block_size;
                const uint64_t logical_growth = block_end > entry_logical_size
                    ? block_end - entry_logical_size : 0;
                if ((size_known && block_end > entry_logical_size) ||
                    logical_growth > MAX_TOTAL_EXTRACT_SIZE - total_extracted)
                {
                    result.error_message = "Archive data exceeds its declared size or the configured extraction limit";
                    result.success = false;
                    archive_read_close(a);
                    archive_read_free(a);
                    archive_write_close(ext);
                    archive_write_free(ext);
                    return result;
                }
                // Unknown-size entries are charged by their highest logical
                // endpoint, not just by the data stored in each sparse block.
                total_extracted += logical_growth;
                entry_logical_size += logical_growth;
                auto wr = archive_write_data_block(ext, buff, size, offset);
                if (wr < ARCHIVE_OK)
                {
                    result.error_message = archive_error_or(ext, "Failed to write archive data");
                    result.success = false;
                    archive_read_close(a);
                    archive_read_free(a);
                    archive_write_close(ext);
                    archive_write_free(ext);
                    return result;
                }
                entry_extracted += block_size;
                total_data_written += block_size;
            }
            if (read_status != ARCHIVE_EOF || archive_write_finish_entry(ext) < ARCHIVE_OK)
            {
                result.error_message = archive_error_string(a) ? archive_error_string(a) : "Failed to finish archive entry";
                result.success = false;
                archive_read_close(a);
                archive_read_free(a);
                archive_write_close(ext);
                archive_write_free(ext);
                return result;
            }
            if (filetype == AE_IFREG)
                result.files_extracted++;
        }
        else
        {
            result.error_message = archive_error_or(ext, "Failed to create extracted entry");
            result.success = false;
            archive_read_data_skip(a);
            archive_read_close(a);
            archive_read_free(a);
            archive_write_close(ext);
            archive_write_free(ext);
            return result;
        }
    }

    if (header_status != ARCHIVE_EOF)
    {
        result.error_message = archive_error_string(a) ? archive_error_string(a) : "Failed to read archive header";
        result.success = false;
        archive_read_close(a);
        archive_read_free(a);
        archive_write_close(ext);
        archive_write_free(ext);
        return result;
    }

    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);

    result.success = true;
    return result;
}

ExtractResult ic_extract(std::string_view archive, std::string_view output_dir)
{
    return exception_guard("ic_extract", [&] { return ic_extract_impl(archive, output_dir); });
}

static bool ic_extract_file_impl(std::string_view archive, std::string_view entry, std::string_view output)
{
    struct archive* a = archive_read_new();
    if (!a)
        return false;
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        archive_read_free(a);
        return false;
    }

    bool found = false;
    struct archive_entry* ae;
    size_t entry_count = 0;
    while (archive_read_next_header(a, &ae) == ARCHIVE_OK)
    {
        std::string pathname = entry_pathname_utf8(ae);
        if (++entry_count > MAX_ARCHIVE_ENTRIES || pathname.size() > MAX_ENTRY_PATH_SIZE)
            break;
        if (pathname == entry && archive_entry_filetype(ae) == AE_IFREG)
        {
            std::string data;
            std::string error;
            if (!read_current_entry(a, data, MAX_ENTRY_SIZE, error))
                break;

            FOPEN_OFSTREAM(out, output, std::ios::binary);
            if (out)
            {
                out.write(data.data(), static_cast<std::streamsize>(data.size()));
                out.close();
                found = static_cast<bool>(out);
            }
            break;
        }
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);
    return found;
}

bool ic_extract_file(std::string_view archive, std::string_view entry, std::string_view output)
{
    return exception_guard("ic_extract_file", [&] { return ic_extract_file_impl(archive, entry, output); });
}

static std::string ic_extract_mem_impl(std::string_view archive, std::string_view entry)
{
    struct archive* a = archive_read_new();
    if (!a)
    {
        LOG_ERROR("ic_extract_mem: archive_read_new() returned null");
        return "";
    }

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        LOG_ERROR("ic_extract_mem: archive_read_open_filename failed: %s (path=%s)", archive_error_string(a), std::string(archive).c_str());
        archive_read_free(a);
        return "";
    }

    std::string result;
    struct archive_entry* ae;
    size_t entry_count = 0;
    while (archive_read_next_header(a, &ae) == ARCHIVE_OK)
    {
        std::string pathname = entry_pathname_utf8(ae);
        if (++entry_count > MAX_ARCHIVE_ENTRIES || pathname.size() > MAX_ENTRY_PATH_SIZE)
        {
            LOG_ERROR("ic_extract_mem: archive entry scan limit exceeded");
            break;
        }
        int filetype = archive_entry_filetype(ae);
        if (pathname != entry || filetype != AE_IFREG)
        {
            archive_read_data_skip(a);
            continue;
        }

        std::string error;
        if (!read_current_entry(a, result, MAX_ENTRY_SIZE, error))
        {
            LOG_ERROR("ic_extract_mem: %s", error.c_str());
            result.clear();
        }
        break;
    }

    archive_read_close(a);
    archive_read_free(a);
    return result;
}

std::string ic_extract_mem(std::string_view archive, std::string_view entry)
{
    return exception_guard("ic_extract_mem", [&] { return ic_extract_mem_impl(archive, entry); });
}

static BufferResult ic_extract_buf_impl(std::string_view archive, std::string_view entry,
    GMBuffer output, int64_t output_offset)
{
    BufferResult result{};
    char* output_data = nullptr;
    size_t output_size = 0;
    if (!get_buffer_output(output, output_offset, output_data, output_size))
    {
        result.error_message = "Invalid output buffer range";
        return result;
    }

    struct archive* a = archive_read_new();
    if (!a)
    {
        result.error_message = "Failed to allocate libarchive reader";
        return result;
    }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    if (OPEN_ARCHIVE_READ(a, archive, 10240) != ARCHIVE_OK)
    {
        result.error_message = archive_error_string(a) ? archive_error_string(a) : "Failed to open archive";
        archive_read_free(a);
        return result;
    }

    struct archive_entry* archive_entry;
    bool found = false;
    size_t entry_count = 0;
    while (archive_read_next_header(a, &archive_entry) == ARCHIVE_OK)
    {
        std::string pathname = entry_pathname_utf8(archive_entry);
        if (++entry_count > MAX_ARCHIVE_ENTRIES || pathname.size() > MAX_ENTRY_PATH_SIZE)
        {
            result.error_message = "Archive entry scan limit exceeded";
            break;
        }
        if (pathname != entry || archive_entry_filetype(archive_entry) != AE_IFREG)
        {
            archive_read_data_skip(a);
            continue;
        }

        found = true;
        std::string data;
        if (!read_current_entry(a, data, MAX_ENTRY_SIZE, result.error_message))
            break;
        result.bytes_required = static_cast<int64_t>(data.size());
        if (data.size() > output_size)
        {
            result.error_message = "Output buffer is too small";
            break;
        }
        if (!data.empty())
            std::memcpy(output_data, data.data(), data.size());
        result.success = true;
        result.bytes_written = static_cast<int64_t>(data.size());
        break;
    }

    if (!found && result.error_message.empty())
        result.error_message = "Archive entry was not found";
    archive_read_close(a);
    archive_read_free(a);
    return result;
}

BufferResult ic_extract_buf(std::string_view archive, std::string_view entry,
    GMBuffer output, int64_t output_offset)
{
    return exception_guard("ic_extract_buf",
        [&] { return ic_extract_buf_impl(archive, entry, output, output_offset); });
}

// =============================================================================
// Archive creation (handle-based)
// =============================================================================

static std::map<int32_t, struct archive*> g_archive_writers;
static int32_t g_next_handle = 1;

static int32_t allocate_archive_handle()
{
    for (size_t attempts = 0; attempts <= MAX_OPEN_ARCHIVES; ++attempts)
    {
        if (g_next_handle <= 0)
            g_next_handle = 1;
        const int32_t candidate = g_next_handle;
        g_next_handle = (g_next_handle == std::numeric_limits<int32_t>::max()) ? 1 : g_next_handle + 1;
        if (g_archive_writers.find(candidate) == g_archive_writers.end())
            return candidate;
    }
    return -1;
}

static int32_t ic_create_impl(std::string_view archive, CompressionFormat format)
{
    if (g_archive_writers.size() >= MAX_OPEN_ARCHIVES)
    {
        LOG_ERROR("ic_create: maximum number of open archives reached");
        return -1;
    }

    struct archive* a = archive_write_new();
    if (!a)
    {
        LOG_ERROR("ic_create: archive_write_new() returned null");
        return -1;
    }

    if (!configure_archive_writer(a, format, static_cast<int32_t>(CompressionLevel::Default)))
    {
        archive_write_free(a);
        return -1;
    }

    int r = OPEN_ARCHIVE_WRITE(a, archive);
    if (r != ARCHIVE_OK)
    {
        LOG_ERROR("ic_create: archive_write_open_filename failed: %s (path=%s)", archive_error_string(a), std::string(archive).c_str());
        archive_write_free(a);
        return -1;
    }

    const int32_t handle = allocate_archive_handle();
    if (handle < 0)
    {
        archive_write_close(a);
        archive_write_free(a);
        return -1;
    }
    g_archive_writers[handle] = a;
    return handle;
}

int32_t ic_create(std::string_view archive, CompressionFormat format)
{
    return exception_guard("ic_create", [&] { return ic_create_impl(archive, format); });
}

static bool ic_add_file_impl(int32_t handle, std::string_view path, std::string_view entry)
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

    const int64_t file_size = static_cast<int64_t>(in.tellg());
    if (file_size < 0)
        return false;
    in.seekg(0);

    struct archive_entry* ae = archive_entry_new();
    if (!ae)
        return false;
    archive_entry_set_pathname_utf8(ae, std::string(entry).c_str());
    archive_entry_set_filetype(ae, AE_IFREG);
    archive_entry_set_size(ae, static_cast<la_int64_t>(file_size));
    archive_entry_set_perm(ae, 0644);

    int r = archive_write_header(a, ae);
    if (r != ARCHIVE_OK)
    {
        archive_entry_free(ae);
        return false;
    }

    const bool ok = stream_file_to_entry(in, a, file_size);
    archive_entry_free(ae);
    return ok;
}

bool ic_add_file(int32_t handle, std::string_view path, std::string_view entry)
{
    return exception_guard("ic_add_file", [&] { return ic_add_file_impl(handle, path, entry); });
}

static bool ic_add_data_impl(int32_t handle, std::string_view entry, std::string_view data)
{
    auto it = g_archive_writers.find(handle);
    if (it == g_archive_writers.end()) return false;

    struct archive* a = it->second;

    struct archive_entry* ae = archive_entry_new();
    if (!ae)
        return false;
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

    const la_ssize_t written = archive_write_data(a, data.data(), data.size());
    archive_entry_free(ae);
    return written >= 0 && static_cast<size_t>(written) == data.size();
}

bool ic_add_data(int32_t handle, std::string_view entry, std::string_view data)
{
    return exception_guard("ic_add_data", [&] { return ic_add_data_impl(handle, entry, data); });
}

static bool ic_add_buf_impl(int32_t handle, std::string_view entry, GMBuffer data,
    int64_t data_offset, int64_t data_length)
{
    const char* input_data = nullptr;
    size_t input_size = 0;
    if (!get_buffer_range(data, data_offset, data_length, input_data, input_size))
        return false;
    return ic_add_data_impl(handle, entry, std::string_view(input_data, input_size));
}

bool ic_add_buf(int32_t handle, std::string_view entry, GMBuffer data,
    int64_t data_offset, int64_t data_length)
{
    return exception_guard("ic_add_buf",
        [&] { return ic_add_buf_impl(handle, entry, data, data_offset, data_length); });
}

static bool ic_close_impl(int32_t handle)
{
    auto it = g_archive_writers.find(handle);
    if (it == g_archive_writers.end()) return false;

    struct archive* a = it->second;
    const int close_status = archive_write_close(a);
    const int free_status = archive_write_free(a);
    g_archive_writers.erase(it);
    return close_status >= ARCHIVE_OK && free_status >= ARCHIVE_OK;
}

bool ic_close(int32_t handle)
{
    return exception_guard("ic_close", [&] { return ic_close_impl(handle); });
}

static void ic_shutdown_impl()
{
    for (auto& writer : g_archive_writers)
    {
        archive_write_close(writer.second);
        archive_write_free(writer.second);
    }
    g_archive_writers.clear();
    g_next_handle = 1;
}

void ic_shutdown()
{
    exception_guard("ic_shutdown", [&] { ic_shutdown_impl(); });
}

// =============================================================================
// Utility functions
// =============================================================================

static CompressionFormat ic_detect_impl(GMBuffer data)
{
    std::string_view view(static_cast<const char*>(data.data()), static_cast<size_t>(data.length()));
    return detect_from_magic(view);
}

CompressionFormat ic_detect(GMBuffer data)
{
    return exception_guard("ic_detect", [&] { return ic_detect_impl(data); });
}

static CompressionFormat ic_detect_file_impl(std::string_view path)
{
    FOPEN_IFSTREAM(in, path, std::ios::binary);
    if (!in) return CompressionFormat::Raw;

    char buf[512];
    in.read(buf, sizeof(buf));
    std::streamsize read = in.gcount();
    in.close();

    if (read <= 0) return CompressionFormat::Raw;

    std::string_view sv(buf, static_cast<size_t>(read));
    return detect_from_magic(sv);
}

CompressionFormat ic_detect_file(std::string_view path)
{
    return exception_guard("ic_detect_file", [&] { return ic_detect_file_impl(path); });
}

static CompressionFormat ic_from_ext_impl(std::string_view name)
{
    return detect_from_ext(name);
}

CompressionFormat ic_from_ext(std::string_view name)
{
    return exception_guard("ic_from_ext", [&] { return ic_from_ext_impl(name); });
}

static std::string ic_to_str_impl(CompressionFormat format)
{
    return format_to_str(format);
}

std::string ic_to_str(CompressionFormat format)
{
    return exception_guard("ic_to_str", [&] { return ic_to_str_impl(format); });
}
