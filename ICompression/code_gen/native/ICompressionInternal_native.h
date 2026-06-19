// ##### extgen :: Auto-generated file do not edit!! #####

#pragma once
#include <cstdint>
#include <string_view>
#include <vector>
#include <array>
#include <optional>
#include "core/GMExtWire.h"

namespace gm_consts
{
}


namespace gm_enums
{
    enum class CompressionFormat : std::int64_t
    {
        Zip = 0,
        SevenZ = 1,
        Gzip = 2,
        Zstd = 3,
        Lz4 = 4,
        Xz = 5,
        Tar = 6,
        Raw = 7
    };

    enum class CompressionLevel : std::int64_t
    {
        Fastest = 0,
        Default = 1,
        Optimal = 2
    };

}


namespace gm_structs
{
    struct ArchiveEntry;
    struct ExtractResult;
    struct CompressResult;

    struct ArchiveEntry
    {
        std::string filename;
        std::int64_t compressed_size;
        std::int64_t uncompressed_size;
        bool is_directory;
        std::uint32_t crc32;
    };

    struct ExtractResult
    {
        bool success;
        std::int32_t files_extracted;
        std::string error_message;
    };

    struct CompressResult
    {
        bool success;
        std::int64_t original_size;
        std::int64_t compressed_size;
        gm_enums::CompressionFormat format;
        float ratio;
    };

}

namespace gm::wire::codec
{
    template<>
    inline void writeValue<gm_structs::ArchiveEntry>(gm::byteio::IByteWriter& _buf, const gm_structs::ArchiveEntry& obj)
    {
        gm::wire::codec::writeValue(_buf, obj.filename);
        gm::wire::codec::writeValue(_buf, obj.compressed_size);
        gm::wire::codec::writeValue(_buf, obj.uncompressed_size);
        gm::wire::codec::writeValue(_buf, obj.is_directory);
        gm::wire::codec::writeValue(_buf, obj.crc32);
    }

    template<>
    inline gm_structs::ArchiveEntry readValue<gm_structs::ArchiveEntry>(gm::byteio::BufferReader& _buf)
    {
        gm_structs::ArchiveEntry obj;
        obj.filename = gm::wire::codec::readValue<std::string>(_buf);
        obj.compressed_size = gm::wire::codec::readValue<std::int64_t>(_buf);
        obj.uncompressed_size = gm::wire::codec::readValue<std::int64_t>(_buf);
        obj.is_directory = gm::wire::codec::readValue<bool>(_buf);
        obj.crc32 = gm::wire::codec::readValue<std::uint32_t>(_buf);
        return obj;
    }

    template<>
    inline void writeValue<gm_structs::ExtractResult>(gm::byteio::IByteWriter& _buf, const gm_structs::ExtractResult& obj)
    {
        gm::wire::codec::writeValue(_buf, obj.success);
        gm::wire::codec::writeValue(_buf, obj.files_extracted);
        gm::wire::codec::writeValue(_buf, obj.error_message);
    }

    template<>
    inline gm_structs::ExtractResult readValue<gm_structs::ExtractResult>(gm::byteio::BufferReader& _buf)
    {
        gm_structs::ExtractResult obj;
        obj.success = gm::wire::codec::readValue<bool>(_buf);
        obj.files_extracted = gm::wire::codec::readValue<std::int32_t>(_buf);
        obj.error_message = gm::wire::codec::readValue<std::string>(_buf);
        return obj;
    }

    template<>
    inline void writeValue<gm_structs::CompressResult>(gm::byteio::IByteWriter& _buf, const gm_structs::CompressResult& obj)
    {
        gm::wire::codec::writeValue(_buf, obj.success);
        gm::wire::codec::writeValue(_buf, obj.original_size);
        gm::wire::codec::writeValue(_buf, obj.compressed_size);
        gm::wire::codec::writeValue(_buf, obj.format);
        gm::wire::codec::writeValue(_buf, obj.ratio);
    }

    template<>
    inline gm_structs::CompressResult readValue<gm_structs::CompressResult>(gm::byteio::BufferReader& _buf)
    {
        gm_structs::CompressResult obj;
        obj.success = gm::wire::codec::readValue<bool>(_buf);
        obj.original_size = gm::wire::codec::readValue<std::int64_t>(_buf);
        obj.compressed_size = gm::wire::codec::readValue<std::int64_t>(_buf);
        obj.format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(_buf);
        obj.ratio = gm::wire::codec::readValue<float>(_buf);
        return obj;
    }

}

namespace gm::wire::details
{
    template<>
    struct gm_struct_traits<gm_structs::ArchiveEntry>
    {
        static constexpr bool is_gm_struct = true;
        static constexpr std::uint32_t codec_id = 0;
    };

    template<>
    struct gm_struct_traits<gm_structs::ExtractResult>
    {
        static constexpr bool is_gm_struct = true;
        static constexpr std::uint32_t codec_id = 1;
    };

    template<>
    struct gm_struct_traits<gm_structs::CompressResult>
    {
        static constexpr bool is_gm_struct = true;
        static constexpr std::uint32_t codec_id = 2;
    };

}

std::string ic_compress(std::string_view data, gm_enums::CompressionFormat format, std::int32_t level);
std::string ic_decompress(std::string_view data, gm_enums::CompressionFormat format);
bool ic_compress_file(std::string_view src, std::string_view dst, gm_enums::CompressionFormat format, std::int32_t level);
bool ic_decompress_file(std::string_view src, std::string_view dst, gm_enums::CompressionFormat format);
gm_structs::CompressResult ic_compress_buf(gm::wire::GMBuffer input, gm::wire::GMBuffer output, gm_enums::CompressionFormat format, std::int32_t level);
gm_structs::CompressResult ic_decompress_buf(gm::wire::GMBuffer input, gm::wire::GMBuffer output, gm_enums::CompressionFormat format);
gm::wire::ArrayStream ic_list(std::string_view archive);
gm_structs::ExtractResult ic_extract(std::string_view archive, std::string_view output_dir);
bool ic_extract_file(std::string_view archive, std::string_view entry, std::string_view output);
std::string ic_extract_mem(std::string_view archive, std::string_view entry);
std::int32_t ic_create(std::string_view archive, gm_enums::CompressionFormat format);
bool ic_add_file(std::int32_t handle, std::string_view path, std::string_view entry);
bool ic_add_data(std::int32_t handle, std::string_view entry, std::string_view data);
bool ic_close(std::int32_t handle);
gm_enums::CompressionFormat ic_detect(std::string_view data);
gm_enums::CompressionFormat ic_detect_file(std::string_view path);
gm_enums::CompressionFormat ic_from_ext(std::string_view name);
std::string ic_to_str(gm_enums::CompressionFormat format);
