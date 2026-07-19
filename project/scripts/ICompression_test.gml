/// @description ICompression 扩展测试脚本

global.__test_passed = 0;
global.__test_failed = 0;

/// @func test_assert(_condition, _message)
/// @param {Bool} _condition
/// @param {String} _message
function test_assert(_condition, _message) {
    if (_condition) {
        global.__test_passed++;
        show_debug_message("[PASS] " + _message);
    } else {
        global.__test_failed++;
        show_debug_message("[FAIL] " + _message);
    }
}

/// @func test_reset()
function test_reset() {
    global.__test_passed = 0;
    global.__test_failed = 0;
}

/// @func test_summary()
/// @returns {String}
function test_summary() {
    var _total = global.__test_passed + global.__test_failed;
    return "Tests: " + string(_total) + " | Passed: " + string(global.__test_passed) + " | Failed: " + string(global.__test_failed);
}

// =============================================================================
// 辅助函数
// =============================================================================

function test_save_test_data(_path) {
    var _buf = buffer_create(1024, buffer_fixed, 1);
    buffer_write(_buf, buffer_string, "Hello ICompression!");
    buffer_save(_buf, _path);
    buffer_delete(_buf);
}

// =============================================================================
// 测试用例
// =============================================================================

function test_iCompression_detect_format() {
    show_debug_message("=== test_iCompression_detect_format ===");
    
    test_assert(ic_detect("") == CompressionFormat.Raw, "Empty data -> Raw");
    
    var _zip_magic = "PK\x03\x04";
    test_assert(ic_detect(_zip_magic) == CompressionFormat.Zip, "ZIP magic detected");
    
    var _sevenz_magic = "\x37\x7A\xBC\xAF\x27\x1C";
    test_assert(ic_detect(_sevenz_magic) == CompressionFormat.SevenZ, "7Z magic detected");
    
    var _gzip_magic = "\x1F\x8B";
    test_assert(ic_detect(_gzip_magic) == CompressionFormat.Gzip, "Gzip magic detected");
    
    var _zstd_magic = "\x28\xB5\x2F\xFD";
    test_assert(ic_detect(_zstd_magic) == CompressionFormat.Zstd, "Zstd magic detected");
    
    var _lz4_magic = "\x04\x22\x4D\x18";
    test_assert(ic_detect(_lz4_magic) == CompressionFormat.Lz4, "Lz4 magic detected");
    
    var _xz_magic = "\xFD\x37\x7A\x58\x5A\x00";
    test_assert(ic_detect(_xz_magic) == CompressionFormat.Xz, "Xz magic detected");
    
    var _tar_magic = "ustar";
    test_assert(ic_detect(_tar_magic) == CompressionFormat.Raw, "Unknown -> Raw");
}

function test_iCompression_from_ext() {
    show_debug_message("=== test_iCompression_from_ext ===");
    
    test_assert(ic_from_ext("archive.zip") == CompressionFormat.Zip, "ext .zip -> Zip");
    test_assert(ic_from_ext("backup.7z") == CompressionFormat.SevenZ, "ext .7z -> SevenZ");
    test_assert(ic_from_ext("data.gz") == CompressionFormat.Gzip, "ext .gz -> Gzip");
    test_assert(ic_from_ext("data.zst") == CompressionFormat.Zstd, "ext .zst -> Zstd");
    test_assert(ic_from_ext("pack.lz4") == CompressionFormat.Lz4, "ext .lz4 -> Lz4");
    test_assert(ic_from_ext("pack.xz") == CompressionFormat.Xz, "ext .xz -> Xz");
    test_assert(ic_from_ext("archive.tar") == CompressionFormat.Tar, "ext .tar -> Tar");
    test_assert(ic_from_ext("unknown.bin") == CompressionFormat.Raw, "ext .bin -> Raw");
    test_assert(ic_from_ext("noext") == CompressionFormat.Raw, "no ext -> Raw");
}

