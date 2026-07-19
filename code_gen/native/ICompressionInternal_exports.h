// ##### extgen :: Auto-generated file do not edit!! #####

#pragma once
#include "core/GMExtUtils.h"

// Internal function used for queueing buffers to native code
GMEXPORT double __EXT_NATIVE__ICompression_queue_buffer(char* __arg_buffer, double __arg_buffer_length);

GMEXPORT char* __EXT_NATIVE__ic_compress(char* __arg_buffer, double __arg_buffer_length);
GMEXPORT char* __EXT_NATIVE__ic_decompress(char* __arg_buffer, double __arg_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_compress_file(char* __arg_buffer, double __arg_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_decompress_file(char* __arg_buffer, double __arg_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_compress_buf(char* __arg_buffer, double __arg_buffer_length, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_decompress_buf(char* __arg_buffer, double __arg_buffer_length, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_list(char* archive, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_extract(char* archive, char* output_dir, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_extract_file(char* archive, char* entry, char* output);
GMEXPORT char* __EXT_NATIVE__ic_extract_mem(char* archive, char* entry);
GMEXPORT double __EXT_NATIVE__ic_create(char* __arg_buffer, double __arg_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_add_file(double handle, char* path, char* entry);
GMEXPORT double __EXT_NATIVE__ic_add_data(double handle, char* entry, char* data);
GMEXPORT double __EXT_NATIVE__ic_close(double handle);
GMEXPORT double __EXT_NATIVE__ic_detect(char* __arg_buffer, double __arg_buffer_length, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_detect_file(char* path, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT double __EXT_NATIVE__ic_from_ext(char* name, char* __ret_buffer, double __ret_buffer_length);
GMEXPORT char* __EXT_NATIVE__ic_to_str(char* __arg_buffer, double __arg_buffer_length);

