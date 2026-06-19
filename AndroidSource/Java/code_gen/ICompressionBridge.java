package com.gamemaker.ExtensionCore.ExtBridge;
import java.lang.String;
import java.nio.ByteBuffer;
import ${YYAndroidPackageName}.GMExtUtils;

public final class ICompressionBridge {
    static {
        // this is the extension lib name
        System.loadLibrary("ICompression");
        nativeRegister();
    }
    // this registers the native functions on the C++ layer
    private static native void nativeRegister();

    public static String __EXT_JAVA__GetExtensionOption(String extName, String optName)
    {
        return GMExtUtils.GetExtensionOption(extName, optName);
    }

    public static native double __EXT_JNI__ICompression_queue_buffer(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native String __EXT_JNI__ic_compress(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native String __EXT_JNI__ic_decompress(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native double __EXT_JNI__ic_compress_file(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native double __EXT_JNI__ic_decompress_file(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native double __EXT_JNI__ic_compress_buf(ByteBuffer __arg_buffer, double __arg_buffer_length, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_decompress_buf(ByteBuffer __arg_buffer, double __arg_buffer_length, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_list(String archive, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_extract(String archive, String output_dir, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_extract_file(String archive, String entry, String output);
    public static native String __EXT_JNI__ic_extract_mem(String archive, String entry);
    public static native double __EXT_JNI__ic_create(ByteBuffer __arg_buffer, double __arg_buffer_length);
    public static native double __EXT_JNI__ic_add_file(double handle, String path, String entry);
    public static native double __EXT_JNI__ic_add_data(double handle, String entry, String data);
    public static native double __EXT_JNI__ic_close(double handle);
    public static native double __EXT_JNI__ic_detect(String data, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_detect_file(String path, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native double __EXT_JNI__ic_from_ext(String name, ByteBuffer __ret_buffer, double __ret_buffer_length);
    public static native String __EXT_JNI__ic_to_str(ByteBuffer __arg_buffer, double __arg_buffer_length);
}