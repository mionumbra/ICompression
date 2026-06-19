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
    _dir = working_directory + "\\" + _dir;
    return _dir;
}

function __test_cleanup_dir(_dir)
{
    if (directory_exists(_dir)) directory_destroy(_dir);
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

    show_debug_message("[OK] test_to_str");
    return true;
}

// =============================================================================
// TEST: ic_detect (magic bytes)
// =============================================================================

function test_detect_magic()
{
    show_debug_message("--- test_detect_magic ---");

    var _gzip = chr(0x1F) + chr(0x8B) + chr(0x08) + chr(0x00);
    if (ic_detect(_gzip) != CompressionFormat.Gzip) { show_debug_message("[FAIL] detect gzip magic"); return false; }

    var _zip = chr(0x50) + chr(0x4B) + chr(0x03) + chr(0x04) + "padding...";
    if (ic_detect(_zip) != CompressionFormat.Zip) { show_debug_message("[FAIL] detect zip magic"); return false; }

    var _7z = chr(0x37) + chr(0x7A) + chr(0xBC) + chr(0xAF) + chr(0x27) + chr(0x1C) + "extra";
    if (ic_detect(_7z) != CompressionFormat.SevenZ) { show_debug_message("[FAIL] detect 7z magic"); return false; }

    var _xz = chr(0xFD) + chr(0x37) + chr(0x7A) + chr(0x58) + chr(0x5A) + chr(0x00) + "padding";
    if (ic_detect(_xz) != CompressionFormat.Xz) { show_debug_message("[FAIL] detect xz magic"); return false; }

    var _zstd = chr(0x28) + chr(0xB5) + chr(0x2F) + chr(0xFD) + "more";
    if (ic_detect(_zstd) != CompressionFormat.Zstd) { show_debug_message("[FAIL] detect zstd magic"); return false; }

    var _lz4 = chr(0x04) + chr(0x22) + chr(0x4D) + chr(0x18) + "stuff";
    if (ic_detect(_lz4) != CompressionFormat.Lz4) { show_debug_message("[FAIL] detect lz4 magic"); return false; }

    if (ic_detect("hello world") != CompressionFormat.Raw) { show_debug_message("[FAIL] detect raw (random)"); return false; }

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
    if (ic_from_ext("file.gz") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .gz"); return false; }
    if (ic_from_ext("file.gzip") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .gzip"); return false; }
    if (ic_from_ext("file.tar.gz") != CompressionFormat.Gzip) { show_debug_message("[FAIL] ext .tar.gz -> gzip"); return false; }
    if (ic_from_ext("data.zst") != CompressionFormat.Zstd) { show_debug_message("[FAIL] ext .zst"); return false; }
    if (ic_from_ext("data.zstd") != CompressionFormat.Zstd) { show_debug_message("[FAIL] ext .zstd"); return false; }
    if (ic_from_ext("dump.lz4") != CompressionFormat.Lz4) { show_debug_message("[FAIL] ext .lz4"); return false; }
    if (ic_from_ext("data.xz") != CompressionFormat.Xz) { show_debug_message("[FAIL] ext .xz"); return false; }
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

    var _formats = [CompressionFormat.Gzip, CompressionFormat.Zstd, CompressionFormat.Lz4, CompressionFormat.Xz];

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

    var _original_path = _dir + "\original.txt";
    var _compressed_path = _dir + "\compressed.zst";
    var _decompressed_path = _dir + "\restored.txt";

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

    var _in_buf = buffer_create(string_byte_length(_data) + 1, buffer_fixed, 1);
    buffer_write(_in_buf, buffer_string, _data);

    var _out_buf = buffer_create(65536, buffer_fixed, 1);

    var _result = ic_compress_buf(_in_buf, _out_buf, CompressionFormat.Gzip, CompressionLevel.Default);
    if (_result == undefined) { show_debug_message("[FAIL] compress_buf returned undefined"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (!_result.success) { show_debug_message("[FAIL] compress_buf success"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.original_size != string_byte_length(_data)) { show_debug_message("[FAIL] compress_buf original_size"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.compressed_size <= 0) { show_debug_message("[FAIL] compress_buf compressed_size > 0"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }
    if (_result.format != CompressionFormat.Gzip) { show_debug_message("[FAIL] compress_buf format"); buffer_delete(_in_buf); buffer_delete(_out_buf); return false; }

    var _decomp_buf = buffer_create(65536, buffer_fixed, 1);
    var _dec_result = ic_decompress_buf(_out_buf, _decomp_buf, CompressionFormat.Gzip);
    if (_dec_result == undefined) { show_debug_message("[FAIL] decompress_buf returned undefined"); buffer_delete(_in_buf); buffer_delete(_out_buf); buffer_delete(_decomp_buf); return false; }
    if (!_dec_result.success) { show_debug_message("[FAIL] decompress_buf success"); buffer_delete(_in_buf); buffer_delete(_out_buf); buffer_delete(_decomp_buf); return false; }

    buffer_seek(_decomp_buf, buffer_seek_start, 0);
    var _restored = buffer_read(_decomp_buf, buffer_string);
    if (_restored != _data) { show_debug_message("[FAIL] buffer round-trip content match"); buffer_delete(_in_buf); buffer_delete(_out_buf); buffer_delete(_decomp_buf); return false; }

    buffer_delete(_in_buf);
    buffer_delete(_out_buf);
    buffer_delete(_decomp_buf);

    show_debug_message("[OK] test_buffer_compress_decompress");
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
    var _archive_path = _dir + "\test_archive.zip";

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
    var _archive_path = _dir + "\extract_test.zip";
    var _extract_dir = _dir + "\extracted";

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

    if (!file_exists(_extract_dir + "\a.txt")) { show_debug_message("[FAIL] extracted a.txt exists"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_extract_dir + "\sub\b.txt")) { show_debug_message("[FAIL] extracted sub/b.txt exists"); __test_cleanup_dir(_dir); return false; }
    if (!file_exists(_extract_dir + "\sub\c.txt")) { show_debug_message("[FAIL] extracted sub/c.txt exists"); __test_cleanup_dir(_dir); return false; }

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
    var _archive_path = _dir + "\single_test.zip";
    var _output_path = _dir + "\rescued.txt";

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

    var _src_path = _dir + "\source.dat";
    var _archive_path = _dir + "\archive.zip";

    var _data = "Binary content " + chr(0) + chr(1) + chr(2) + chr(3) + chr(4) + chr(5) + " end";
    var _buf = buffer_create(string_byte_length(_data), buffer_fixed, 1);
    buffer_write(_buf, buffer_string, _data);
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
    var _archive_path = _dir + "\test.tar";

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
    if (_comp_empty == undefined) { show_debug_message("[FAIL] compress empty string"); return false; }
    if (ic_decompress(_comp_empty, CompressionFormat.Gzip) != "") { show_debug_message("[FAIL] decompress empty round-trip"); return false; }

    if (ic_compress("X", CompressionFormat.Gzip, CompressionLevel.Default) == "") { show_debug_message("[FAIL] compress single byte"); return false; }
    if (ic_decompress(ic_compress("X", CompressionFormat.Gzip, CompressionLevel.Default), CompressionFormat.Gzip) != "X") { show_debug_message("[FAIL] round-trip single byte"); return false; }

    var _big = "";
    repeat (1000) { _big += "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; }
    var _comp_big = ic_compress(_big, CompressionFormat.Zstd, CompressionLevel.Default);
    if (_comp_big == "") { show_debug_message("[FAIL] compress large data"); return false; }
    if (string_length(_comp_big) >= string_length(_big)) { show_debug_message("[FAIL] large data actually compressed"); return false; }
    if (ic_decompress(_comp_big, CompressionFormat.Zstd) != _big) { show_debug_message("[FAIL] large data round-trip"); return false; }

    var _bin_data = chr(0) + chr(1) + chr(2) + chr(254) + chr(255) + "hello" + chr(0) + "world";
    var _comp_bin = ic_compress(_bin_data, CompressionFormat.Gzip, CompressionLevel.Default);
    var _dec_bin = ic_decompress(_comp_bin, CompressionFormat.Gzip);
    if (string_byte_length(_dec_bin) != string_byte_length(_bin_data)) { show_debug_message("[FAIL] binary data length match"); return false; }
    if (_dec_bin != _bin_data) { show_debug_message("[FAIL] binary data round-trip"); return false; }

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

    var _path1 = _dir + "\archive1.zip";
    var _path2 = _dir + "\archive2.zip";

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

    var _gzip_path = _dir + "\test.gz";
    var _compressed = ic_compress("detect me", CompressionFormat.Gzip, CompressionLevel.Default);
    var _buf = buffer_create(string_byte_length(_compressed), buffer_fixed, 1);
    buffer_write(_buf, buffer_string, _compressed);
    buffer_save(_buf, _gzip_path);
    buffer_delete(_buf);

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
    var _archive_path = _dir + "\test.7z";

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
    ];

    for (var _i = 0; _i < array_length(_tests); _i++)
    {
        _total++;
        if (_tests[_i]()) _passed++;
    }

    __test_summary(_total, _passed);
}