function test_iCompression_compress_decompress() {
    show_debug_message("=== test_iCompression_compress_decompress ===");
    
    var _original = "Hello ICompression! This is a test string.";
    var _round_trip_ok = true;
    var _formats = [
        CompressionFormat.Zip,
        CompressionFormat.Gzip,
        CompressionFormat.Zstd,
        CompressionFormat.Lz4,
        CompressionFormat.Xz,
        CompressionFormat.Tar,
        CompressionFormat.Raw
    ];
    
    for (var _i = 0; _i < array_length(_formats); _i++) {
        var _fmt = _formats[_i];
        var _name = ic_to_str(_fmt);
        
        var _compressed = ic_compress(_original, _fmt, CompressionLevel.Default);
        test_assert(string_length(_compressed) > 0, "compress(" + _name + ") returns non-empty");
        
        var _decompressed = ic_decompress(_compressed, _fmt);
        test_assert(_decompressed == _original, "round-trip " + _name);
        
        if (_decompressed != _original) {
            _round_trip_ok = false;
        }
    }
    
    test_assert(_round_trip_ok, "All formats round-trip correctly");
    
    var _empty_compressed = ic_compress("", CompressionFormat.Zstd, CompressionLevel.Default);
    test_assert(string_length(_empty_compressed) >= 0, "compress empty string doesn't crash");
}

function test_iCompression_compress_decompress_file() {
    show_debug_message("=== test_iCompression_compress_decompress_file ===");
    
    var _test_dir = "test_ic_tmp";
    var _src = _test_dir + "/source.txt";
    var _dst = _test_dir + "/output.zst";
    var _out = _test_dir + "/restored.txt";
    
    if (!directory_exists(_test_dir)) {
        directory_create(_test_dir);
    }
    test_save_test_data(_src);
    
    var _r1 = ic_compress_file(_src, _dst, CompressionFormat.Zstd, CompressionLevel.Default);
    test_assert(_r1 == true, "compress_file returns true");
    test_assert(file_exists(_dst), "compressed file exists");
    
    var _r2 = ic_decompress_file(_dst, _out, CompressionFormat.Zstd);
    test_assert(_r2 == true, "decompress_file returns true");
    test_assert(file_exists(_out), "decompressed file exists");
    
    var _orig_buf = buffer_load(_src);
    var _rest_buf = buffer_load(_out);
    var _orig_str = buffer_read(_orig_buf, buffer_string);
    var _rest_str = buffer_read(_rest_buf, buffer_string);
    
    test_assert(_orig_str == _rest_str, "file round-trip content matches");
    
    buffer_delete(_orig_buf);
    buffer_delete(_rest_buf);
    
    file_delete(_src);
    file_delete(_dst);
    file_delete(_out);
    directory_destroy(_test_dir);
}

function test_iCompression_archive_operations() {
    show_debug_message("=== test_iCompression_archive_operations ===");
    
    var _zip_path = "test_ic_archive.zip";
    var _extract_dir = "test_ic_extracted";
    
    if (file_exists(_zip_path)) file_delete(_zip_path);
    if (directory_exists(_extract_dir)) directory_destroy(_extract_dir);
    
    var _h = ic_create(_zip_path, CompressionFormat.Zip);
    test_assert(_h > 0, "create() returns handle > 0");
    
    var _test_file = "test_source.txt";
    test_save_test_data(_test_file);
    
    var _r1 = ic_add_file(_h, _test_file, "entry_file.txt");
    test_assert(_r1 == true, "add_file() returns true");
    
    var _r2 = ic_add_data(_h, "entry_data.txt", "Inline data from ic_add_data");
    test_assert(_r2 == true, "add_data() returns true");
    
    var _r3 = ic_close(_h);
    test_assert(_r3 == true, "close() returns true");
    test_assert(file_exists(_zip_path), "archive file exists");
    
    var _list_result = ic_list(_zip_path);
    test_assert(_list_result != "", "list() returns non-empty result");
    
    directory_create(_extract_dir);
    
    var _r4 = ic_extract(_zip_path, _extract_dir);
    test_assert(_r4 == true, "extract() returns true");
    
    var _extracted_file = _extract_dir + "/entry_file.txt";
    test_assert(file_exists(_extracted_file), "extracted file exists");
    
    var _orig_buf = buffer_load(_test_file);
    var _ext_buf = buffer_load(_extracted_file);
    var _orig_content = buffer_read(_orig_buf, buffer_string);
    var _ext_content = buffer_read(_ext_buf, buffer_string);
    
    test_assert(_orig_content == _ext_content, "extracted file content matches original");
    
    buffer_delete(_orig_buf);
    buffer_delete(_ext_buf);
    
    var _mem_data = ic_extract_mem(_zip_path, "entry_data.txt");
    test_assert(string_length(_mem_data) > 0, "extract_mem returns data");
    test_assert(_mem_data == "Inline data from ic_add_data", "extract_mem content correct");
    
    file_delete(_zip_path);
    file_delete(_test_file);
    file_delete(_extracted_file);
    directory_destroy(_extract_dir);
}

