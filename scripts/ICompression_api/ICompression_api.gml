// ##### extgen :: Auto-generated file do not edit!! #####

// #####################################################################
// # Macros
// #####################################################################

// #####################################################################
// # Enums
// #####################################################################

enum CompressionFormat
{
    Zip = 0,
    SevenZ = 1,
    Gzip = 2,
    Zstd = 3,
    Lz4 = 4,
    Xz = 5,
    Tar = 6,
    Raw = 7
}

enum CompressionLevel
{
    Fastest = 0,
    Default = 1,
    Optimal = 2
}

// #####################################################################
// # Constructors
// #####################################################################

/**
 * @returns {Struct.ArchiveEntry} 
 */
function ArchiveEntry() constructor
{
    /**
     * Internally generated hash for quick validation
     * @ignore 
     */
    static __EXT_NATIVE__uid = 4225351699;

    self.filename = undefined;
    self.compressed_size = undefined;
    self.uncompressed_size = undefined;
    self.is_directory = undefined;
    self.crc32 = undefined;

}

/**
 * @returns {Struct.ExtractResult} 
 */
function ExtractResult() constructor
{
    /**
     * Internally generated hash for quick validation
     * @ignore 
     */
    static __EXT_NATIVE__uid = 2788600535;

    self.success = undefined;
    self.files_extracted = undefined;
    self.error_message = undefined;

}

/**
 * @returns {Struct.CompressResult} 
 */
function CompressResult() constructor
{
    /**
     * Internally generated hash for quick validation
     * @ignore 
     */
    static __EXT_NATIVE__uid = 2506395900;

    self.success = undefined;
    self.original_size = undefined;
    self.compressed_size = undefined;
    self.format = undefined;
    self.ratio = undefined;

}

// #####################################################################
// # Codecs
// #####################################################################

/**
 * @func __EXT_NATIVE__ArchiveEntry_encode(_inst, _buffer, _offset, _where)
 * @param {Struct.ArchiveEntry} _inst
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @param {String} _where
 * @ignore 
 */
function __EXT_NATIVE__ArchiveEntry_encode(_inst, _buffer, _offset, _where = _GMFUNCTION_)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);
    with (_inst)
    {
        // field: filename, type: String
        if (!is_string(self.filename)) show_error($"{_where} :: self.filename expected string", true);
        buffer_write(_buffer, buffer_u32, string_byte_length(self.filename));
        buffer_write(_buffer, buffer_string, self.filename);

        // field: compressed_size, type: Int64
        if (!is_numeric(self.compressed_size)) show_error($"{_where} :: self.compressed_size expected number", true);
        buffer_write(_buffer, buffer_u64, self.compressed_size);

        // field: uncompressed_size, type: Int64
        if (!is_numeric(self.uncompressed_size)) show_error($"{_where} :: self.uncompressed_size expected number", true);
        buffer_write(_buffer, buffer_u64, self.uncompressed_size);

        // field: is_directory, type: Bool
        if (!is_bool(self.is_directory)) show_error($"{_where} :: self.is_directory expected bool", true);
        buffer_write(_buffer, buffer_bool, self.is_directory);

        // field: crc32, type: UInt32
        if (!is_numeric(self.crc32)) show_error($"{_where} :: self.crc32 expected number", true);
        buffer_write(_buffer, buffer_u32, self.crc32);

    }
}

/**
 * @func __EXT_NATIVE__ArchiveEntry_decode(_buffer, _offset)
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @returns {Struct.ArchiveEntry} 
 * @ignore 
 */
function __EXT_NATIVE__ArchiveEntry_decode(_buffer, _offset)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);

    _inst = new ArchiveEntry();
    with (_inst)
    {
        // field: filename, type: String
        buffer_read(_buffer, buffer_u32);
        self.filename = buffer_read(_buffer, buffer_string);

        // field: compressed_size, type: Int64
        self.compressed_size = buffer_read(_buffer, buffer_u64);

        // field: uncompressed_size, type: Int64
        self.uncompressed_size = buffer_read(_buffer, buffer_u64);

        // field: is_directory, type: Bool
        self.is_directory = buffer_read(_buffer, buffer_bool);

        // field: crc32, type: UInt32
        self.crc32 = buffer_read(_buffer, buffer_u32);

    }

    return _inst;
}

