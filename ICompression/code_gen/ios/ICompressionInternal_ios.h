// ##### extgen :: Auto-generated file do not edit!! #####

#import <Foundation/Foundation.h>

@interface ICompressionInternal : NSObject
- (char*)__EXT_NATIVE__ic_compress:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (char*)__EXT_NATIVE__ic_decompress:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (double)__EXT_NATIVE__ic_compress_file:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (double)__EXT_NATIVE__ic_decompress_file:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (double)__EXT_NATIVE__ic_compress_buf:(char*)__arg_buffer arg1:(double)__arg_buffer_length arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_decompress_buf:(char*)__arg_buffer arg1:(double)__arg_buffer_length arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_list:(char*)archive arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_extract:(char*)archive arg1:(char*)output_dir arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_extract_file:(char*)archive arg1:(char*)entry arg2:(char*)output;
- (char*)__EXT_NATIVE__ic_extract_mem:(char*)archive arg1:(char*)entry;
- (double)__EXT_NATIVE__ic_create:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (double)__EXT_NATIVE__ic_add_file:(double)handle arg1:(char*)path arg2:(char*)entry;
- (double)__EXT_NATIVE__ic_add_data:(double)handle arg1:(char*)entry arg2:(char*)data;
- (double)__EXT_NATIVE__ic_close:(double)handle;
- (double)__EXT_NATIVE__ic_detect:(char*)data arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_detect_file:(char*)path arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length;
- (double)__EXT_NATIVE__ic_from_ext:(char*)name arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length;
- (char*)__EXT_NATIVE__ic_to_str:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
- (double)__EXT_NATIVE__ICompression_queue_buffer:(char*)__arg_buffer arg1:(double)__arg_buffer_length;
@end

