# libarchive 3.8.8 (24d992722659c529700143e3087dee6454addecd): an empty
# LZ4 stream must initialize its descriptor and checksum before close.
if(NOT DEFINED LIBARCHIVE_SOURCE_DIR)
  message(FATAL_ERROR "LIBARCHIVE_SOURCE_DIR is required")
endif()

set(_source "${LIBARCHIVE_SOURCE_DIR}/libarchive/archive_write_add_filter_lz4.c")
if(NOT EXISTS "${_source}")
  message(FATAL_ERROR "libarchive LZ4 source does not exist: ${_source}")
endif()
file(READ "${_source}" _content)

set(_original [=[archive_filter_lz4_close(struct archive_write_filter *f)
{
	struct private_data *data = (struct private_data *)f->data;
	int ret;

	/* Finish compression cycle. */]=])
set(_patched [=[archive_filter_lz4_close(struct archive_write_filter *f)
{
	struct private_data *data = (struct private_data *)f->data;
	int ret;

	/* Empty streams still need a descriptor and checksum state. */
	if (!data->header_written) {
		ret = lz4_write_stream_descriptor(f);
		if (ret != ARCHIVE_OK)
			return (ret);
		data->header_written = 1;
	}

	/* Finish compression cycle. */]=])

string(FIND "${_content}" "${_original}" _original_first)
string(FIND "${_content}" "${_original}" _original_last REVERSE)
string(FIND "${_content}" "${_patched}" _patched_first)
string(FIND "${_content}" "${_patched}" _patched_last REVERSE)

if(_patched_first GREATER_EQUAL 0 AND
   _patched_first EQUAL _patched_last AND _original_first EQUAL -1)
  message(STATUS "libarchive LZ4 empty-stream patch already applied")
elseif(_original_first GREATER_EQUAL 0 AND
       _original_first EQUAL _original_last AND _patched_first EQUAL -1)
  string(REPLACE "${_original}" "${_patched}" _content "${_content}")
  file(WRITE "${_source}" "${_content}")
  message(STATUS "Applied libarchive LZ4 empty-stream patch")
else()
  message(FATAL_ERROR
    "Unexpected libarchive LZ4 source; review the empty-stream patch before updating the dependency")
endif()
