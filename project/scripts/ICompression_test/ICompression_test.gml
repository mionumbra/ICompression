// =============================================================================
// ICompression  -  unit tests
// =============================================================================

function __test_summary(_total, _passed)
{
    var _failed = _total - _passed;
    show_debug_message("========================================");
    show_debug_message($"Tests: {_total} total, {_passed} passed, {_failed} failed");
    show_debug_message("========================================");
}

function __test_temp_dir()
{
    var _dir = "IC_test_" + string(date_current_datetime());
    _dir = string_replace_all(_dir, " ", "_");
    _dir = string_replace_all(_dir, ":", "-");
    _dir = working_directory + "/" + _dir;
    return _dir;
}

function __test_cleanup_dir(_dir)
{
    if (directory_exists(_dir)) directory_destroy(_dir);
}

// Regression tests own their resources so a failed assertion still closes writers
// and releases buffers before returning to the suite.
function __test_assert(_condition, _message)
{
    if (!_condition) throw _message;
}

function __test_buffer(_context, _size)
{
    var _buffer = buffer_create(_size, buffer_fixed, 1);
    array_push(_context.buffers, _buffer);
    return _buffer;
}

function __test_load_buffer(_context, _path)
{
    var _buffer = buffer_load(_path);
    __test_assert(_buffer >= 0, "buffer_load: " + _path);
    array_push(_context.buffers, _buffer);
    return _buffer;
}

function __test_writer(_context, _filename, _format)
{
    var _path = _context.directory + "/" + _filename;
    array_push(_context.files, _path);
    var _handle = ic_create(_path, _format);
    __test_assert(_handle >= 0, "ic_create: " + _filename);
    array_push(_context.handles, _handle);
    return _handle;
}

function __test_close_writer(_context, _handle)
{
    var _closed = ic_close(_handle);
    for (var _index = 0; _index < array_length(_context.handles); ++_index) {
        if (_context.handles[_index] == _handle) _context.handles[_index] = -1;
    }
    __test_assert(_closed, "ic_close: " + string(_handle));
}

function __test_equal_bytes(_first, _first_offset, _second, _second_offset, _length)
{
    for (var _index = 0; _index < _length; ++_index) {
        if (buffer_peek(_first, _first_offset + _index, buffer_u8) != buffer_peek(_second, _second_offset + _index, buffer_u8)) return false;
    }
    return true;
}

function __test_with_resources(_name, _body)
{
    show_debug_message("--- " + _name + " ---");
    var _context = { directory: __test_temp_dir() + "_" + string(get_timer()), buffers: [], handles: [], files: [] };
    var _passed = true;
    try {
        directory_create(_context.directory);
        __test_assert(directory_exists(_context.directory), "create temporary directory");
        _body(_context);
    }
    catch (_exception) {
        show_debug_message("[FAIL] " + _name + ": " + string(_exception));
        _passed = false;
    }

    for (var _index = 0; _index < array_length(_context.handles); ++_index) {
        var _handle = _context.handles[_index];
        if (_handle < 0) continue;
        try { __test_assert(ic_close(_handle), "close abandoned writer"); }
        catch (_exception) { show_debug_message("[FAIL] cleanup handle: " + string(_exception)); _passed = false; }
    }
    for (var _index = 0; _index < array_length(_context.buffers); ++_index) {
        var _buffer = _context.buffers[_index];
        try { if (buffer_exists(_buffer)) buffer_delete(_buffer); }
        catch (_exception) { show_debug_message("[FAIL] cleanup buffer: " + string(_exception)); _passed = false; }
    }
    for (var _index = 0; _index < array_length(_context.files); ++_index) {
        var _path = _context.files[_index];
        try {
            if (file_exists(_path)) file_delete(_path);
            __test_assert(!file_exists(_path), "delete temporary file: " + _path);
        }
        catch (_exception) { show_debug_message("[FAIL] cleanup file: " + string(_exception)); _passed = false; }
    }
    try {
        if (directory_exists(_context.directory)) directory_destroy(_context.directory);
        __test_assert(!directory_exists(_context.directory), "delete temporary directory");
    }
    catch (_exception) { show_debug_message("[FAIL] cleanup directory: " + string(_exception)); _passed = false; }
    if (_passed) show_debug_message("[OK] " + _name);
    return _passed;
}

// =============================================================================
// TEST: ic_to_str
// =============================================================================

function test_to_str()
{
    show_debug_message("--- test_to_str ---");

    if (ic_to_str(CompressionFormat.Zip) != "ZIP") { show_debug_message("[FAIL] Zip to_str"); return false; }
    if (ic_to_str(CompressionFormat.SevenZ) != "7z") { show_debug_message("[FAIL] SevenZ to_str"); return false; }
    if (ic_to_str(CompressionFormat.Gzip) != "gzip") { show_debug_message("[FAIL] Gzip to_str"); return false; }
    if (ic_to_str(CompressionFormat.Zstd) != "zstd") { show_debug_message("[FAIL] Zstd to_str"); return false; }
    if (ic_to_str(CompressionFormat.Lz4) != "lz4") { show_debug_message("[FAIL] Lz4 to_str"); return false; }
    if (ic_to_str(CompressionFormat.Xz) != "xz") { show_debug_message("[FAIL] Xz to_str"); return false; }
    if (ic_to_str(CompressionFormat.Tar) != "tar") { show_debug_message("[FAIL] Tar to_str"); return false; }
    if (ic_to_str(CompressionFormat.Raw) != "raw") { show_debug_message("[FAIL] Raw to_str"); return false; }
    if (ic_to_str(CompressionFormat.Bzip2) != "bzip2") { show_debug_message("[FAIL] Bzip2 to_str"); return false; }
    if (ic_to_str(CompressionFormat.Rar) != "rar") { show_debug_message("[FAIL] Rar to_str"); return false; }

    show_debug_message("[OK] test_to_str");
    return true;
}

// =============================================================================
// TEST: ic_detect (magic bytes)
// =============================================================================

function __test_detect_bytes(_bytes)
{
    var _buf = buffer_create(array_length(_bytes), buffer_fixed, 1);
    for (var _i = 0; _i < array_length(_bytes); _i++)
    {
        buffer_write(_buf, buffer_u8, _bytes[_i]);
    }

    var _result = ic_detect(_buf);
    buffer_delete(_buf);
    return _result;
}

function __test_detect_text(_text)
{
    var _buf = buffer_create(string_byte_length(_text), buffer_fixed, 1);
    buffer_write(_buf, buffer_text, _text);

    var _result = ic_detect(_buf);
    buffer_delete(_buf);
    return _result;
}

