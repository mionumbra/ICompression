// ##### extgen :: Auto-generated file do not edit!! #####

#include "ICompressionInternal_native.h"
#include "ICompressionInternal_exports.h"

using namespace gm_structs;
using namespace gm::wire::codec;

static std::queue<gm::wire::GMBuffer> __buffer_queue;

// Internal function used for queueing buffers to native code
GMEXPORT double __EXT_NATIVE__ICompression_queue_buffer(char* __arg_buffer, double __arg_buffer_length)
{
    gm::wire::GMBuffer __buff{__arg_buffer, static_cast<uint64_t>(__arg_buffer_length)};
    __buffer_queue.push(__buff);

    return 1.0;
}

GMEXPORT char* __EXT_NATIVE__ic_compress(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: data, type: String
    std::string_view data = gm::wire::codec::readValue<std::string_view>(__br);

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    // field: level, type: Int32
    std::int32_t level = gm::wire::codec::readValue<std::int32_t>(__br);

    static std::string __result;
    __result = ic_compress(data, format, level);
    return (char*)__result.c_str();
}

GMEXPORT char* __EXT_NATIVE__ic_decompress(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: data, type: String
    std::string_view data = gm::wire::codec::readValue<std::string_view>(__br);

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    static std::string __result;
    __result = ic_decompress(data, format);
    return (char*)__result.c_str();
}

GMEXPORT double __EXT_NATIVE__ic_compress_file(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: src, type: String
    std::string_view src = gm::wire::codec::readValue<std::string_view>(__br);

    // field: dst, type: String
    std::string_view dst = gm::wire::codec::readValue<std::string_view>(__br);

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    // field: level, type: Int32
    std::int32_t level = gm::wire::codec::readValue<std::int32_t>(__br);

    auto&& __result = ic_compress_file(src, dst, format, level);
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_decompress_file(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: src, type: String
    std::string_view src = gm::wire::codec::readValue<std::string_view>(__br);

    // field: dst, type: String
    std::string_view dst = gm::wire::codec::readValue<std::string_view>(__br);

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    auto&& __result = ic_decompress_file(src, dst, format);
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_compress_buf(char* __arg_buffer, double __arg_buffer_length, char* __ret_buffer, double __ret_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: input, type: Buffer
    gm::wire::GMBuffer input = __buffer_queue.front();
    __buffer_queue.pop();

    // field: output, type: Buffer
    gm::wire::GMBuffer output = __buffer_queue.front();
    __buffer_queue.pop();

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    // field: level, type: Int32
    std::int32_t level = gm::wire::codec::readValue<std::int32_t>(__br);

    auto&& __result = ic_compress_buf(input, output, format, level);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: struct CompressResult
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_decompress_buf(char* __arg_buffer, double __arg_buffer_length, char* __ret_buffer, double __ret_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: input, type: Buffer
    gm::wire::GMBuffer input = __buffer_queue.front();
    __buffer_queue.pop();

    // field: output, type: Buffer
    gm::wire::GMBuffer output = __buffer_queue.front();
    __buffer_queue.pop();

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    auto&& __result = ic_decompress_buf(input, output, format);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: struct CompressResult
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_list(char* archive, char* __ret_buffer, double __ret_buffer_length)
{
    auto&& __result = ic_list(archive);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: Any
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_extract(char* archive, char* output_dir, char* __ret_buffer, double __ret_buffer_length)
{
    auto&& __result = ic_extract(archive, output_dir);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: struct ExtractResult
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_extract_file(char* archive, char* entry, char* output)
{
    auto&& __result = ic_extract_file(archive, entry, output);
    return static_cast<double>(__result);
}

GMEXPORT char* __EXT_NATIVE__ic_extract_mem(char* archive, char* entry)
{
    static std::string __result;
    __result = ic_extract_mem(archive, entry);
    return (char*)__result.c_str();
}

GMEXPORT double __EXT_NATIVE__ic_create(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: archive, type: String
    std::string_view archive = gm::wire::codec::readValue<std::string_view>(__br);

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    auto&& __result = ic_create(archive, format);
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_add_file(double handle, char* path, char* entry)
{
    auto&& __result = ic_add_file(static_cast<std::int32_t>(handle), path, entry);
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_add_data(double handle, char* entry, char* data)
{
    auto&& __result = ic_add_data(static_cast<std::int32_t>(handle), entry, data);
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_close(double handle)
{
    auto&& __result = ic_close(static_cast<std::int32_t>(handle));
    return static_cast<double>(__result);
}

GMEXPORT double __EXT_NATIVE__ic_detect(char* __ret_buffer, double __ret_buffer_length)
{
    gm::wire::GMBuffer input = __buffer_queue.front();
    __buffer_queue.pop();
    std::string_view data(static_cast<const char*>(input.data()), static_cast<size_t>(input.length()));

    auto&& __result = ic_detect(data);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: enum CompressionFormat
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_detect_file(char* path, char* __ret_buffer, double __ret_buffer_length)
{
    auto&& __result = ic_detect_file(path);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: enum CompressionFormat
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT double __EXT_NATIVE__ic_from_ext(char* name, char* __ret_buffer, double __ret_buffer_length)
{
    auto&& __result = ic_from_ext(name);
    gm::byteio::BufferWriter __bw{__ret_buffer, static_cast<size_t>(__ret_buffer_length)};

    // return: __result, type: enum CompressionFormat
    gm::wire::codec::writeValue(__bw, __result);
    return 0;
}

GMEXPORT char* __EXT_NATIVE__ic_to_str(char* __arg_buffer, double __arg_buffer_length)
{
    gm::byteio::BufferReader __br{__arg_buffer, static_cast<size_t>(__arg_buffer_length)};

    // field: format, type: enum CompressionFormat
    gm_enums::CompressionFormat format = gm::wire::codec::readValue<gm_enums::CompressionFormat>(__br);

    static std::string __result;
    __result = ic_to_str(format);
    return (char*)__result.c_str();
}

