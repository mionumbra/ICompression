// =============================================================================
// ICompression  -  minimal crash isolation
// =============================================================================

function debug_step(_name)
{
    show_debug_message($"STEP: {_name}");
}

// ic_detect takes a buffer holding the candidate bytes (see api.gmidl).
function __diagnostics_detect_bytes(_bytes)
{
    var _buffer = buffer_create(array_length(_bytes), buffer_fixed, 1);
    for (var _index = 0; _index < array_length(_bytes); ++_index)
    {
        buffer_write(_buffer, buffer_u8, _bytes[_index]);
    }
    var _result = ic_detect(_buffer);
    buffer_delete(_buffer);
    return _result;
}

function run_diagnostics()
{
    show_debug_message("");
    show_debug_message("========== DIAGNOSTICS ==========");

    // 1. Test ic_to_str (no buffers involved)
    debug_step("1 ic_to_str with CompressionFormat.Zip");
    var _r1 = ic_to_str(CompressionFormat.Zip);
    show_debug_message($"  result = '{_r1}'  byte_len={string_byte_length(_r1)}");

    debug_step("2 ic_to_str with CompressionFormat.SevenZ");
    var _r2 = ic_to_str(CompressionFormat.SevenZ);
    show_debug_message($"  result = '{_r2}'  byte_len={string_byte_length(_r2)}");

    // 2. Test ic_detect with magic bytes supplied in a buffer
    debug_step("3 ic_detect plain ASCII");
    var _r3 = __diagnostics_detect_bytes([104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100]); // "hello world"
    show_debug_message($"  result = {_r3} (expected Raw={CompressionFormat.Raw})");

    debug_step("4 ic_detect gzip magic bytes");
    var _r4 = __diagnostics_detect_bytes([0x1F, 0x8B, 0x08, 0x00]);
    show_debug_message($"  result = {_r4} (expected Gzip={CompressionFormat.Gzip})");

    debug_step("5 ic_detect zip magic bytes");
    var _r5 = __diagnostics_detect_bytes([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00]);
    show_debug_message($"  result = {_r5} (expected Zip={CompressionFormat.Zip})");

    // 3. Test ic_compress / ic_decompress (string stream APIs)
    debug_step("6 ic_compress gzip");
    var _r6 = ic_compress("hello", CompressionFormat.Gzip, CompressionLevel.Default);
    show_debug_message($"  compressed byte_len = {string_byte_length(_r6)}");

    debug_step("7 ic_decompress gzip");
    var _r7 = ic_decompress(_r6, CompressionFormat.Gzip);
    show_debug_message($"  decompressed = '{_r7}'");

    // 4. Test ic_from_ext (no buffer)
    debug_step("8 ic_from_ext");
    var _r8 = ic_from_ext("test.zip");
    show_debug_message($"  result = {_r8} (expected Zip={CompressionFormat.Zip})");

    show_debug_message("========== DIAGNOSTICS DONE ==========");
}