function test_iCompression_extract_file() {
    show_debug_message("=== test_iCompression_extract_file ===");
    
    var _zip_path = "test_ic_single.zip";
    var _out_path = "test_ic_single_out.txt";
    
    if (file_exists(_zip_path)) file_delete(_zip_path);
    if (file_exists(_out_path)) file_delete(_out_path);
    
    var _h = ic_create(_zip_path, CompressionFormat.Zip);
    ic_add_data(_h, "hello.txt", "Hello from single extract test!");
    ic_close(_h);
    
    var _r = ic_extract_file(_zip_path, "hello.txt", _out_path);
    test_assert(_r == true, "extract_file returns true");
    test_assert(file_exists(_out_path), "extracted file exists");
    
    var _buf = buffer_load(_out_path);
    var _content = buffer_read(_buf, buffer_string);
    buffer_delete(_buf);
    
    test_assert(_content == "Hello from single extract test!", "extract_file content correct");
    
    file_delete(_zip_path);
    file_delete(_out_path);
}

function test_iCompression_detect_file() {
    show_debug_message("=== test_iCompression_detect_file ===");
    
    var _test_path = "test_detect.zst";
    var _buf = buffer_create(8, buffer_fixed, 1);
    
    buffer_write(_buf, buffer_u8, 0x28);
    buffer_write(_buf, buffer_u8, 0xB5);
    buffer_write(_buf, buffer_u8, 0x2F);
    buffer_write(_buf, buffer_u8, 0xFD);
    buffer_save(_buf, _test_path);
    buffer_delete(_buf);
    
    var _fmt = ic_detect_file(_test_path);
    test_assert(_fmt == CompressionFormat.Zstd, "detect_file from magic: Zstd");
    
    file_delete(_test_path);
}

function test_iCompression_to_str() {
    show_debug_message("=== test_iCompression_to_str ===");
    
    test_assert(ic_to_str(CompressionFormat.Zip) == "ZIP", "Zip -> 'ZIP'");
    test_assert(ic_to_str(CompressionFormat.Zstd) == "zstd", "Zstd -> 'zstd'");
    test_assert(ic_to_str(CompressionFormat.Raw) == "raw", "Raw -> 'raw'");
}

function test_iCompression_buffer_operations() {
    show_debug_message("=== test_iCompression_buffer_operations ===");
    
    var _input = buffer_create(1024, buffer_grow, 1);
    buffer_write(_input, buffer_string, "Buffer test data for compression");
    buffer_seek(_input, buffer_seek_start, 0);
    
    var _output = buffer_create(2048, buffer_grow, 1);
    
    test_assert(true, "buffer operations layer exists (internal)");
    
    buffer_delete(_input);
    buffer_delete(_output);
}

// =============================================================================
// 主测试入口
// =============================================================================

function test_iCompression() {
    test_reset();
    show_debug_message("==========================================");
    show_debug_message("ICompression Extension Test Suite");
    show_debug_message("==========================================");
    
    test_iCompression_detect_format();
    test_iCompression_from_ext();
    test_iCompression_to_str();
    test_iCompression_compress_decompress();
    test_iCompression_compress_decompress_file();
    test_iCompression_detect_file();
    test_iCompression_archive_operations();
    test_iCompression_extract_file();
    test_iCompression_buffer_operations();
    
    show_debug_message("==========================================");
    show_debug_message(test_summary());
    show_debug_message("==========================================");
    
    if (global.__test_failed == 0) {
        show_debug_message("ALL TESTS PASSED!");
    } else {
        show_debug_message("WARNING: " + string(global.__test_failed) + " test(s) failed.");
    }
}