/**
 * @func __EXT_NATIVE__ExtractResult_encode(_inst, _buffer, _offset, _where)
 * @param {Struct.ExtractResult} _inst
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @param {String} _where
 * @ignore 
 */
function __EXT_NATIVE__ExtractResult_encode(_inst, _buffer, _offset, _where = _GMFUNCTION_)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);
    with (_inst)
    {
        // field: success, type: Bool
        if (!is_bool(self.success)) show_error($"{_where} :: self.success expected bool", true);
        buffer_write(_buffer, buffer_bool, self.success);

        // field: files_extracted, type: Int32
        if (!is_numeric(self.files_extracted)) show_error($"{_where} :: self.files_extracted expected number", true);
        buffer_write(_buffer, buffer_s32, self.files_extracted);

        // field: error_message, type: String
        if (!is_string(self.error_message)) show_error($"{_where} :: self.error_message expected string", true);
        buffer_write(_buffer, buffer_u32, string_byte_length(self.error_message));
        buffer_write(_buffer, buffer_string, self.error_message);

    }
}

/**
 * @func __EXT_NATIVE__ExtractResult_decode(_buffer, _offset)
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @returns {Struct.ExtractResult} 
 * @ignore 
 */
function __EXT_NATIVE__ExtractResult_decode(_buffer, _offset)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);

    _inst = new ExtractResult();
    with (_inst)
    {
        // field: success, type: Bool
        self.success = buffer_read(_buffer, buffer_bool);

        // field: files_extracted, type: Int32
        self.files_extracted = buffer_read(_buffer, buffer_s32);

        // field: error_message, type: String
        buffer_read(_buffer, buffer_u32);
        self.error_message = buffer_read(_buffer, buffer_string);

    }

    return _inst;
}

/**
 * @func __EXT_NATIVE__CompressResult_encode(_inst, _buffer, _offset, _where)
 * @param {Struct.CompressResult} _inst
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @param {String} _where
 * @ignore 
 */
function __EXT_NATIVE__CompressResult_encode(_inst, _buffer, _offset, _where = _GMFUNCTION_)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);
    with (_inst)
    {
        // field: success, type: Bool
        if (!is_bool(self.success)) show_error($"{_where} :: self.success expected bool", true);
        buffer_write(_buffer, buffer_bool, self.success);

        // field: original_size, type: Int64
        if (!is_numeric(self.original_size)) show_error($"{_where} :: self.original_size expected number", true);
        buffer_write(_buffer, buffer_u64, self.original_size);

        // field: compressed_size, type: Int64
        if (!is_numeric(self.compressed_size)) show_error($"{_where} :: self.compressed_size expected number", true);
        buffer_write(_buffer, buffer_u64, self.compressed_size);

        // field: format, type: enum CompressionFormat

        if (!is_numeric(self.format)) show_error($"{_where} :: self.format expected number", true);
        buffer_write(_buffer, buffer_u64, self.format);

        // field: ratio, type: Float32
        if (!is_numeric(self.ratio)) show_error($"{_where} :: self.ratio expected number", true);
        buffer_write(_buffer, buffer_f32, self.ratio);

    }
}

/**
 * @func __EXT_NATIVE__CompressResult_decode(_buffer, _offset)
 * @param {Id.Buffer} _buffer
 * @param {Real} _offset
 * @returns {Struct.CompressResult} 
 * @ignore 
 */
function __EXT_NATIVE__CompressResult_decode(_buffer, _offset)
{
    buffer_seek(_buffer, buffer_seek_start, _offset);

    _inst = new CompressResult();
    with (_inst)
    {
        // field: success, type: Bool
        self.success = buffer_read(_buffer, buffer_bool);

        // field: original_size, type: Int64
        self.original_size = buffer_read(_buffer, buffer_u64);

        // field: compressed_size, type: Int64
        self.compressed_size = buffer_read(_buffer, buffer_u64);

        // field: format, type: enum CompressionFormat
        self.format = buffer_read(_buffer, buffer_u64);

        // field: ratio, type: Float32
        self.ratio = buffer_read(_buffer, buffer_f32);

    }

    return _inst;
}

