package ${YYAndroidPackageName};
import static com.gamemaker.ExtensionCore.ExtBridge.ICompressionBridge.*;
import java.lang.String;
import java.nio.ByteBuffer;

public class ICompressionInternal extends RunnerSocial {
    public double __EXT_NATIVE__ICompression_queue_buffer(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ICompression_queue_buffer(__arg_buffer, __arg_buffer_length);
    }
    public String __EXT_NATIVE__ic_compress(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_compress(__arg_buffer, __arg_buffer_length);
    }
    public String __EXT_NATIVE__ic_decompress(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_decompress(__arg_buffer, __arg_buffer_length);
    }
    public double __EXT_NATIVE__ic_compress_file(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_compress_file(__arg_buffer, __arg_buffer_length);
    }
    public double __EXT_NATIVE__ic_decompress_file(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_decompress_file(__arg_buffer, __arg_buffer_length);
    }
    public double __EXT_NATIVE__ic_compress_buf(ByteBuffer __arg_buffer, double __arg_buffer_length, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_compress_buf(__arg_buffer, __arg_buffer_length, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_decompress_buf(ByteBuffer __arg_buffer, double __arg_buffer_length, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_decompress_buf(__arg_buffer, __arg_buffer_length, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_list(String archive, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_list(archive, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_extract(String archive, String output_dir, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_extract(archive, output_dir, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_extract_file(String archive, String entry, String output)
    {
        return __EXT_JNI__ic_extract_file(archive, entry, output);
    }
    public String __EXT_NATIVE__ic_extract_mem(String archive, String entry)
    {
        return __EXT_JNI__ic_extract_mem(archive, entry);
    }
    public double __EXT_NATIVE__ic_create(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_create(__arg_buffer, __arg_buffer_length);
    }
    public double __EXT_NATIVE__ic_add_file(double handle, String path, String entry)
    {
        return __EXT_JNI__ic_add_file(handle, path, entry);
    }
    public double __EXT_NATIVE__ic_add_data(double handle, String entry, String data)
    {
        return __EXT_JNI__ic_add_data(handle, entry, data);
    }
    public double __EXT_NATIVE__ic_close(double handle)
    {
        return __EXT_JNI__ic_close(handle);
    }
    public double __EXT_NATIVE__ic_detect(String data, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_detect(data, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_detect_file(String path, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_detect_file(path, __ret_buffer, __ret_buffer_length);
    }
    public double __EXT_NATIVE__ic_from_ext(String name, ByteBuffer __ret_buffer, double __ret_buffer_length)
    {
        return __EXT_JNI__ic_from_ext(name, __ret_buffer, __ret_buffer_length);
    }
    public String __EXT_NATIVE__ic_to_str(ByteBuffer __arg_buffer, double __arg_buffer_length)
    {
        return __EXT_JNI__ic_to_str(__arg_buffer, __arg_buffer_length);
    }
}