function test_detect_magic()
{
    show_debug_message("--- test_detect_magic ---");

    if (__test_detect_bytes([0x1F, 0x8B, 0x08, 0x00]) != CompressionFormat.Gzip) { show_debug_message("[FAIL] detect gzip magic"); return false; }

    if (__test_detect_bytes([0x42, 0x5A, 0x68, 0x39]) != CompressionFormat.Bzip2) { show_debug_message("[FAIL] detect bzip2 magic"); return false; }

    if (__test_detect_bytes([0x50, 0x4B, 0x03, 0x04]) != CompressionFormat.Zip) { show_debug_message("[FAIL] detect zip magic"); return false; }

    if (__test_detect_bytes([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) != CompressionFormat.SevenZ) { show_debug_message("[FAIL] detect 7z magic"); return false; }

    if (__test_detect_bytes([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) != CompressionFormat.Rar) { show_debug_message("[FAIL] detect rar magic"); return false; }
    if (__test_detect_bytes([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) != CompressionFormat.Rar) { show_debug_message("[FAIL] detect rar5 magic"); return false; }

    if (__test_detect_bytes([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) != CompressionFormat.Xz) { show_debug_message("[FAIL] detect xz magic"); return false; }

    if (__test_detect_bytes([0x28, 0xB5, 0x2F, 0xFD]) != CompressionFormat.Zstd) { show_debug_message("[FAIL] detect zstd magic"); return false; }

    if (__test_detect_bytes([0x04, 0x22, 0x4D, 0x18]) != CompressionFormat.Lz4) { show_debug_message("[FAIL] detect lz4 magic"); return false; }

    if (__test_detect_text("hello world") != CompressionFormat.Raw) { show_debug_message("[FAIL] detect raw (random)"); return false; }

    show_debug_message("[OK] test_detect_magic");
    return true;
}

// =============================================================================
// TEST: ic_from_ext
// =============================================================================

function test_from_ext()
{
    show_debug_message("--- test_from_ext ---");

    if (ic_from_ext("archive.zip") != CompressionFormat.Zip) { show_debug_message("[FAIL] ext .zip"); return false; }
    if (ic_from_ext("data.7z") != CompressionFormat.SevenZ) { show_debug_message("[FAIL] ext .7z"); return false; }
    if (ic_from_ext("data.rar") != CompressionFormat.Rar) { show_debug_message("[FAIL] ext .rar"); return false; }
    if (ic_from_ext("file.gz") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .gz"); return false; }
    if (ic_from_ext("file.gzip") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .gzip"); return false; }
    if (ic_from_ext("file.tar.gz") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .tar.gz -> gzip"); return false; }
    if (ic_from_ext("file.tgz") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .tgz -> gzip"); return false; }
    if (ic_from_ext("data.bz2") != CompressionFormat.Bzip2) { show_debug_message("[FAIL] ext .bz2"); return false; }
    if (ic_from_ext("data.bzip2") != CompressionFormat.Bzip2) { show_debug_message("[FAIL] ext .bzip2"); return false; }
    if (ic_from_ext("data.tar.bz2") != CompressionFormat.Bzip2) { show_debug_message("[FAIL] ext .tar.bz2 -> bzip2"); return false; }
    if (ic_from_ext("data.tbz2") != CompressionFormat.Bzip2) { show_debug_message("[FAIL] ext .tbz2 -> bzip2"); return false; }
    if (ic_from_ext("data.zst") != CompressionFormat.Zstd) { show_debug_message("[FAIL] ext .zst"); return false; }
    if (ic_from_ext("data.zstd") != CompressionFormat.Zstd) { show_debug_message("[FAIL] ext .zstd"); return false; }
    if (ic_from_ext("data.tzst") != CompressionFormat.Zstd) { show_debug_message("[FAIL] ext .tzst -> zstd"); return false; }
    if (ic_from_ext("dump.lz4") != CompressionFormat.Lz4) { show_debug_message("[FAIL] ext .lz4"); return false; }
    if (ic_from_ext("dump.tlz4") != CompressionFormat.Lz4) { show_debug_message("[FAIL] ext .tlz4 -> lz4"); return false; }
    if (ic_from_ext("data.xz") != CompressionFormat.Xz) { show_debug_message("[FAIL] ext .xz"); return false; }
    if (ic_from_ext("data.txz") != CompressionFormat.Xz) { show_debug_message("[FAIL] ext .txz -> xz"); return false; }
    if (ic_from_ext("backup.tar") != CompressionFormat.Tar) { show_debug_message("[FAIL] ext .tar"); return false; }
    if (ic_from_ext("nofile") != CompressionFormat.Raw) { show_debug_message("[FAIL] ext none"); return false; }
    if (ic_from_ext("readme.txt") != CompressionFormat.Raw) { show_debug_message("[FAIL] ext .txt -> raw"); return false; }

    show_debug_message("[OK] test_from_ext");
    return true;
}

// =============================================================================
// TEST: ic_compress / ic_decompress string round-trip
// =============================================================================

function test_stream_compress_decompress()
{
    show_debug_message("--- test_stream_compress_decompress ---");

    var _original = "Hello, GameMaker! This is a test string for compression. "
                  + "It contains enough data to actually compress a little bit. "
                  + "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    var _formats = [CompressionFormat.Gzip, CompressionFormat.Bzip2, CompressionFormat.Zstd, CompressionFormat.Lz4, CompressionFormat.Xz];

    for (var _i = 0; _i < array_length(_formats); _i++)
    {
        var _fmt = _formats[_i];
        var _name = ic_to_str(_fmt);

        var _compressed = ic_compress(_original, _fmt, CompressionLevel.Default);
        if (_compressed == "") { show_debug_message($"[FAIL] compress {_name} returned empty"); return false; }

        var _decompressed = ic_decompress(_compressed, _fmt);
        if (_decompressed != _original) { show_debug_message($"[FAIL] round-trip {_name} mismatch"); return false; }

        show_debug_message($"  [{_name}] OK (orig={string_length(_original)}, comp={string_length(_compressed)})");
    }

    var _comp_raw = ic_compress(_original, CompressionFormat.Raw, CompressionLevel.Default);
    if (_comp_raw == "") { show_debug_message("[FAIL] raw compress empty"); return false; }

    show_debug_message("[OK] test_stream_compress_decompress");
    return true;
}

// =============================================================================
// TEST: ic_compress_file / ic_decompress_file round-trip
// =============================================================================

function test_file_compress_decompress()
{
    show_debug_message("--- test_file_compress_decompress ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);

    var _original_path = _dir + "/original.txt";
    var _compressed_path = _dir + "/compressed.zst";
    var _decompressed_path = _dir + "/restored.txt";

    var _data = "File-based round-trip test. Lorem ipsum dolor sit amet, "
              + "consectetur adipiscing elit. REPEAT_REPEAT_REPEAT_REPEAT_";
    var _f = file_text_open_write(_original_path);
    file_text_write_string(_f, _data);
    file_text_close(_f);

    if (!ic_compress_file(_original_path, _compressed_path, CompressionFormat.Zstd, CompressionLevel.Default))
        { show_debug_message("[FAIL] compress_file zstd"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_compressed_path))
        { show_debug_message("[FAIL] compressed file exists"); __test_cleanup_dir(_dir); return false; }
    if (!ic_decompress_file(_compressed_path, _decompressed_path, CompressionFormat.Zstd))
        { show_debug_message("[FAIL] decompress_file zstd"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_decompressed_path))
        { show_debug_message("[FAIL] decompressed file exists"); __test_cleanup_dir(_dir); return false; }

    var _f2 = file_text_open_read(_decompressed_path);
    var _restored = file_text_read_string(_f2);
    file_text_close(_f2);
    if (_restored != _data)
        { show_debug_message("[FAIL] file round-trip content match"); __test_cleanup_dir(_dir); return false; }

    file_delete(_original_path);
    file_delete(_compressed_path);
    file_delete(_decompressed_path);
    directory_destroy(_dir);

    show_debug_message("[OK] test_file_compress_decompress");
    return true;
}

// =============================================================================
// TEST: ic_compress_buf / ic_decompress_buf round-trip
// =============================================================================

function test_buffer_compress_decompress()
{
    show_debug_message("--- test_buffer_compress_decompress ---");

    var _data = "Buffer-based round-trip. Testing compress_buf/decompress_buf. "
              + "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";

    var _expected_size = string_byte_length(_data);
    var _in_buf = buffer_create(_expected_size, buffer_fixed, 1);
    buffer_write(_in_buf, buffer_text, _data);

    var _out_buf = buffer_create(65536, buffer_fixed, 1);

    var _result = ic_compress_buf(_in_buf, _out_buf, CompressionFormat.Gzip, CompressionLevel.Default);
    if (_result == undefined) { show_debug_message("[FAIL] compress_buf returned undefined"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (!_result.success) { show_debug_message("[FAIL] compress_buf success"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.original_size != _expected_size) { show_debug_message("[FAIL] compress_buf original_size"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.compressed_size <= 0) { show_debug_message("[FAIL] compress_buf compressed_size > 0"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.format != CompressionFormat.Gzip) { show_debug_message("[FAIL] compress_buf format"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }

    var _compressed_buf = buffer_create(_result.compressed_size, buffer_fixed, 1);
    for (var _byte = 0; _byte < _result.compressed_size; _byte++)
    {
        buffer_poke(_compressed_buf, _byte, buffer_u8, buffer_peek(_out_buf, _byte, buffer_u8));
    }

    var _decomp_buf = buffer_create(_expected_size, buffer_fixed, 1);
    var _dec_result = ic_decompress_buf(_compressed_buf, _decomp_buf, CompressionFormat.Gzip);
    if (_dec_result == undefined) { show_debug_message("[FAIL] decompress_buf returned undefined"); buffer_delete(_in_buf); buffer_delete(_out_buf); buffer_delete(_compressed_buf); buffer_delete(_decomp_buf); return false; }
    if (!_dec_result.success) { show_debug_message("[FAIL] decompress_buf success"); buffer_delete(_in_buf); buffer_delete(_out_buf); buffer_delete(_compressed_buf); buffer_delete(_decomp_buf); return false; }

    for (var _byte = 0; _byte < _expected_size; _byte++)
    {
        if (buffer_peek(_decomp_buf, _byte, buffer_u8) != buffer_peek(_in_buf, _byte, buffer_u8))
        {
            show_debug_message($"[FAIL] buffer round-trip content match at byte {_byte}");
            buffer_delete(_in_buf);
            buffer_delete(_out_buf);
            buffer_delete(_compressed_buf);
            buffer_delete(_decomp_buf);
            return false;
        }
    }

    buffer_delete(_in_buf);
    buffer_delete(_out_buf);
    buffer_delete(_compressed_buf);
    buffer_delete(_decomp_buf);

    show_debug_message("[OK] test_buffer_compress_decompress");
    return true;
}

// =============================================================================
// TEST: Binary buffer APIs, offsets, lengths, and required capacity
// =============================================================================

function test_binary_buffer_apis()
{
    show_debug_message("--- test_binary_buffer_apis ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/binary.zip";
    var _source = buffer_create(12, buffer_fixed, 1);
    var _expected = [0, 1, 2, 0, 254, 255, 65, 0];
    for (var _i = 0; _i < array_length(_expected); _i++) {
        buffer_poke(_source, _i + 2, buffer_u8, _expected[_i]);
    }

    var _compressed = buffer_create(256, buffer_fixed, 1);
    var _compress_result = ic_compress_buf_range(_source, 2, array_length(_expected), _compressed, 5, CompressionFormat.Gzip, CompressionLevel.Default);
    if (!_compress_result.success || _compress_result.bytes_written <= 0) {
        show_debug_message($"[FAIL] compress_buf_range: {_compress_result.error_message}");
        buffer_delete(_source);
        buffer_delete(_compressed);
        __test_cleanup_dir(_dir);
        return false;
    }

    var _roundtrip = buffer_create(16, buffer_fixed, 1);
    var _decompress_result = ic_decompress_buf_range(_compressed, 5, _compress_result.bytes_written, _roundtrip, 4, CompressionFormat.Gzip);
    if (!_decompress_result.success || _decompress_result.bytes_written != array_length(_expected)) {
        show_debug_message($"[FAIL] decompress_buf_range: {_decompress_result.error_message}");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        __test_cleanup_dir(_dir);
        return false;
    }
    for (var _i = 0; _i < array_length(_expected); _i++) {
        if (buffer_peek(_roundtrip, _i + 4, buffer_u8) != _expected[_i]) {
            show_debug_message($"[FAIL] ranged buffer mismatch at {_i}");
            buffer_delete(_source);
            buffer_delete(_compressed);
            buffer_delete(_roundtrip);
            __test_cleanup_dir(_dir);
            return false;
        }
    }

    var _empty_source = buffer_create(0, buffer_fixed, 1);
    var _empty_compressed = buffer_create(128, buffer_fixed, 1);
    var _empty_output = buffer_create(0, buffer_fixed, 1);
    var _empty_compress_result = ic_compress_buf_range(_empty_source, 0, 0, _empty_compressed, 0, CompressionFormat.Gzip, CompressionLevel.Default);
    var _empty_decompress_result = ic_decompress_buf_range(_empty_compressed, 0, _empty_compress_result.bytes_written, _empty_output, 0, CompressionFormat.Gzip);
    if (!_empty_compress_result.success || !_empty_decompress_result.success || _empty_decompress_result.bytes_written != 0) {
        show_debug_message($"[FAIL] empty ranged buffer round-trip: compress={_empty_compress_result.success}/{_empty_compress_result.bytes_written}/{_empty_compress_result.error_message}, decompress={_empty_decompress_result.success}/{_empty_decompress_result.bytes_written}/{_empty_decompress_result.error_message}");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        buffer_delete(_empty_source);
        buffer_delete(_empty_compressed);
        buffer_delete(_empty_output);
        __test_cleanup_dir(_dir);
        return false;
    }
    buffer_delete(_empty_source);
    buffer_delete(_empty_compressed);
    buffer_delete(_empty_output);

    var _handle = ic_create(_archive_path, CompressionFormat.Zip);
    if (_handle < 0 || !ic_add_buf(_handle, "binary.dat", _source, 2, array_length(_expected)) || !ic_close(_handle)) {
        show_debug_message("[FAIL] add_buf with range");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        __test_cleanup_dir(_dir);
        return false;
    }

    var _small = buffer_create(4, buffer_fixed, 1);
    var _small_result = ic_extract_buf(_archive_path, "binary.dat", _small, 0);
    if (_small_result.success || _small_result.bytes_required != array_length(_expected)) {
        show_debug_message("[FAIL] extract_buf required capacity");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        buffer_delete(_small);
        __test_cleanup_dir(_dir);
        return false;
    }

    var _output = buffer_create(12, buffer_fixed, 1);
    var _extract_result = ic_extract_buf(_archive_path, "binary.dat", _output, 3);
    if (!_extract_result.success || _extract_result.bytes_written != array_length(_expected)) {
        show_debug_message($"[FAIL] extract_buf: {_extract_result.error_message}");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        buffer_delete(_small);
        buffer_delete(_output);
        __test_cleanup_dir(_dir);
        return false;
    }
    for (var _i = 0; _i < array_length(_expected); _i++) {
        if (buffer_peek(_output, _i + 3, buffer_u8) != _expected[_i]) {
            show_debug_message($"[FAIL] binary buffer mismatch at {_i}");
            buffer_delete(_source);
            buffer_delete(_compressed);
            buffer_delete(_roundtrip);
            buffer_delete(_small);
            buffer_delete(_output);
            __test_cleanup_dir(_dir);
            return false;
        }
    }

    if (ic_add_buf(-1, "bad", _source, 0, 1)) {
        show_debug_message("[FAIL] add_buf accepted invalid handle with valid range");
        buffer_delete(_source);
        buffer_delete(_compressed);
        buffer_delete(_roundtrip);
        buffer_delete(_small);
        buffer_delete(_output);
        __test_cleanup_dir(_dir);
        return false;
    }

    buffer_delete(_source);
    buffer_delete(_compressed);
    buffer_delete(_roundtrip);
    buffer_delete(_small);
    buffer_delete(_output);
    file_delete(_archive_path);
    directory_destroy(_dir);
    show_debug_message("[OK] test_binary_buffer_apis");
    return true;
}

// =============================================================================
// TEST: ic_create -> ic_add_data -> ic_close -> ic_list -> ic_extract_mem
// =============================================================================

function test_archive_create_list_extract()
{
    show_debug_message("--- test_archive_create_list_extract ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/test_archive.zip";

    var _handle = ic_create(_archive_path, CompressionFormat.Zip);
    if (_handle < 0) { show_debug_message("[FAIL] ic_create returned valid handle"); __test_cleanup_dir(_dir); return false; }

    if (!ic_add_data(_handle, "hello.txt", "Hello World")) { show_debug_message("[FAIL] ic_add_data hello.txt"); __test_cleanup_dir(_dir); return false; }
    if (!ic_add_data(_handle, "folder/data.json", "{ \"key\": 42 }")) { show_debug_message("[FAIL] ic_add_data folder/data.json"); __test_cleanup_dir(_dir); return false; }
    if (!ic_add_data(_handle, "empty.txt", "")) { show_debug_message("[FAIL] ic_add_data empty.txt"); __test_cleanup_dir(_dir); return false; }

    if (!ic_close(_handle)) { show_debug_message("[FAIL] ic_close"); __test_cleanup_dir(_dir); return false; }

    if (!file_exists(_archive_path)) { show_debug_message("[FAIL] archive file exists"); __test_cleanup_dir(_dir); return false; }

    var _entries = ic_list(_archive_path);
    if (!is_array(_entries)) { show_debug_message("[FAIL] ic_list returned array"); __test_cleanup_dir(_dir); return false; }
    if (array_length(_entries) != 3) { show_debug_message($"[FAIL] ic_list expected 3 entries, got {array_length(_entries)}"); __test_cleanup_dir(_dir); return false; }

    for (var _i = 0; _i < array_length(_entries); _i++)
    {
        var _e = _entries[_i];
        show_debug_message($"  [{_i}] {_e.filename} (dir={_e.is_directory})");
    }

    if (ic_extract_mem(_archive_path, "hello.txt") != "Hello World") { show_debug_message("[FAIL] ic_extract_mem hello.txt match"); __test_cleanup_dir(_dir); return false; }
    if (ic_extract_mem(_archive_path, "folder/data.json") != "{ \"key\": 42 }") { show_debug_message("[FAIL] ic_extract_mem folder/data.json match"); __test_cleanup_dir(_dir); return false; }
    if (ic_extract_mem(_archive_path, "empty.txt") != "") { show_debug_message("[FAIL] ic_extract_mem empty file"); __test_cleanup_dir(_dir); return false; }

    file_delete(_archive_path);
    directory_destroy(_dir);

    show_debug_message("[OK] test_archive_create_list_extract");
    return true;
}

// =============================================================================
// TEST: ic_extract (full extraction to disk)
// =============================================================================

function test_extract_all()
{
    show_debug_message("--- test_extract_all ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/extract_test.zip";
    var _extract_dir = _dir + "/extracted";

    var _handle = ic_create(_archive_path, CompressionFormat.Zip);
    if (_handle < 0) { show_debug_message("[FAIL] create archive for extract test"); __test_cleanup_dir(_dir); return false; }
    ic_add_data(_handle, "a.txt", "AAA");
    ic_add_data(_handle, "sub/b.txt", "BBB");
    ic_add_data(_handle, "sub/c.txt", "CCC");
    ic_close(_handle);

    directory_create(_extract_dir);
    var _result = ic_extract(_archive_path, _extract_dir);
    if (_result == undefined) { show_debug_message("[FAIL] extract returned"); __test_cleanup_dir(_dir); return false; }
    if (!_result.success) { show_debug_message($"[FAIL] extract success: {_result.error_message}"); __test_cleanup_dir(_dir); return false; }
    if (_result.files_extracted != 3) { show_debug_message($"[FAIL] files_extracted=3, got {_result.files_extracted}"); __test_cleanup_dir(_dir); return false; }

    if (!file_exists(_extract_dir + "/a.txt")) { show_debug_message("[FAIL] extracted a.txt exists"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_extract_dir + "/sub/b.txt")) { show_debug_message("[FAIL] extracted sub/b.txt exists"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_extract_dir + "/sub/c.txt")) { show_debug_message("[FAIL] extracted sub/c.txt exists"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_extract_all");
    return true;
}

// =============================================================================
// TEST: ic_extract_file (single file to disk)
// =============================================================================

function test_extract_single_file()
{
    show_debug_message("--- test_extract_single_file ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/single_test.zip";
    var _output_path = _dir + "/rescued.txt";

    var _handle = ic_create(_archive_path, CompressionFormat.Zip);
    ic_add_data(_handle, "target.txt", "Target file content here!");
    ic_add_data(_handle, "other.txt", "Other file");
    ic_close(_handle);

    if (!ic_extract_file(_archive_path, "target.txt", _output_path)) { show_debug_message("[FAIL] extract_file"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_output_path)) { show_debug_message("[FAIL] output file exists"); __test_cleanup_dir(_dir); return false; }

    var _f = file_text_open_read(_output_path);
    var _read = file_text_read_string(_f);
    file_text_close(_f);
    if (_read != "Target file content here!") { show_debug_message("[FAIL] extracted content matches"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_extract_single_file");
    return true;
}

// =============================================================================
// TEST: ic_add_file (real file from disk)
// =============================================================================

function test_add_file_from_disk()
{
    show_debug_message("--- test_add_file_from_disk ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);

    var _src_path = _dir + "/source.dat";
    var _archive_path = _dir + "/archive.zip";

    var _data = "File content from disk with enough text to round-trip through ic_extract_mem.";
    var _buf = buffer_create(string_byte_length(_data), buffer_fixed, 1);
    buffer_write(_buf, buffer_text, _data);
    buffer_save(_buf, _src_path);
    buffer_delete(_buf);

    var _handle = ic_create(_archive_path, CompressionFormat.Zip);
    if (_handle < 0) { show_debug_message("[FAIL] create archive"); __test_cleanup_dir(_dir); return false; }

    if (!ic_add_file(_handle, _src_path, "disk_file.bin")) { show_debug_message("[FAIL] ic_add_file from disk"); __test_cleanup_dir(_dir); return false; }
    ic_close(_handle);

    if (ic_extract_mem(_archive_path, "disk_file.bin") != _data) { show_debug_message("[FAIL] round-trip add_file content match"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_add_file_from_disk");
    return true;
}

// =============================================================================
// TEST: Tar archive
// =============================================================================

function test_tar_archive()
{
    show_debug_message("--- test_tar_archive ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/test.tar";

    var _handle = ic_create(_archive_path, CompressionFormat.Tar);
    if (_handle < 0) { show_debug_message("[FAIL] create tar archive"); __test_cleanup_dir(_dir); return false; }

    ic_add_data(_handle, "readme.txt", "Tar test file");
    ic_add_data(_handle, "config.ini", "[section]" + chr(10) + "key=value");
    ic_close(_handle);

    if (!file_exists(_archive_path)) { show_debug_message("[FAIL] tar file exists"); __test_cleanup_dir(_dir); return false; }

    var _entries = ic_list(_archive_path);
    if (!is_array(_entries)) { show_debug_message("[FAIL] tar list is array"); __test_cleanup_dir(_dir); return false; }
    if (array_length(_entries) != 2) { show_debug_message($"[FAIL] tar has 2 entries, got {array_length(_entries)}"); __test_cleanup_dir(_dir); return false; }

    if (ic_extract_mem(_archive_path, "readme.txt") != "Tar test file") { show_debug_message("[FAIL] tar extract_mem match"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_tar_archive");
    return true;
}

// =============================================================================
// TEST: Compression levels
// =============================================================================

function test_compression_levels()
{
    show_debug_message("--- test_compression_levels ---");

    var _data = "";
    repeat (100) { _data += "The quick brown fox jumps over the lazy dog. "; }

    var _fast = ic_compress(_data, CompressionFormat.Gzip, CompressionLevel.Fastest);
    var _optimal = ic_compress(_data, CompressionFormat.Gzip, CompressionLevel.Optimal);

    if (_fast == "") { show_debug_message("[FAIL] fastest compressed"); return false; }
    if (_optimal == "") { show_debug_message("[FAIL] optimal compressed"); return false; }

    if (ic_decompress(_fast, CompressionFormat.Gzip) != _data) { show_debug_message("[FAIL] fastest round-trip"); return false; }
    if (ic_decompress(_optimal, CompressionFormat.Gzip) != _data) { show_debug_message("[FAIL] optimal round-trip"); return false; }

    show_debug_message($"  fastest={string_length(_fast)}B  optimal={string_length(_optimal)}B");

    show_debug_message("[OK] test_compression_levels");
    return true;
}

// =============================================================================
// TEST: Edge cases
// =============================================================================

function test_edge_cases()
{
    show_debug_message("--- test_edge_cases ---");

    var _comp_empty = ic_compress("", CompressionFormat.Gzip, CompressionLevel.Default);
    if (_comp_empty == undefined || _comp_empty == "") { show_debug_message("[FAIL] compress empty string"); return false; }
    if (ic_decompress(_comp_empty, CompressionFormat.Gzip) != "") { show_debug_message("[FAIL] decompress empty round-trip"); return false; }

    if (ic_compress("X", CompressionFormat.Gzip, CompressionLevel.Default) == "") { show_debug_message("[FAIL] compress single byte"); return false; }
    if (ic_decompress(ic_compress("X", CompressionFormat.Gzip, CompressionLevel.Default), CompressionFormat.Gzip) != "X") { show_debug_message("[FAIL] round-trip single byte"); return false; }

    var _big = "";
    repeat (1000) { _big += "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; }
    var _comp_big = ic_compress(_big, CompressionFormat.Zstd, CompressionLevel.Default);
    if (_comp_big == "") { show_debug_message("[FAIL] compress large data"); return false; }
    if (string_length(_comp_big) >= string_length(_big)) { show_debug_message("[FAIL] large data actually compressed"); return false; }
    if (ic_decompress(_comp_big, CompressionFormat.Zstd) != _big) { show_debug_message("[FAIL] large data round-trip"); return false; }

    var _utf8_text = "中文 / café / 🙂 / GameMaker";
    var _comp_utf8 = ic_compress(_utf8_text, CompressionFormat.Gzip, CompressionLevel.Default);
    if (_comp_utf8 == "") { show_debug_message("[FAIL] UTF-8 text compressed"); return false; }
    var _dec_utf8 = ic_decompress(_comp_utf8, CompressionFormat.Gzip);
    if (string_byte_length(_dec_utf8) != string_byte_length(_utf8_text)) { show_debug_message("[FAIL] UTF-8 byte length match"); return false; }
    if (_dec_utf8 != _utf8_text) { show_debug_message("[FAIL] UTF-8 text round-trip"); return false; }

    show_debug_message("[OK] test_edge_cases");
    return true;
}

// =============================================================================
// TEST: Multiple archive handles
// =============================================================================

function test_multiple_handles()
{
    show_debug_message("--- test_multiple_handles ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);

    var _path1 = _dir + "/archive1.zip";
    var _path2 = _dir + "/archive2.zip";

    var _h1 = ic_create(_path1, CompressionFormat.Zip);
    var _h2 = ic_create(_path2, CompressionFormat.Zip);
    if (_h1 < 0 || _h2 < 0) { show_debug_message("[FAIL] two handles created"); __test_cleanup_dir(_dir); return false; }
    if (_h1 == _h2) { show_debug_message("[FAIL] handles are distinct"); __test_cleanup_dir(_dir); return false; }

    if (!ic_add_data(_h1, "one.txt", "First archive")) { show_debug_message("[FAIL] add to archive 1"); __test_cleanup_dir(_dir); return false; }
    if (!ic_add_data(_h2, "two.txt", "Second archive")) { show_debug_message("[FAIL] add to archive 2"); __test_cleanup_dir(_dir); return false; }

    if (!ic_close(_h1)) { show_debug_message("[FAIL] close archive 1"); __test_cleanup_dir(_dir); return false; }
    if (!ic_close(_h2)) { show_debug_message("[FAIL] close archive 2"); __test_cleanup_dir(_dir); return false; }

    if (ic_extract_mem(_path1, "one.txt") != "First archive") { show_debug_message("[FAIL] archive 1 content"); __test_cleanup_dir(_dir); return false; }
    if (ic_extract_mem(_path2, "two.txt") != "Second archive") { show_debug_message("[FAIL] archive 2 content"); __test_cleanup_dir(_dir); return false; }

    if (ic_close(_h1)) { show_debug_message("[FAIL] double close returns false"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_multiple_handles");
    return true;
}

// =============================================================================
// TEST: ic_detect_file
// =============================================================================

function test_detect_file()
{
    show_debug_message("--- test_detect_file ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);

    var _src_path = _dir + "/detect_source.txt";
    var _gzip_path = _dir + "/test.gz";
    var _f = file_text_open_write(_src_path);
    file_text_write_string(_f, "detect me");
    file_text_close(_f);

    if (!ic_compress_file(_src_path, _gzip_path, CompressionFormat.Gzip, CompressionLevel.Default))
        { show_debug_message("[FAIL] create gzip for detect_file"); __test_cleanup_dir(_dir); return false; }

    if (ic_detect_file(_gzip_path) != CompressionFormat.Gzip) { show_debug_message("[FAIL] detect_file gzip"); __test_cleanup_dir(_dir); return false; }
    if (ic_detect_file("nonexistent_file.xyz") != CompressionFormat.Raw) { show_debug_message("[FAIL] detect_file nonexistent"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_detect_file");
    return true;
}

// =============================================================================
// TEST: SevenZ archive
// =============================================================================

function test_7z_archive()
{
    show_debug_message("--- test_7z_archive ---");

    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _archive_path = _dir + "/test.7z";

    var _handle = ic_create(_archive_path, CompressionFormat.SevenZ);
    if (_handle < 0) { show_debug_message("[FAIL] create 7z archive"); __test_cleanup_dir(_dir); return false; }

    ic_add_data(_handle, "document.txt", "7zip test content here...");
    ic_close(_handle);

    if (!file_exists(_archive_path)) { show_debug_message("[FAIL] 7z file exists"); __test_cleanup_dir(_dir); return false; }

    if (ic_extract_mem(_archive_path, "document.txt") != "7zip test content here...") { show_debug_message("[FAIL] 7z extract match"); __test_cleanup_dir(_dir); return false; }

    directory_destroy(_dir);

    show_debug_message("[OK] test_7z_archive");
    return true;
}

// =============================================================================
// TEST: Error handling / invalid inputs
// =============================================================================

function test_error_handling()
{
    show_debug_message("--- test_error_handling ---");

    if (ic_compress_file("__nonexistent__", "out.zst", CompressionFormat.Zstd, CompressionLevel.Default))
        { show_debug_message("[FAIL] compress_file fails on nonexistent source"); return false; }
    if (ic_decompress_file("__nonexistent__", "out.txt", CompressionFormat.Zstd))
        { show_debug_message("[FAIL] decompress_file fails on nonexistent source"); return false; }

    if (ic_add_file(-1, "path", "entry")) { show_debug_message("[FAIL] add_file with invalid handle"); return false; }
    if (ic_add_data(-1, "entry", "data")) { show_debug_message("[FAIL] add_data with invalid handle"); return false; }
    if (ic_close(-1)) { show_debug_message("[FAIL] close with invalid handle"); return false; }
    if (ic_close(99999)) { show_debug_message("[FAIL] close with non-existent handle"); return false; }

    var _entries = ic_list("__nonexistent__.zip");
    if (!is_array(_entries)) { show_debug_message("[FAIL] list nonexistent returns array"); return false; }
    if (array_length(_entries) != 0) { show_debug_message("[FAIL] list nonexistent is empty"); return false; }

    show_debug_message("[OK] test_error_handling");
    return true;
}

// Stream APIs must preserve arbitrary payload bytes without unpacking an inner archive.
function test_binary_stream_roundtrips()
{
    return __test_with_resources("test_binary_stream_roundtrips", function(_context) {
        var _handle = __test_writer(_context, "inner.zip", CompressionFormat.Zip);
        __test_assert(ic_add_data(_handle, "inside.txt", "INNER-ZIP-CONTENT"), "create nested ZIP payload");
        __test_close_writer(_context, _handle);
        var _zip = __test_load_buffer(_context, _context.directory + "/inner.zip");
        var _zeros = __test_buffer(_context, 1024);
        buffer_fill(_zeros, 0, buffer_u8, 0, 1024);
        var _empty = __test_buffer(_context, 1);
        var _inputs = [_zeros, _zip, _empty];
        var _lengths = [1024, buffer_get_size(_zip), 0];
        var _names = ["zero bytes", "ZIP bytes", "empty"];
        var _formats = [CompressionFormat.Gzip, CompressionFormat.Bzip2, CompressionFormat.Zstd, CompressionFormat.Lz4, CompressionFormat.Xz, CompressionFormat.Raw];
        var _capacity = buffer_get_size(_zip) + 16384;
        var _compressed = __test_buffer(_context, _capacity);
        var _restored = __test_buffer(_context, _capacity);
        var _nested = __test_buffer(_context, _capacity);

        for (var _format_index = 0; _format_index < array_length(_formats); ++_format_index) {
            var _format = _formats[_format_index];
            for (var _input_index = 0; _input_index < array_length(_inputs); ++_input_index) {
                var _input = _inputs[_input_index];
                var _length = _lengths[_input_index];
                var _label = ic_to_str(_format) + " / " + _names[_input_index];
                buffer_fill(_compressed, 0, buffer_u8, 165, _capacity);
                buffer_fill(_restored, 0, buffer_u8, 165, _capacity);
                var _compressed_result = ic_compress_buf_range(_input, 0, _length, _compressed, 0, _format, CompressionLevel.Default);
                __test_assert(_compressed_result.success, _label + " compress: " + _compressed_result.error_message);
                __test_assert(_compressed_result.bytes_required == _compressed_result.bytes_written, _label + " compressed capacity");
                if (_format == CompressionFormat.Raw) {
                    __test_assert(_compressed_result.bytes_written == _length, _label + " raw size identity");
                    __test_assert(__test_equal_bytes(_input, 0, _compressed, 0, _length), _label + " raw byte identity");
                }
                else __test_assert(_compressed_result.bytes_written > 0, _label + " must contain a stream frame");
                var _restored_result = ic_decompress_buf_range(_compressed, 0, _compressed_result.bytes_written, _restored, 0, _format);
                __test_assert(_restored_result.success, _label + " decompress: " + _restored_result.error_message);
                __test_assert(_restored_result.bytes_written == _length, _label + " expected " + string(_length) + " bytes, got " + string(_restored_result.bytes_written));
                __test_assert(_restored_result.bytes_required == _length, _label + " restored capacity");
                __test_assert(__test_equal_bytes(_input, 0, _restored, 0, _length), _label + " restored byte identity");
                __test_assert(buffer_peek(_restored, _length, buffer_u8) == 165, _label + " wrote beyond payload");
            }
            if (_format != CompressionFormat.Raw) {
                var _label = ic_to_str(_format) + " / same-filter nested frame";
                var _inner_result = ic_compress_buf_range(_zeros, 0, 1024, _compressed, 0, _format, CompressionLevel.Default);
                __test_assert(_inner_result.success && _inner_result.bytes_written > 0, _label + " inner compression");
                var _outer_result = ic_compress_buf_range(_compressed, 0, _inner_result.bytes_written, _nested, 0, _format, CompressionLevel.Default);
                __test_assert(_outer_result.success && _outer_result.bytes_written > 0, _label + " outer compression");
                var _restored_result = ic_decompress_buf_range(_nested, 0, _outer_result.bytes_written, _restored, 0, _format);
                __test_assert(_restored_result.success, _label + ": " + _restored_result.error_message);
                __test_assert(_restored_result.bytes_written == _inner_result.bytes_written, _label + " removes only outer frame");
                __test_assert(__test_equal_bytes(_compressed, 0, _restored, 0, _inner_result.bytes_written), _label + " preserves inner bytes");
            }
            if (_format == CompressionFormat.Lz4) {
                // Both paths used to reach libarchive's LZ4 close callback before checksum initialization.
                for (var _empty_case = 0; _empty_case < 2; ++_empty_case) {
                    var _filename = "empty_handle_" + string(_empty_case) + ".lz4";
                    var _empty_handle = __test_writer(_context, _filename, CompressionFormat.Lz4);
                    if (_empty_case == 1) __test_assert(ic_add_data(_empty_handle, "empty", ""), "LZ4 empty entry add");
                    __test_close_writer(_context, _empty_handle);
                    var _empty_frame = __test_load_buffer(_context, _context.directory + "/" + _filename);
                    var _frame_length = buffer_get_size(_empty_frame);
                    __test_assert(_frame_length > 0 && ic_detect(_empty_frame) == CompressionFormat.Lz4, "LZ4 handle produces a frame");
                    var _empty_result = ic_decompress_buf_range(_empty_frame, 0, _frame_length, _restored, 0, CompressionFormat.Lz4);
                    __test_assert(_empty_result.success && _empty_result.bytes_written == 0 && _empty_result.bytes_required == 0,
                        "LZ4 empty handle case " + string(_empty_case) + ": " + _empty_result.error_message);
                }
            }
            show_debug_message("  [OK] " + ic_to_str(_format) + " binary subcase matrix");
        }
    });
}

function test_archive_buffer_roundtrips()
{
    return __test_with_resources("test_archive_buffer_roundtrips", function(_context) {
        var _input = __test_buffer(_context, 256);
        for (var _index = 0; _index < 256; ++_index) buffer_poke(_input, _index, buffer_u8, _index);
        var _compressed = __test_buffer(_context, 32768);
        var _output = __test_buffer(_context, 512);
        var _formats = [CompressionFormat.Zip, CompressionFormat.SevenZ, CompressionFormat.Tar];
        var _lengths = [256, 0];
        for (var _format_index = 0; _format_index < array_length(_formats); ++_format_index) {
            var _format = _formats[_format_index];
            for (var _length_index = 0; _length_index < array_length(_lengths); ++_length_index) {
                var _length = _lengths[_length_index];
                var _label = ic_to_str(_format) + " archive buffer / " + string(_length) + " bytes";
                buffer_fill(_output, 0, buffer_u8, 165, 512);
                var _encoded = ic_compress_buf_range(_input, 0, _length, _compressed, 0, _format, CompressionLevel.Default);
                __test_assert(_encoded.success && _encoded.bytes_written > 0, _label + " compress: " + _encoded.error_message);
                __test_assert(_encoded.bytes_required == _encoded.bytes_written, _label + " compressed capacity");
                var _decoded = ic_decompress_buf_range(_compressed, 0, _encoded.bytes_written, _output, 0, _format);
                __test_assert(_decoded.success, _label + " decompress: " + _decoded.error_message);
                __test_assert(_decoded.bytes_written == _length && _decoded.bytes_required == _length, _label + " decoded length");
                __test_assert(__test_equal_bytes(_input, 0, _output, 0, _length), _label + " byte identity");
                __test_assert(buffer_peek(_output, _length, buffer_u8) == 165, _label + " wrote beyond payload");
            }
        }
    });
}
function test_stream_validation()
{
    return __test_with_resources("test_stream_validation", function(_context) {
        var _text = "plain uncompressed payload";
        var _length = string_byte_length(_text);
        var _input = __test_buffer(_context, _length);
        buffer_write(_input, buffer_text, _text);
        var _compressed = __test_buffer(_context, 8192);
        var _output = __test_buffer(_context, 8192);
        var _gzip = ic_compress_buf_range(_input, 0, _length, _compressed, 0, CompressionFormat.Gzip, CompressionLevel.Default);
        __test_assert(_gzip.success && _gzip.bytes_written > 0, "valid gzip setup");
        var _wrong = ic_decompress_buf_range(_compressed, 0, _gzip.bytes_written, _output, 0, CompressionFormat.Zstd);
        __test_assert(!_wrong.success && _wrong.bytes_written == 0 && _wrong.error_message != "", "reject gzip supplied as Zstd");
        var _plain = ic_decompress_buf_range(_input, 0, _length, _output, 0, CompressionFormat.Gzip);
        __test_assert(!_plain.success && _plain.bytes_written == 0 && _plain.error_message != "", "reject uncompressed input supplied as gzip");
        var _empty = ic_decompress_buf_range(_input, 0, 0, _output, 0, CompressionFormat.Gzip);
        __test_assert(!_empty.success && _empty.bytes_written == 0 && _empty.error_message != "", "reject absent gzip frame");
        __test_assert(_gzip.bytes_written > 8, "gzip fixture contains header and trailer");
        var _header = ic_decompress_buf_range(_compressed, 0, 2, _output, 0, CompressionFormat.Gzip);
        __test_assert(!_header.success && _header.bytes_written == 0 && _header.error_message != "", "reject truncated gzip header");
        var _trailer = ic_decompress_buf_range(_compressed, 0, _gzip.bytes_written - 1, _output, 0, CompressionFormat.Gzip);
        __test_assert(!_trailer.success && _trailer.bytes_written == 0 && _trailer.error_message != "", "reject truncated gzip trailer");
        buffer_poke(_compressed, _gzip.bytes_written, buffer_u8, 65);
        var _garbage = ic_decompress_buf_range(_compressed, 0, _gzip.bytes_written + 1, _output, 0, CompressionFormat.Gzip);
        __test_assert(!_garbage.success && _garbage.bytes_written == 0 && _garbage.error_message != "", "reject valid gzip followed by garbage");
        var _rar = ic_compress_buf_range(_input, 0, 0, _output, 0, CompressionFormat.Rar, CompressionLevel.Default);
        __test_assert(!_rar.success && _rar.bytes_written == 0 && _rar.error_message != "", "reject unsupported RAR even with empty input");

        var _empty_path = _context.directory + "/empty_input.bin";
        var _existing_path = _context.directory + "/existing_output.bin";
        array_push(_context.files, _empty_path);
        array_push(_context.files, _existing_path);
        buffer_save_ext(_input, _empty_path, 0, 0);
        __test_assert(file_exists(_empty_path), "empty file fixture exists");
        var _source_check = file_bin_open(_empty_path, 0);
        __test_assert(_source_check >= 0, "empty file fixture opens");
        var _source_size = file_bin_size(_source_check);
        file_bin_close(_source_check);
        __test_assert(_source_size == 0, "empty file fixture has zero bytes");
        buffer_save(_input, _existing_path);
        __test_assert(file_exists(_existing_path), "existing output fixture exists");
        __test_assert(!ic_compress_file(_empty_path, _existing_path, CompressionFormat.Rar, CompressionLevel.Default), "empty file RAR compression fails");
        var _preserved = __test_load_buffer(_context, _existing_path);
        __test_assert(buffer_get_size(_preserved) == _length && __test_equal_bytes(_input, 0, _preserved, 0, _length), "failed RAR compression preserves existing output");
    });
}

function test_buffer_invalid_ranges()
{
    return __test_with_resources("test_buffer_invalid_ranges", function(_context) {
        var _input = __test_buffer(_context, 8);
        buffer_fill(_input, 0, buffer_u8, 42, 8);
        var _output = __test_buffer(_context, 128);
        var _handle = __test_writer(_context, "range.zip", CompressionFormat.Zip);
        __test_assert(!ic_add_buf(_handle, "negative_offset", _input, -1, 1), "valid handle rejects negative offset");
        __test_assert(!ic_add_buf(_handle, "negative_length", _input, 0, -1), "valid handle rejects negative length");
        __test_assert(!ic_add_buf(_handle, "overflow", _input, 7, 2), "valid handle rejects range beyond input");
        __test_assert(ic_add_buf(_handle, "valid", _input, 0, 8), "valid handle remains usable after invalid ranges");
        __test_close_writer(_context, _handle);
        var _entries = ic_list(_context.directory + "/range.zip");
        __test_assert(array_length(_entries) == 1 && _entries[0].filename == "valid", "invalid additions leave no archive entries");

        var _bad = ic_compress_buf_range(_input, 7, 2, _output, 0, CompressionFormat.Gzip, CompressionLevel.Default);
        __test_assert(!_bad.success && _bad.bytes_written == 0, "compress rejects invalid input range");
        _bad = ic_compress_buf_range(_input, 0, 8, _output, -1, CompressionFormat.Gzip, CompressionLevel.Default);
        __test_assert(!_bad.success && _bad.bytes_written == 0, "compress rejects negative output offset");
        var _small = __test_buffer(_context, 1);
        buffer_poke(_small, 0, buffer_u8, 165);
        var _small_result = ic_compress_buf_range(_input, 0, 8, _small, 0, CompressionFormat.Gzip, CompressionLevel.Default);
        __test_assert(!_small_result.success && _small_result.bytes_written == 0 && _small_result.bytes_required > 1, "compress reports required capacity");
        __test_assert(buffer_peek(_small, 0, buffer_u8) == 165, "failed compression does not write output");
        var _compressed = ic_compress_buf_range(_input, 0, 8, _output, 0, CompressionFormat.Gzip, CompressionLevel.Default);
        __test_assert(_compressed.success && _compressed.bytes_written == _small_result.bytes_required, "compression retry uses required capacity");
        var _restored = ic_decompress_buf_range(_output, 0, _compressed.bytes_written, _small, 0, CompressionFormat.Gzip);
        __test_assert(!_restored.success && _restored.bytes_written == 0 && _restored.bytes_required == 8, "decompress reports required capacity");
        __test_assert(buffer_peek(_small, 0, buffer_u8) == 165, "failed decompression does not write output");
        _bad = ic_decompress_buf_range(_output, 0, _compressed.bytes_written, _input, 9, CompressionFormat.Gzip);
        __test_assert(!_bad.success && _bad.bytes_written == 0, "decompress rejects output offset beyond buffer");
    });
}

function test_archive_format_detection()
{
    return __test_with_resources("test_archive_format_detection", function(_context) {
        var _zip_handle = __test_writer(_context, "empty.zip", CompressionFormat.Zip);
        __test_close_writer(_context, _zip_handle);
        var _tar_handle = __test_writer(_context, "detect.tar", CompressionFormat.Tar);
        __test_assert(ic_add_data(_tar_handle, "entry.txt", "tar detection payload"), "tar detection setup");
        __test_close_writer(_context, _tar_handle);
        var _filenames = ["empty.zip", "detect.tar"];
        var _formats = [CompressionFormat.Zip, CompressionFormat.Tar];
        for (var _index = 0; _index < array_length(_filenames); ++_index) {
            var _path = _context.directory + "/" + _filenames[_index];
            var _buffer = __test_load_buffer(_context, _path);
            __test_assert(ic_detect(_buffer) == _formats[_index], "buffer detects " + _filenames[_index]);
            __test_assert(ic_detect_file(_path) == _formats[_index], "file detects " + _filenames[_index]);
        }
    });
}

function test_list_pagination()
{
    return __test_with_resources("test_list_pagination", function(_context) {
        var _sizes = [0, 15, 16, 17, 32, 40];
        for (var _size_index = 0; _size_index < array_length(_sizes); ++_size_index) {
            var _size = _sizes[_size_index];
            var _filename = "paged_" + string(_size) + ".zip";
            var _path = _context.directory + "/" + _filename;
            var _handle = __test_writer(_context, _filename, CompressionFormat.Zip);
            for (var _index = 0; _index < _size; ++_index) {
                __test_assert(ic_add_data(_handle, "entry_" + string(_index) + ".txt", "x"), "pagination archive setup");
            }
            __test_close_writer(_context, _handle);
            var _offset = 0;
            var _count = 0;
            var _seen = array_create(_size, false);
            var _page_count = max(1, ceil(_size / 16));
            for (var _page_index = 0; _page_index < _page_count; ++_page_index) {
                var _page = ic_list_page(_path, _offset);
                var _label = string(_size) + " entries / page " + string(_page_index);
                __test_assert(_page.success, _label + ": " + _page.error_message);
                var _expected_count = min(16, _size - _offset);
                __test_assert(array_length(_page.entries) == _expected_count, _label + " page size");
                for (var _index = 0; _index < _expected_count; ++_index) {
                    var _entry_index = _offset + _index;
                    __test_assert(!_seen[_entry_index], _label + " duplicate entry");
                    __test_assert(_page.entries[_index].filename == "entry_" + string(_entry_index) + ".txt", _label + " filename/order");
                    _seen[_entry_index] = true;
                }
                _count += _expected_count;
                __test_assert(_page.next_offset == _count, _label + " next_offset");
                __test_assert(_page.has_more == (_count < _size), _label + " has_more");
                _offset = _page.next_offset;
            }
            __test_assert(_count == _size, "pagination total count");
            for (var _index = 0; _index < _size; ++_index) __test_assert(_seen[_index], "pagination omitted entry");
            var _past_end = ic_list_page(_path, _size);
            __test_assert(_past_end.success && array_length(_past_end.entries) == 0 && !_past_end.has_more, "page at end is empty");
            __test_assert(_past_end.next_offset == _size, "page at end offset");
            var _negative = ic_list_page(_path, -1);
            __test_assert(!_negative.success && array_length(_negative.entries) == 0, "reject negative list offset");
        }
    });
}
// GNU old sparse tar: each entry contains a 512-byte header, one stored byte,
// and 511 padding bytes, regardless of its logical size. No large buffers.
function __test_tar_ascii(_buffer, _offset, _text)
{
    for (var _index = 1; _index <= string_byte_length(_text); ++_index) {
        buffer_poke(_buffer, _offset + _index - 1, buffer_u8, string_byte_at(_text, _index));
    }
}

function __test_tar_octal(_buffer, _offset, _width, _value)
{
    var _digits = "";
    do {
        _digits = chr(48 + (_value mod 8)) + _digits;
        _value = floor(_value / 8);
    } until (_value == 0);
    __test_assert(string_length(_digits) < _width, "tar octal field fits");
    while (string_length(_digits) < _width - 1) _digits = "0" + _digits;
    __test_tar_ascii(_buffer, _offset, _digits);
    buffer_poke(_buffer, _offset + _width - 1, buffer_u8, 0);
}

// Hand-crafted tar with caller-controlled entry names, typeflags, and link
// targets. Each entry is one 512-byte header plus its data padded to whole
// 512-byte blocks; two zero blocks terminate the archive.
function __test_raw_tar(_context, _filename, _entries)
{
    var _path = _context.directory + "/" + _filename;
    array_push(_context.files, _path);
    var _blocks = 2;
    for (var _entry_index = 0; _entry_index < array_length(_entries); ++_entry_index) {
        _blocks += 1 + ceil(string_byte_length(_entries[_entry_index].data) / 512);
    }
    var _archive = __test_buffer(_context, _blocks * 512);
    buffer_fill(_archive, 0, buffer_u8, 0, buffer_get_size(_archive));
    var _offset = 0;
    for (var _entry_index = 0; _entry_index < array_length(_entries); ++_entry_index) {
        var _entry = _entries[_entry_index];
        var _size = string_byte_length(_entry.data);
        __test_assert(string_byte_length(_entry.name) < 100 && string_byte_length(_entry.linkname) < 100, "tar fixture field fits");
        __test_tar_ascii(_archive, _offset, _entry.name);
        __test_tar_octal(_archive, _offset + 100, 8, 420); // 0644
        __test_tar_octal(_archive, _offset + 108, 8, 0);
        __test_tar_octal(_archive, _offset + 116, 8, 0);
        __test_tar_octal(_archive, _offset + 124, 12, _size);
        __test_tar_octal(_archive, _offset + 136, 12, 0);
        for (var _index = 148; _index < 156; ++_index) buffer_poke(_archive, _offset + _index, buffer_u8, 32);
        buffer_poke(_archive, _offset + 156, buffer_u8, _entry.typeflag);
        __test_tar_ascii(_archive, _offset + 157, _entry.linkname);
        __test_tar_ascii(_archive, _offset + 257, "ustar  "); // trailing NUL remains zero
        var _checksum = 0;
        for (var _index = 0; _index < 512; ++_index) _checksum += buffer_peek(_archive, _offset + _index, buffer_u8);
        __test_tar_octal(_archive, _offset + 148, 7, _checksum);
        buffer_poke(_archive, _offset + 155, buffer_u8, 32);
        _offset += 512;
        __test_tar_ascii(_archive, _offset, _entry.data);
        _offset += ceil(_size / 512) * 512;
    }
    buffer_save(_archive, _path);
    __test_assert(file_exists(_path), "tar fixture saved: " + _filename);
    return _path;
}

// ---- cpio "newc" fixtures (reading accepts all libarchive formats) ----

function __test_cpio_pad4(_v)
{
    return (4 - (_v mod 4)) mod 4;
}

function __test_cpio_hex8(_archive, _offset, _value)
{
    var _hex = "0123456789ABCDEF";
    for (var _i = 7; _i >= 0; --_i) {
        buffer_poke(_archive, _offset + _i, buffer_u8, string_byte_at(_hex, (_value & 0xF) + 1));
        _value = _value >> 4;
    }
}

function __test_cpio_entry(_archive, _offset, _name, _data, _trailer)
{
    var _name_size = string_byte_length(_name) + 1;
    var _data_size = string_byte_length(_data);
    __test_tar_ascii(_archive, _offset, "070701");
    __test_cpio_hex8(_archive, _offset + 6, _trailer ? 0 : 1);      // ino
    __test_cpio_hex8(_archive, _offset + 14, _trailer ? 0 : 33188); // mode 0100644
    __test_cpio_hex8(_archive, _offset + 22, 0);  // uid
    __test_cpio_hex8(_archive, _offset + 30, 0);  // gid
    __test_cpio_hex8(_archive, _offset + 38, 1);  // nlink
    __test_cpio_hex8(_archive, _offset + 46, 0);  // mtime
    __test_cpio_hex8(_archive, _offset + 54, _data_size);
    __test_cpio_hex8(_archive, _offset + 62, 0);  // devmajor
    __test_cpio_hex8(_archive, _offset + 70, 0);  // devminor
    __test_cpio_hex8(_archive, _offset + 78, 0);  // rdevmajor
    __test_cpio_hex8(_archive, _offset + 86, 0);  // rdevminor
    __test_cpio_hex8(_archive, _offset + 94, _name_size);
    __test_cpio_hex8(_archive, _offset + 102, 0); // check, unused in newc
    _offset += 110;
    __test_tar_ascii(_archive, _offset, _name); // NUL from the pre-zeroed buffer
    _offset += _name_size + __test_cpio_pad4(_offset + _name_size);
    __test_tar_ascii(_archive, _offset, _data);
    _offset += _data_size + __test_cpio_pad4(_offset + _data_size);
    return _offset;
}

function __test_raw_cpio(_context, _filename, _entries)
{
    var _path = _context.directory + "/" + _filename;
    array_push(_context.files, _path);
    var _total = 0;
    for (var _i = 0; _i < array_length(_entries); ++_i) {
        var _e = _entries[_i];
        _total += 110 + string_byte_length(_e.name) + 1;
        _total += __test_cpio_pad4(_total);
        _total += string_byte_length(_e.data);
        _total += __test_cpio_pad4(_total);
    }
    _total += 110 + 11; // "TRAILER!!!" + NUL
    _total += __test_cpio_pad4(_total);
    var _archive = __test_buffer(_context, _total);
    buffer_fill(_archive, 0, buffer_u8, 0, _total);
    var _offset = 0;
    for (var _i = 0; _i < array_length(_entries); ++_i) {
        _offset = __test_cpio_entry(_archive, _offset, _entries[_i].name, _entries[_i].data, false);
    }
    _offset = __test_cpio_entry(_archive, _offset, "TRAILER!!!", "", true);
    __test_assert(_offset == _total, "cpio fixture size matches layout");
    buffer_save(_archive, _path);
    __test_assert(file_exists(_path), "cpio fixture saved: " + _filename);
    return _path;
}

function __test_sparse_tar(_context, _prefix, _logical_size, _count)
{
    var _path = _context.directory + "/" + _prefix + ".tar";
    array_push(_context.files, _path);
    var _archive = __test_buffer(_context, _count * 1024 + 1024);
    buffer_fill(_archive, 0, buffer_u8, 0, buffer_get_size(_archive));
    var _paths = [];
    for (var _entry_index = 0; _entry_index < _count; ++_entry_index) {
        var _header = _entry_index * 1024;
        var _name = _prefix + "_" + string(_entry_index) + ".bin";
        var _output_path = _context.directory + "/" + _name;
        array_push(_context.files, _output_path);
        array_push(_paths, _output_path);
        __test_assert(string_byte_length(_name) < 100, "sparse tar filename fits");
        __test_tar_ascii(_archive, _header, _name);
        __test_tar_octal(_archive, _header + 100, 8, 420); // 0644
        __test_tar_octal(_archive, _header + 108, 8, 0);
        __test_tar_octal(_archive, _header + 116, 8, 0);
        __test_tar_octal(_archive, _header + 124, 12, 1); // one stored byte
        __test_tar_octal(_archive, _header + 136, 12, 0);
        for (var _index = 148; _index < 156; ++_index) buffer_poke(_archive, _header + _index, buffer_u8, 32);
        buffer_poke(_archive, _header + 156, buffer_u8, ord("S"));
        __test_tar_ascii(_archive, _header + 257, "ustar  "); // trailing NUL remains zero
        __test_tar_octal(_archive, _header + 386, 12, _logical_size - 1); // sparse[0].offset
        __test_tar_octal(_archive, _header + 398, 12, 1); // sparse[0].numbytes
        // isextended at 482 remains zero; no sparse extension headers.
        __test_tar_octal(_archive, _header + 483, 12, _logical_size);
        var _checksum = 0;
        for (var _index = 0; _index < 512; ++_index) _checksum += buffer_peek(_archive, _header + _index, buffer_u8);
        __test_tar_octal(_archive, _header + 148, 7, _checksum);
        buffer_poke(_archive, _header + 155, buffer_u8, 32);
        buffer_poke(_archive, _header + 512, buffer_u8, 90);
    }
    buffer_save(_archive, _path);
    __test_assert(file_exists(_path), "sparse fixture saved");
    var _listing = ic_list_page(_path, 0);
    __test_assert(_listing.success && array_length(_listing.entries) == _count && !_listing.has_more,
        "sparse fixture lists all entries: " + _listing.error_message);
    for (var _entry_index = 0; _entry_index < _count; ++_entry_index) {
        var _entry = _listing.entries[_entry_index];
        __test_assert(_entry.filename == _prefix + "_" + string(_entry_index) + ".bin", "sparse fixture filename");
        __test_assert(!_entry.is_directory && _entry.uncompressed_size == _logical_size, "sparse fixture logical size");
    }
    return { path: _path, outputs: _paths };
}

function __test_sparse_file(_path, _expected_size)
{
    __test_assert(file_exists(_path), "sparse output exists: " + _path);
    var _file = file_bin_open(_path, 0);
    __test_assert(_file >= 0, "sparse output opens");
    var _read_error = "";
    var _actual_size = -1;
    var _first = -1;
    var _middle = -1;
    var _before_last = -1;
    var _last = -1;
    try {
        _actual_size = file_bin_size(_file);
        _first = file_bin_read_byte(_file);
        file_bin_seek(_file, floor(_expected_size / 2));
        _middle = file_bin_read_byte(_file);
        file_bin_seek(_file, _expected_size - 2);
        _before_last = file_bin_read_byte(_file);
        _last = file_bin_read_byte(_file);
    }
    catch (_exception) { _read_error = string(_exception); }
    file_bin_close(_file);
    __test_assert(_read_error == "", "read sparse output: " + _read_error);
    __test_assert(_actual_size == _expected_size, "sparse logical size expected " + string(_expected_size) + ", got " + string(_actual_size));
    __test_assert(_first == 0 && _middle == 0 && _before_last == 0 && _last == 90, "sparse holes and final byte");
}

function test_sparse_extraction_limits()
{
    return __test_with_resources("test_sparse_extraction_limits", function(_context) {
        // The small valid fixture checks every hole byte before the quota cases.
        var _small_size = 8193;
        var _small = __test_sparse_tar(_context, "sparse_small", _small_size, 1);
        var _small_result = ic_extract(_small.path, _context.directory);
        __test_assert(_small_result.success && _small_result.files_extracted == 1, "small sparse extraction: " + _small_result.error_message);
        __test_sparse_file(_small.outputs[0], _small_size);
        var _small_buffer = __test_load_buffer(_context, _small.outputs[0]);
        __test_assert(buffer_get_size(_small_buffer) == _small_size, "small sparse buffer size");
        for (var _index = 0; _index < _small_size - 1; ++_index) __test_assert(buffer_peek(_small_buffer, _index, buffer_u8) == 0, "small sparse hole byte " + string(_index));
        __test_assert(buffer_peek(_small_buffer, _small_size - 1, buffer_u8) == 90, "small sparse last byte");

        // On NTFS, libarchive marks entries with these holes as sparse before
        // writing the last byte. Each fixture itself is at most 6144 bytes.
        var _entry_limit = 256 * 1024 * 1024;
        var _exact = __test_sparse_tar(_context, "sparse_exact", _entry_limit, 4);
        var _exact_result = ic_extract(_exact.path, _context.directory);
        __test_assert(_exact_result.success && _exact_result.files_extracted == 4, "exact 1 GiB sparse total succeeds: " + _exact_result.error_message);
        for (var _index = 0; _index < 4; ++_index) __test_sparse_file(_exact.outputs[_index], _entry_limit);

        var _oversized = __test_sparse_tar(_context, "sparse_oversized", _entry_limit + 1, 1);
        var _oversized_result = ic_extract(_oversized.path, _context.directory);
        __test_assert(!_oversized_result.success && _oversized_result.files_extracted == 0, "oversized sparse entry rejected");
        __test_assert(string_pos("extraction limit", _oversized_result.error_message) > 0, "oversized entry reports quota error: " + _oversized_result.error_message);
        __test_assert(!file_exists(_oversized.outputs[0]), "oversized sparse entry rejected before file creation");

        var _excess = __test_sparse_tar(_context, "sparse_excess", _entry_limit, 5);
        var _excess_result = ic_extract(_excess.path, _context.directory);
        // Validate the four permitted outputs even on the old implementation.
        for (var _index = 0; _index < 4; ++_index) __test_sparse_file(_excess.outputs[_index], _entry_limit);
        __test_assert(!_excess_result.success && _excess_result.files_extracted == 4,
            "sparse total exceeds 1 GiB: expected failure after 4 files, got success=" + string(_excess_result.success) + ", files=" + string(_excess_result.files_extracted));
        __test_assert(string_pos("extraction limit", _excess_result.error_message) > 0, "sparse total reports quota error: " + _excess_result.error_message);
        __test_assert(!file_exists(_excess.outputs[4]), "fifth sparse file rejected before creation");
    });
}

// Full extraction rejects link entries, special files, and unsafe names before
// writing anything (ICompression_native.cpp :270-307, :1252-1267).
function test_extract_rejects_unsafe_entries()
{
    return __test_with_resources("test_extract_rejects_unsafe_entries", function(_context) {
        var _out = _context.directory + "/out";
        directory_create(_out);
        var _cases = [
            { key: "symlink", name: "link.txt", typeflag: ord("2"), linkname: "target.txt", data: "", blocked_file: _out + "/link.txt", blocked_dir: "", blocked_outside: "" },
            { key: "hardlink", name: "hard.txt", typeflag: ord("1"), linkname: "target.txt", data: "", blocked_file: _out + "/hard.txt", blocked_dir: "", blocked_outside: "" },
            { key: "chardev", name: "device.txt", typeflag: ord("3"), linkname: "", data: "", blocked_file: _out + "/device.txt", blocked_dir: "", blocked_outside: "" },
            { key: "fifo", name: "pipe.txt", typeflag: ord("6"), linkname: "", data: "", blocked_file: _out + "/pipe.txt", blocked_dir: "", blocked_outside: "" },
            { key: "dotdot", name: "../evil.txt", typeflag: ord("0"), linkname: "", data: "evil", blocked_file: _out + "/evil.txt", blocked_dir: "", blocked_outside: _context.directory + "/evil.txt" },
            { key: "dotdot_backslash", name: ".." + chr(92) + "evil.txt", typeflag: ord("0"), linkname: "", data: "evil", blocked_file: _out + "/evil.txt", blocked_dir: "", blocked_outside: _context.directory + "/evil.txt" },
            { key: "absolute", name: "/abs/evil.txt", typeflag: ord("0"), linkname: "", data: "evil", blocked_file: _out + "/abs/evil.txt", blocked_dir: _out + "/abs", blocked_outside: "" },
        ];
        for (var _index = 0; _index < array_length(_cases); ++_index) {
            var _unsafe = _cases[_index];
            var _path = __test_raw_tar(_context, "unsafe_" + _unsafe.key + ".tar", [_unsafe]);
            var _listing = ic_list_page(_path, 0);
            __test_assert(_listing.success && array_length(_listing.entries) == 1, _unsafe.key + ": fixture lists one entry: " + _listing.error_message);
            var _result = ic_extract(_path, _out);
            __test_assert(!_result.success, _unsafe.key + ": extraction rejected");
            __test_assert(_result.files_extracted == 0, _unsafe.key + ": nothing extracted, got " + string(_result.files_extracted));
            __test_assert(string_pos("unsafe entry", _result.error_message) > 0, _unsafe.key + ": unsafe-entry error, got " + _result.error_message);
            __test_assert(!file_exists(_unsafe.blocked_file), _unsafe.key + ": no file materialized");
            if (_unsafe.blocked_dir != "") __test_assert(!directory_exists(_unsafe.blocked_dir), _unsafe.key + ": no directory materialized");
            if (_unsafe.blocked_outside != "") __test_assert(!file_exists(_unsafe.blocked_outside), _unsafe.key + ": nothing written outside the output directory");
        }
        // Entries written before the unsafe one stay on disk: the abort leaves
        // earlier successes in place (ICompression_native.cpp :1258-1267).
        var _mixed = __test_raw_tar(_context, "unsafe_mixed.tar", [
            { name: "sub/ok.txt", typeflag: ord("0"), linkname: "", data: "safe content" },
            { name: "link.txt", typeflag: ord("2"), linkname: "target.txt", data: "" }
        ]);
        var _mixed_result = ic_extract(_mixed, _out);
        __test_assert(!_mixed_result.success && _mixed_result.files_extracted == 1, "abort after a valid entry keeps its count");
        __test_assert(string_pos("unsafe entry", _mixed_result.error_message) > 0, "mixed archive reports the unsafe entry: " + _mixed_result.error_message);
        __test_assert(file_exists(_out + "/sub/ok.txt"), "entry extracted before the unsafe one remains");
        __test_assert(!file_exists(_out + "/link.txt"), "unsafe entry after a valid one is not created");
        // Control: the same fixture style extracts a safe nested name.
        var _control = __test_raw_tar(_context, "safe_control.tar", [
            { name: "sub/ok2.txt", typeflag: ord("0"), linkname: "", data: "safe content" }
        ]);
        var _control_result = ic_extract(_control, _out);
        __test_assert(_control_result.success && _control_result.files_extracted == 1, "control nested entry extracts: " + _control_result.error_message);
        var _control_file = file_text_open_read(_out + "/sub/ok2.txt");
        var _control_text = file_text_read_string(_control_file);
        file_text_close(_control_file);
        __test_assert(_control_text == "safe content", "control content round-trips");
    });
}

// MAX_ENTRY_PATH_SIZE (4096) bounds the archive entry path alone; output_dir is
// not part of the measurement (ICompression_native.cpp :32, :1252-1254).
function test_extract_entry_path_limit()
{
    return __test_with_resources("test_extract_entry_path_limit", function(_context) {
        var _long_name = string_repeat("b", 4097);
        var _handle = __test_writer(_context, "long_extract.zip", CompressionFormat.Zip);
        __test_assert(ic_add_data(_handle, _long_name, "x"), "long entry name added");
        __test_close_writer(_context, _handle);
        var _out = _context.directory + "/out_long";
        directory_create(_out);
        var _result = ic_extract(_context.directory + "/long_extract.zip", _out);
        __test_assert(!_result.success, "entry path over 4096 bytes rejected");
        __test_assert(_result.files_extracted == 0, "long-path entry extracted nothing");
        __test_assert(string_pos("unsafe entry", _result.error_message) > 0, "long path reports unsafe entry: " + string_copy(_result.error_message, 1, 48));
        // file_exists() on a >4096-char path crashes the Windows VM outright
        // (runner bug, reproduced: access violation), so prove the output
        // directory stayed empty through a short wildcard instead.
        var _found = file_find_first(_out + "/*", fa_directory);
        file_find_close();
        __test_assert(_found == "", "no long-path file materialized");
    });
}

// Listing fails on entry paths over 256 UTF-8 bytes; 256 bytes still lists, and
// entries skipped by the page offset are never name-checked
// (ICompression_native.cpp :33, :1160-1166).
function test_list_page_long_entry_path()
{
    return __test_with_resources("test_list_page_long_entry_path", function(_context) {
        var _long_name = string_repeat("a", 257);
        var _handle = __test_writer(_context, "long_list.zip", CompressionFormat.Zip);
        __test_assert(ic_add_data(_handle, _long_name, "x"), "long entry name added");
        __test_assert(ic_add_data(_handle, "normal.txt", "y"), "normal entry added");
        __test_close_writer(_context, _handle);
        var _path = _context.directory + "/long_list.zip";
        var _page = ic_list_page(_path, 0);
        __test_assert(!_page.success, "listing a 257-byte entry path fails");
        __test_assert(array_length(_page.entries) == 0, "failed listing returns no entries");
        __test_assert(string_pos("too long to list", _page.error_message) > 0, "long path reports the listing limit: " + _page.error_message);
        var _skipped = ic_list_page(_path, 1);
        __test_assert(_skipped.success, "offset-skipped long entry is not name-checked: " + _skipped.error_message);
        __test_assert(array_length(_skipped.entries) == 1 && _skipped.entries[0].filename == "normal.txt", "only the normal entry lists after the skip");
        var _edge_handle = __test_writer(_context, "list_edge.zip", CompressionFormat.Zip);
        __test_assert(ic_add_data(_edge_handle, string_repeat("c", 256), "z"), "boundary entry name added");
        __test_close_writer(_context, _edge_handle);
        var _edge = ic_list_page(_context.directory + "/list_edge.zip", 0);
        __test_assert(_edge.success && array_length(_edge.entries) == 1, "256-byte entry path lists: " + _edge.error_message);
        __test_assert(string_byte_length(_edge.entries[0].filename) == 256, "boundary entry name preserved");
    });
}

// 65,535 entries scan cleanly; the 65,536th header trips MAX_ARCHIVE_ENTRIES,
// surfaced by ic_list_page as a dedicated error (ICompression_native.cpp :31,
// :1135-1138). ic_extract enforces the same bound via the unsafe-entry path
// (:1252); that variant is not exercised to avoid writing 65,535 files.
function test_entry_scan_limit()
{
    return __test_with_resources("test_entry_scan_limit", function(_context) {
        var _full_handle = __test_writer(_context, "scan_full.zip", CompressionFormat.Zip);
        for (var _index = 0; _index < 65535; ++_index) {
            __test_assert(ic_add_data(_full_handle, "e" + string(_index), ""), "scan-limit fixture entry " + string(_index));
        }
        __test_close_writer(_context, _full_handle);
        var _full = ic_list_page(_context.directory + "/scan_full.zip", 65534);
        __test_assert(_full.success, "65,535 entries scan to the end: " + _full.error_message);
        __test_assert(array_length(_full.entries) == 1 && _full.entries[0].filename == "e65534", "last entry lists at the boundary");
        __test_assert(!_full.has_more && _full.next_offset == 65535, "boundary page finishes the archive");

        var _over_handle = __test_writer(_context, "scan_over.zip", CompressionFormat.Zip);
        for (var _index = 0; _index < 65536; ++_index) {
            __test_assert(ic_add_data(_over_handle, "e" + string(_index), ""), "scan-limit fixture entry " + string(_index));
        }
        __test_close_writer(_context, _over_handle);
        var _over_path = _context.directory + "/scan_over.zip";
        var _first = ic_list_page(_over_path, 0);
        __test_assert(_first.success && array_length(_first.entries) == 16 && _first.has_more, "oversized archive still lists its first page");
        var _over = ic_list_page(_over_path, 65535);
        __test_assert(!_over.success && array_length(_over.entries) == 0, "entry 65,536 rejected by the scan limit");
        __test_assert(string_pos("too many entries", _over.error_message) > 0, "scan-limit error reported: " + _over.error_message);
    });
}

// A non-sparse entry is accepted at exactly 256 MiB and rejected at one byte
// more, from its declared size, before any data is written
// (ICompression_native.cpp :28, :1269-1283).
function test_nonsparse_entry_size_limit()
{
    return __test_with_resources("test_nonsparse_entry_size_limit", function(_context) {
        var _limit = 256 * 1024 * 1024;
        var _zeros = __test_buffer(_context, _limit + 1); // zero-initialized
        var _out_accept = _context.directory + "/out_accept";
        var _out_reject = _context.directory + "/out_reject";
        directory_create(_out_accept);
        directory_create(_out_reject);

        var _accept_handle = __test_writer(_context, "accept.zip", CompressionFormat.Zip);
        __test_assert(ic_add_buf(_accept_handle, "payload.bin", _zeros, 0, _limit), "accept-side entry added");
        __test_close_writer(_context, _accept_handle);
        var _accept = ic_extract(_context.directory + "/accept.zip", _out_accept);
        __test_assert(_accept.success && _accept.files_extracted == 1, "256 MiB entry extracts: " + _accept.error_message);
        var _accept_file = _out_accept + "/payload.bin";
        __test_assert(file_exists(_accept_file), "accept-side output exists");
        var _bin = file_bin_open(_accept_file, 0);
        __test_assert(_bin >= 0, "accept-side output opens");
        var _size = file_bin_size(_bin);
        var _first = file_bin_read_byte(_bin);
        file_bin_seek(_bin, _limit - 1);
        var _last = file_bin_read_byte(_bin);
        file_bin_close(_bin);
        __test_assert(_size == _limit, "accept-side output is exactly 256 MiB, got " + string(_size));
        __test_assert(_first == 0 && _last == 0, "accept-side output contains the zero payload");

        var _reject_handle = __test_writer(_context, "reject.zip", CompressionFormat.Zip);
        __test_assert(ic_add_buf(_reject_handle, "payload.bin", _zeros, 0, _limit + 1), "reject-side entry added");
        __test_close_writer(_context, _reject_handle);
        var _reject = ic_extract(_context.directory + "/reject.zip", _out_reject);
        __test_assert(!_reject.success && _reject.files_extracted == 0, "256 MiB + 1 entry rejected");
        __test_assert(string_pos("extraction limit", _reject.error_message) > 0, "reject-side reports quota: " + _reject.error_message);
        __test_assert(!file_exists(_out_reject + "/payload.bin"), "reject-side output not created");
    });
}

// A missing entry in an over-limit archive keeps the specific scan-limit error
// instead of being overwritten by the generic not-found message
// (ICompression_native.cpp :1541-1570).
function test_extract_buf_keeps_scan_limit_error()
{
    return __test_with_resources("test_extract_buf_keeps_scan_limit_error", function(_context) {
        var _handle = __test_writer(_context, "scan_over_buf.zip", CompressionFormat.Zip);
        for (var _index = 0; _index < 65536; ++_index) {
            __test_assert(ic_add_data(_handle, "e" + string(_index), ""), "scan-limit fixture entry " + string(_index));
        }
        __test_close_writer(_context, _handle);
        var _output = __test_buffer(_context, 16);
        var _result = ic_extract_buf(_context.directory + "/scan_over_buf.zip", "missing.txt", _output, 0);
        __test_assert(!_result.success, "missing entry in an over-limit archive fails");
        __test_assert(string_pos("scan limit", _result.error_message) > 0, "scan-limit error kept, got: " + _result.error_message);
        __test_assert(string_pos("not found", _result.error_message) == 0, "specific error not clobbered: " + _result.error_message);
    });
}

// Windows-reserved entry names are rejected per path segment before anything is
// written: NTFS ADS colons, DOS device names (on the stem before the first
// dot), and segments ending with a dot or space
// (ICompression_native.cpp :252-307).
function test_extract_rejects_windows_names()
{
    return __test_with_resources("test_extract_rejects_windows_names", function(_context) {
        var _cases = [
            { key: "device_dir", name: "dir/NUL" },
            { key: "device_stem", name: "NUL.txt" },
            { key: "ads_colon", name: "evil.txt:ads" },
            { key: "trailing_dot", name: "trailing." },
            { key: "trailing_space", name: "trailing /file.txt" },
        ];
        for (var _index = 0; _index < array_length(_cases); ++_index) {
            var _case = _cases[_index];
            var _path = __test_raw_tar(_context, "win_" + _case.key + ".tar", [
                { name: _case.name, typeflag: ord("0"), linkname: "", data: "evil" }
            ]);
            var _out = _context.directory + "/out_" + _case.key;
            directory_create(_out);
            var _result = ic_extract(_path, _out);
            __test_assert(!_result.success, _case.key + ": extraction rejected");
            __test_assert(_result.files_extracted == 0, _case.key + ": nothing extracted, got " + string(_result.files_extracted));
            __test_assert(string_pos("unsafe entry", _result.error_message) > 0, _case.key + ": unsafe-entry error, got " + _result.error_message);
            // DOS device names answer file_exists() through the device itself,
            // so prove the output directory stayed empty with a wildcard.
            var _found = file_find_first(_out + "/*", fa_directory);
            file_find_close();
            __test_assert(_found == "", _case.key + ": nothing materialized");
        }
        var _control = __test_raw_tar(_context, "win_safe_control.tar", [
            { name: "sub/ok.txt", typeflag: ord("0"), linkname: "", data: "safe content" }
        ]);
        var _control_out = _context.directory + "/out_control";
        directory_create(_control_out);
        var _control_result = ic_extract(_control, _control_out);
        __test_assert(_control_result.success && _control_result.files_extracted == 1, "safe control extracts: " + _control_result.error_message);
        __test_assert(file_exists(_control_out + "/sub/ok.txt"), "safe control file materialized");
    });
}

// An attacker-controlled entry path embedded in the unsafe-entry error is
// truncated to 256 bytes without splitting a UTF-8 sequence
// (ICompression_native.cpp :311-321, :1260).
function test_extract_error_truncates_path()
{
    return __test_with_resources("test_extract_error_truncates_path", function(_context) {
        var _long_name = string_repeat("a", 1000) + ":" + string_repeat("b", 999);
        var _handle = __test_writer(_context, "truncate.zip", CompressionFormat.Zip);
        __test_assert(ic_add_data(_handle, _long_name, "x"), "long colon entry added");
        __test_close_writer(_context, _handle);
        var _out = _context.directory + "/out_truncate";
        directory_create(_out);
        var _result = ic_extract(_context.directory + "/truncate.zip", _out);
        __test_assert(!_result.success, "colon entry rejected");
        __test_assert(string_pos("unsafe entry", _result.error_message) > 0, "unsafe-entry error, got: " + string_copy(_result.error_message, 1, 64));
        __test_assert(string_length(_result.error_message) <= 300, "error message bounded, got length " + string(string_length(_result.error_message)));
        __test_assert(string_copy(_result.error_message, string_length(_result.error_message) - 2, 3) == "...", "truncated message ends with an ellipsis");
    });
}

// The file APIs stream, so input past the old in-memory caps round-trips
// (ICompression_native.cpp :280-334, :924-1170). 300 MiB clears the 256 MiB
// per-entry cap the previous whole-file implementation inherited from
// decompress_raw; zeros keep every archive under a megabyte, so the VM spends
// seconds on I/O instead of minutes on compression.
function test_file_apis_stream_large_input()
{
    return __test_with_resources("test_file_apis_stream_large_input", function(_context) {
        var _size = 300 * 1024 * 1024;
        var _source = _context.directory + "/large.bin";
        array_push(_context.files, _source);
        // Materialize the zero input with a single write past EOF: the OS
        // zero-fills instantly, while buffer_save() of a buffer this large
        // silently writes a 1-byte stub in the VM (reproduced on 1.0.8.2).
        var _source_file = file_bin_open(_source, 1);
        file_bin_seek(_source_file, _size - 1);
        file_bin_write_byte(_source_file, 0);
        file_bin_close(_source_file);
        var _source_check = file_bin_open(_source, 0);
        var _source_size = file_bin_size(_source_check);
        file_bin_close(_source_check);
        __test_assert(_source_size == _size, "large input materialized, got " + string(_source_size));

        var _formats = [CompressionFormat.Gzip, CompressionFormat.Zstd];
        var _extensions = ["gz", "zst"];
        for (var _index = 0; _index < array_length(_formats); ++_index) {
            var _format = _formats[_index];
            var _label = ic_to_str(_format) + " 300 MiB file";
            var _archive = _context.directory + "/large_" + string(_index) + "." + _extensions[_index];
            var _restored = _context.directory + "/restored_" + string(_index) + ".bin";
            var _roundtrip = _context.directory + "/roundtrip_" + string(_index) + "." + _extensions[_index];
            array_push(_context.files, _archive);
            array_push(_context.files, _restored);
            array_push(_context.files, _roundtrip);
            __test_assert(ic_compress_file(_source, _archive, _format, CompressionLevel.Default), _label + " compresses");
            __test_assert(ic_decompress_file(_archive, _restored, _format), _label + " decompresses");
            var _file = file_bin_open(_restored, 0);
            __test_assert(_file >= 0, _label + " restored output opens");
            var _restored_size = file_bin_size(_file);
            file_bin_close(_file);
            __test_assert(_restored_size == _size, _label + " restored size, got " + string(_restored_size));
            // Recompressing the restored output must reproduce the archive
            // byte for byte: both filters are deterministic at a fixed level.
            // The gzip filter stamps its 10-byte header with the current time
            // (libarchive archive_write_add_filter_gzip.c), so only the
            // payload beyond the fixed header is compared.
            __test_assert(ic_compress_file(_restored, _roundtrip, _format, CompressionLevel.Default), _label + " recompresses");
            var _first = __test_load_buffer(_context, _archive);
            var _second = __test_load_buffer(_context, _roundtrip);
            __test_assert(buffer_get_size(_first) == buffer_get_size(_second), _label + " archive sizes match");
            __test_assert(buffer_get_size(_first) > 10 && buffer_get_size(_first) < 4 * 1024 * 1024, _label + " zeros compress to a tiny archive");
            __test_assert(__test_equal_bytes(_first, 10, _second, 10, buffer_get_size(_first) - 10), _label + " archive payloads match");
        }
    });
}

// Raw file compression stores the payload verbatim and raw decompression is a
// plain byte copy (ICompression_native.cpp :1017-1044).
function test_file_apis_raw_copy()
{
    return __test_with_resources("test_file_apis_raw_copy", function(_context) {
        var _size = 65536 + 3; // deliberately not block-aligned
        var _source_buffer = __test_buffer(_context, _size);
        for (var _index = 0; _index < _size; ++_index) buffer_poke(_source_buffer, _index, buffer_u8, _index mod 251);
        var _source = _context.directory + "/raw_input.bin";
        var _archive = _context.directory + "/raw_archive.bin";
        var _restored = _context.directory + "/raw_restored.bin";
        array_push(_context.files, _source);
        array_push(_context.files, _archive);
        array_push(_context.files, _restored);
        buffer_save(_source_buffer, _source);
        __test_assert(ic_compress_file(_source, _archive, CompressionFormat.Raw, CompressionLevel.Default), "raw file compresses");
        var _archive_buffer = __test_load_buffer(_context, _archive);
        __test_assert(buffer_get_size(_archive_buffer) == _size, "raw archive stores the payload verbatim");
        __test_assert(__test_equal_bytes(_source_buffer, 0, _archive_buffer, 0, _size), "raw archive bytes identical");
        __test_assert(ic_decompress_file(_archive, _restored, CompressionFormat.Raw), "raw file decompresses");
        var _restored_buffer = __test_load_buffer(_context, _restored);
        __test_assert(buffer_get_size(_restored_buffer) == _size, "raw restored size");
        __test_assert(__test_equal_bytes(_source_buffer, 0, _restored_buffer, 0, _size), "raw restored bytes identical");
    });
}

// Streaming outputs are all-or-nothing: failures create no destination, leave
// an existing destination untouched, and delete their temporary files
// (ICompression_native.cpp :75-99).
function test_file_api_failure_cleanliness()
{
    return __test_with_resources("test_file_api_failure_cleanliness", function(_context) {
        var _missing_dst = _context.directory + "/missing.gz";
        __test_assert(!ic_compress_file(_context.directory + "/no_such_input.bin", _missing_dst, CompressionFormat.Gzip, CompressionLevel.Default), "missing source fails");
        __test_assert(!file_exists(_missing_dst), "missing source creates no destination");

        var _garbage = _context.directory + "/garbage.bin";
        array_push(_context.files, _garbage);
        var _garbage_text = "this is not a compressed stream";
        var _garbage_buffer = __test_buffer(_context, string_byte_length(_garbage_text));
        buffer_write(_garbage_buffer, buffer_text, _garbage_text);
        buffer_save(_garbage_buffer, _garbage);

        var _out = _context.directory + "/garbage.out";
        __test_assert(!ic_decompress_file(_garbage, _out, CompressionFormat.Gzip), "garbage input fails");
        __test_assert(!file_exists(_out), "garbage input creates no output");

        var _existing = _context.directory + "/existing.out";
        array_push(_context.files, _existing);
        var _kept = __test_buffer(_context, 8);
        for (var _index = 0; _index < 8; ++_index) buffer_poke(_kept, _index, buffer_u8, 200 + _index);
        buffer_save(_kept, _existing);
        __test_assert(!ic_decompress_file(_garbage, _existing, CompressionFormat.Gzip), "garbage over existing output fails");
        var _preserved = __test_load_buffer(_context, _existing);
        __test_assert(buffer_get_size(_preserved) == 8 && __test_equal_bytes(_kept, 0, _preserved, 0, 8), "failed decompress preserves existing output");

        var _leftover = file_find_first(_context.directory + "/*.tmp*", fa_directory);
        file_find_close();
        __test_assert(_leftover == "", "no temporary files remain");
    });
}

function test_open_handle_limit()
{
    show_debug_message("--- test_open_handle_limit ---");
    var _dir = __test_temp_dir();
    directory_create(_dir);
    var _handles = array_create(64, -1);
    for (var _i = 0; _i < 64; ++_i) {
        _handles[_i] = ic_create(_dir + $"/limit_{_i}.zip", CompressionFormat.Zip);
        if (_handles[_i] < 0) {
            for (var _j = 0; _j < _i; ++_j) ic_close(_handles[_j]);
            __test_cleanup_dir(_dir);
            return false;
        }
    }

    var _extra = ic_create(_dir + "/limit_extra.zip", CompressionFormat.Zip);
    for (var _i = 0; _i < 64; ++_i) {
        ic_close(_handles[_i]);
        file_delete(_dir + $"/limit_{_i}.zip");
    }
    if (_extra >= 0) ic_close(_extra);
    directory_destroy(_dir);
    if (_extra >= 0) { show_debug_message("[FAIL] open handle limit"); return false; }
    show_debug_message("[OK] test_open_handle_limit");
    return true;
}

// =============================================================================
// TEST: ic_detect rejects invalid tar headers
// =============================================================================

function test_detect_tar_negatives()
{
    return __test_with_resources("test_detect_tar_negatives", function(_context) {
        // A plausible ustar header whose checksum does not match its bytes.
        var _header = __test_buffer(_context, 512);
        buffer_poke(_header, 0, buffer_text, "payload.txt");
        buffer_poke(_header, 100, buffer_text, "0000644");
        buffer_poke(_header, 108, buffer_text, "0000000");
        buffer_poke(_header, 116, buffer_text, "0000000");
        buffer_poke(_header, 124, buffer_text, "00000000020");
        buffer_poke(_header, 136, buffer_text, "14700000000");
        buffer_poke(_header, 148, buffer_text, "0000000");
        buffer_poke(_header, 156, buffer_text, "0");
        buffer_poke(_header, 257, buffer_text, "ustar");
        __test_assert(ic_detect(_header) != CompressionFormat.Tar, "buffer: wrong tar checksum must not detect as Tar");
        var _header_path = _context.directory + "/bad_checksum.bin";
        array_push(_context.files, _header_path);
        buffer_save(_header, _header_path);
        __test_assert(ic_detect_file(_header_path) != CompressionFormat.Tar, "file: wrong tar checksum must not detect as Tar");

        // A truncated header is too short to validate as tar.
        var _truncated = __test_buffer(_context, 100);
        buffer_poke(_truncated, 0, buffer_text, "payload.txt");
        __test_assert(ic_detect(_truncated) != CompressionFormat.Tar, "buffer: truncated tar header must not detect as Tar");
        var _truncated_path = _context.directory + "/truncated.bin";
        array_push(_context.files, _truncated_path);
        buffer_save(_truncated, _truncated_path);
        __test_assert(ic_detect_file(_truncated_path) != CompressionFormat.Tar, "file: truncated tar header must not detect as Tar");

        // An all-zero block is the tar end-of-archive marker, not a header.
        var _zeros = __test_buffer(_context, 512);
        __test_assert(ic_detect(_zeros) != CompressionFormat.Tar, "buffer: zero block must not detect as Tar");
        var _zeros_path = _context.directory + "/zeros.bin";
        array_push(_context.files, _zeros_path);
        buffer_save(_zeros, _zeros_path);
        __test_assert(ic_detect_file(_zeros_path) != CompressionFormat.Tar, "file: zero block must not detect as Tar");
    });
}

// Archive reading accepts every libarchive format (README Support); cpio newc
// is the pinned representative. Detection does not cover it and reports Raw.
function test_cpio_read()
{
    return __test_with_resources("test_cpio_read", function(_context) {
        var _path = __test_raw_cpio(_context, "sample.cpio", [
            { name : "hello.txt", data : "Hello, cpio!" },
            { name : "dir/note.txt", data : "nested" },
        ]);
        var _page = ic_list_page(_path, 0);
        __test_assert(_page.success && array_length(_page.entries) == 2, "cpio lists both entries: " + _page.error_message);
        __test_assert(_page.entries[0].filename == "hello.txt", "cpio first entry name");
        __test_assert(ic_extract_mem(_path, "dir/note.txt") == "nested", "cpio single entry content");
        var _out = _context.directory + "/out_cpio";
        directory_create(_out);
        var _result = ic_extract(_path, _out);
        __test_assert(_result.success && _result.files_extracted == 2, "cpio full extraction: " + _result.error_message);
        __test_assert(file_exists(_out + "/hello.txt") && file_exists(_out + "/dir/note.txt"), "cpio entries materialized");
        var _magic = __test_buffer(_context, 16);
        buffer_poke(_magic, 0, buffer_text, "070701");
        __test_assert(ic_detect(_magic) == CompressionFormat.Raw, "cpio detection reports Raw");
    });
}

// =============================================================================
// Test runner
// =============================================================================

function run_all_tests()
{
    show_debug_message("");
    show_debug_message("##########################################");
    show_debug_message("#  ICompression Test Suite");
    show_debug_message("##########################################");

    var _total = 0;
    var _passed = 0;

    var _tests = [
        test_to_str,
        test_detect_magic,
        test_from_ext,
        test_stream_compress_decompress,
        test_buffer_compress_decompress,
        test_binary_buffer_apis,
        test_file_compress_decompress,
        test_archive_create_list_extract,
        test_extract_all,
        test_extract_single_file,
        test_add_file_from_disk,
        test_tar_archive,
        test_compression_levels,
        test_edge_cases,
        test_multiple_handles,
        test_detect_file,
        test_7z_archive,
        test_error_handling,
        test_binary_stream_roundtrips,
        test_archive_buffer_roundtrips,
        test_stream_validation,
        test_buffer_invalid_ranges,
        test_archive_format_detection,
        test_detect_tar_negatives,
        test_list_pagination,
        test_sparse_extraction_limits,
        test_extract_rejects_unsafe_entries,
        test_extract_entry_path_limit,
        test_list_page_long_entry_path,
        test_entry_scan_limit,
        test_nonsparse_entry_size_limit,
        test_extract_buf_keeps_scan_limit_error,
        test_extract_rejects_windows_names,
        test_extract_error_truncates_path,
        test_file_apis_stream_large_input,
        test_file_apis_raw_copy,
        test_file_api_failure_cleanliness,
        test_open_handle_limit,
        test_cpio_read,
    ];

    for (var _i = 0; _i < array_length(_tests); _i++)
    {
        _total++;
        if (_tests[_i]()) _passed++;
    }

    __test_summary(_total, _passed);
    return _passed == _total;
}