// #####################################################################
// # Functions
// #####################################################################

/**
 * @param {String} _data
 * @param {Enum.CompressionFormat} _format
 * @param {Real} _level
 * @returns {String} 
 */
function ic_compress(_data, _format, _level)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _data, type: String
    if (!is_string(_data)) show_error($"{_GMFUNCTION_} :: _data expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_data));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _data);

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    // param: _level, type: Int32
    if (!is_numeric(_level)) show_error($"{_GMFUNCTION_} :: _level expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_s32, _level);

    var _return_value = __EXT_NATIVE__ic_compress(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

/**
 * @param {String} _data
 * @param {Enum.CompressionFormat} _format
 * @returns {String} 
 */
function ic_decompress(_data, _format)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _data, type: String
    if (!is_string(_data)) show_error($"{_GMFUNCTION_} :: _data expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_data));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _data);

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    var _return_value = __EXT_NATIVE__ic_decompress(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

/**
 * @param {String} _src
 * @param {String} _dst
 * @param {Enum.CompressionFormat} _format
 * @param {Real} _level
 * @returns {Bool} 
 */
function ic_compress_file(_src, _dst, _format, _level)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _src, type: String
    if (!is_string(_src)) show_error($"{_GMFUNCTION_} :: _src expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_src));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _src);

    // param: _dst, type: String
    if (!is_string(_dst)) show_error($"{_GMFUNCTION_} :: _dst expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_dst));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _dst);

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    // param: _level, type: Int32
    if (!is_numeric(_level)) show_error($"{_GMFUNCTION_} :: _level expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_s32, _level);

    var _return_value = __EXT_NATIVE__ic_compress_file(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

/**
 * @param {String} _src
 * @param {String} _dst
 * @param {Enum.CompressionFormat} _format
 * @returns {Bool} 
 */
function ic_decompress_file(_src, _dst, _format)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _src, type: String
    if (!is_string(_src)) show_error($"{_GMFUNCTION_} :: _src expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_src));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _src);

    // param: _dst, type: String
    if (!is_string(_dst)) show_error($"{_GMFUNCTION_} :: _dst expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_dst));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _dst);

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    var _return_value = __EXT_NATIVE__ic_decompress_file(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

/**
 * @param {Id.Buffer} _input
 * @param {Id.Buffer} _output
 * @param {Enum.CompressionFormat} _format
 * @param {Real} _level
 * @returns {Struct.CompressResult} 
 */
function ic_compress_buf(_input, _output, _format, _level)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _input, type: Buffer
    if (!buffer_exists(_input)) show_error($"{_GMFUNCTION_} :: _input expected Id.Buffer", true);
    __EXT_NATIVE__ICompression_queue_buffer(buffer_get_address(_input), buffer_get_size(_input));

    // param: _output, type: Buffer
    if (!buffer_exists(_output)) show_error($"{_GMFUNCTION_} :: _output expected Id.Buffer", true);
    __EXT_NATIVE__ICompression_queue_buffer(buffer_get_address(_output), buffer_get_size(_output));

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    // param: _level, type: Int32
    if (!is_numeric(_level)) show_error($"{_GMFUNCTION_} :: _level expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_s32, _level);

    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_compress_buf(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer), buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = __EXT_NATIVE__CompressResult_decode(__EXT_NATIVE__ret_buffer, buffer_tell(__EXT_NATIVE__ret_buffer));
    return _result;
}

/**
 * @param {Id.Buffer} _input
 * @param {Id.Buffer} _output
 * @param {Enum.CompressionFormat} _format
 * @returns {Struct.CompressResult} 
 */
function ic_decompress_buf(_input, _output, _format)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _input, type: Buffer
    if (!buffer_exists(_input)) show_error($"{_GMFUNCTION_} :: _input expected Id.Buffer", true);
    __EXT_NATIVE__ICompression_queue_buffer(buffer_get_address(_input), buffer_get_size(_input));

    // param: _output, type: Buffer
    if (!buffer_exists(_output)) show_error($"{_GMFUNCTION_} :: _output expected Id.Buffer", true);
    __EXT_NATIVE__ICompression_queue_buffer(buffer_get_address(_output), buffer_get_size(_output));

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_decompress_buf(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer), buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = __EXT_NATIVE__CompressResult_decode(__EXT_NATIVE__ret_buffer, buffer_tell(__EXT_NATIVE__ret_buffer));
    return _result;
}

/**
 * @param {String} _archive
 * @returns {Any} 
 */
function ic_list(_archive)
{
    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_list(_archive, buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = __ext_core_buffer_unmarshal_value(__EXT_NATIVE__ret_buffer, __EXT_NATIVE__decoders);
    return _result;
}

/**
 * @param {String} _archive
 * @param {String} _output_dir
 * @returns {Struct.ExtractResult} 
 */
function ic_extract(_archive, _output_dir)
{
    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_extract(_archive, _output_dir, buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = __EXT_NATIVE__ExtractResult_decode(__EXT_NATIVE__ret_buffer, buffer_tell(__EXT_NATIVE__ret_buffer));
    return _result;
}

// Skipping function ic_extract_file (no wrapper is required)


// Skipping function ic_extract_mem (no wrapper is required)


/**
 * @param {String} _archive
 * @param {Enum.CompressionFormat} _format
 * @returns {Bool} 
 */
function ic_create(_archive, _format)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _archive, type: String
    if (!is_string(_archive)) show_error($"{_GMFUNCTION_} :: _archive expected string", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u32, string_byte_length(_archive));
    buffer_write(__EXT_NATIVE__args_buffer, buffer_string, _archive);

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    var _return_value = __EXT_NATIVE__ic_create(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

// Skipping function ic_add_file (no wrapper is required)


// Skipping function ic_add_data (no wrapper is required)


// Skipping function ic_close (no wrapper is required)


/**
 * @param {String} _data
 * @returns {Enum.CompressionFormat} 
 */
function ic_detect(_data)
{
    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_detect(_data, buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = buffer_read(__EXT_NATIVE__ret_buffer, buffer_u64);
    return _result;
}

/**
 * @param {String} _path
 * @returns {Enum.CompressionFormat} 
 */
function ic_detect_file(_path)
{
    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_detect_file(_path, buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = buffer_read(__EXT_NATIVE__ret_buffer, buffer_u64);
    return _result;
}

/**
 * @param {String} _name
 * @returns {Enum.CompressionFormat} 
 */
function ic_from_ext(_name)
{
    var __EXT_NATIVE__ret_buffer = __ext_core_get_ret_buffer();

    var _return_value = __EXT_NATIVE__ic_from_ext(_name, buffer_get_address(__EXT_NATIVE__ret_buffer), buffer_get_size(__EXT_NATIVE__ret_buffer));

    var _result = undefined;
    _result = buffer_read(__EXT_NATIVE__ret_buffer, buffer_u64);
    return _result;
}

/**
 * @param {Enum.CompressionFormat} _format
 * @returns {String} 
 */
function ic_to_str(_format)
{
    var __EXT_NATIVE__args_buffer = __ext_core_get_args_buffer();

    // param: _format, type: enum CompressionFormat

    if (!is_numeric(_format)) show_error($"{_GMFUNCTION_} :: _format expected number", true);
    buffer_write(__EXT_NATIVE__args_buffer, buffer_u64, _format);

    var _return_value = __EXT_NATIVE__ic_to_str(buffer_get_address(__EXT_NATIVE__args_buffer), buffer_tell(__EXT_NATIVE__args_buffer));

    return _return_value;
}

/// @ignore
function __EXT_NATIVE__ICompression_get_decoders()
{
    static __EXT_NATIVE__decoders = [
        __EXT_NATIVE__ArchiveEntry_decode,
        __EXT_NATIVE__ExtractResult_decode,
        __EXT_NATIVE__CompressResult_decode
    ];
    return __EXT_NATIVE__decoders;
}
