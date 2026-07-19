// =============================================================================
// ICompression  -  minimal crash isolation
// =============================================================================

function debug_step(_name)
{
    show_debug_message($"STEP: {_name}");
}

function run_diagnostics()
{
    show_debug_message("");
    show_debug_message("========== DIAGNOSTICS ==========");

    // 1. Test ic_to_str (uses args buffer, no ret buffer)
    debug_step("1 ic_to_str with integer 0");
    var _r1 = ic_to_str(0);
    show_debug_message($"  result = '{_r1}'  byte_len={string_byte_length(_r1)}");

    debug_step("2 ic_to_str with CompressionFormat.Zip");
    var _r2 = ic_to_str(CompressionFormat.Zip);
    show_debug_message($"  result = '{_r2}'  byte_len={string_byte_length(_r2)}");

    debug_step("3 ic_to_str with CompressionFormat.SevenZ");
    var _r3 = ic_to_str(CompressionFormat.SevenZ);
    show_debug_message($"  result = '{_r3}'  byte_len={string_byte_length(_r3)}");

    // 2. Test ic_detect with simple ASCII (no null bytes, uses ret buffer)
    debug_step("4 ic_detect plain ASCII");
    var _r4 = ic_detect("hello world");
    show_debug_message($"  result = {_r4}");

    debug_step("5 ic_detect gzip magic bytes");
    var _gzip = chr(0x1F) + chr(0x8B) + chr(0x08) + chr(0x00);
    show_debug_message($"  gzip byte_len = {string_byte_length(_gzip)}");
    show_debug_message($"  gzip str_len  = {string_length(_gzip)}");

    var _r5 = ic_detect(_gzip);
    show_debug_message($"  result = {_r5} (expected Gzip={CompressionFormat.Gzip})");

    debug_step("6 ic_detect zip magic bytes");
    var _zip = chr(0x50) + chr(0x4B) + chr(0x03) + chr(0x04) + "padding";
    var _r6 = ic_detect(_zip);
    show_debug_message($"  result = {_r6} (expected Zip={CompressionFormat.Zip})");

    // 3. Test ic_compress / ic_decompress (needs both args+ret buffers)
    debug_step("7 ic_compress gzip");
    var _r7 = ic_compress("hello", CompressionFormat.Gzip, CompressionLevel.Default);
    show_debug_message($"  compressed byte_len = {string_byte_length(_r7)}");

    debug_step("8 ic_decompress gzip");
    var _r8 = ic_decompress(_r7, CompressionFormat.Gzip);
    show_debug_message($"  decompressed = '{_r8}'");

    // 4. Test ic_from_ext (no buffer)
    debug_step("9 ic_from_ext");
    var _r9 = ic_from_ext("test.zip");
    show_debug_message($"  result = {_r9} (expected Zip={CompressionFormat.Zip})");

    show_debug_message("========== DIAGNOSTICS DONE ==========");
};