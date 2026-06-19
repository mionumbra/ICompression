{
  "resourceType": "GMExtensionConfig",
  "resourceVersion": "2.0",
  "name": "ICompression",
  "version": "1.0.0.0",
  "files": [
    {
      "fileName": "ICompression",
      "filePath": "ICompression.dll",
      "init": -1,
      "final": -1,
      "kind": "DLL",
      "os": "Windows",
      "options": []
    },
    {
      "fileName": "ICompression",
      "filePath": "libICompression.dylib",
      "init": -1,
      "final": -1,
      "kind": "DYLIB",
      "os": "macOS",
      "options": []
    },
    {
      "fileName": "ICompression",
      "filePath": "libICompression.so",
      "init": -1,
      "final": -1,
      "kind": "DYLIB",
      "os": "Linux",
      "options": []
    }
  ],
  "functions": [
    {
      "name": "ic_compress",
      "externalName": "__EXT_NATIVE__ic_compress",
      "help": "Compress a string using the specified format and level",
      "returnType": "String",
      "args": [
        { "type": "String", "name": "data", "description": "Data to compress" },
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" },
        { "type": "Double", "name": "level", "description": "CompressionLevel enum" }
      ]
    },
    {
      "name": "ic_decompress",
      "externalName": "__EXT_NATIVE__ic_decompress",
      "help": "Decompress a string using the specified format",
      "returnType": "String",
      "args": [
        { "type": "String", "name": "data", "description": "Data to decompress" },
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" }
      ]
    },
    {
      "name": "ic_compress_file",
      "externalName": "__EXT_NATIVE__ic_compress_file",
      "help": "Compress a file",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "src", "description": "Source file path" },
        { "type": "String", "name": "dst", "description": "Destination file path" },
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" },
        { "type": "Double", "name": "level", "description": "CompressionLevel enum" }
      ]
    },
    {
      "name": "ic_decompress_file",
      "externalName": "__EXT_NATIVE__ic_decompress_file",
      "help": "Decompress a file",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "src", "description": "Source file path" },
        { "type": "String", "name": "dst", "description": "Destination file path" },
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" }
      ]
    },
    {
      "name": "ic_compress_buf",
      "externalName": "__EXT_NATIVE__ic_compress_buf",
      "help": "Compress a buffer",
      "returnType": "Real",
      "args": [
        { "type": "Double", "name": "input", "description": "Input buffer address" },
        { "type": "Double", "name": "input_length", "description": "Input buffer length" },
        { "type": "Double", "name": "output", "description": "Output buffer address" },
        { "type": "Double", "name": "output_length", "description": "Output buffer length" }
      ],
      "private": true
    },
    {
      "name": "ic_decompress_buf",
      "externalName": "__EXT_NATIVE__ic_decompress_buf",
      "help": "Decompress a buffer",
      "returnType": "Real",
      "args": [
        { "type": "Double", "name": "input", "description": "Input buffer address" },
        { "type": "Double", "name": "input_length", "description": "Input buffer length" },
        { "type": "Double", "name": "output", "description": "Output buffer address" },
        { "type": "Double", "name": "output_length", "description": "Output buffer length" }
      ],
      "private": true
    },
    {
      "name": "ic_list",
      "externalName": "__EXT_NATIVE__ic_list",
      "help": "List entries in an archive",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "archive", "description": "Archive file path" },
        { "type": "Double", "name": "ret_buffer", "description": "Return buffer address" },
        { "type": "Double", "name": "ret_size", "description": "Return buffer size" }
      ],
      "private": true
    },
    {
      "name": "ic_extract",
      "externalName": "__EXT_NATIVE__ic_extract",
      "help": "Extract all files from an archive to a directory",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "archive", "description": "Archive file path" },
        { "type": "String", "name": "output_dir", "description": "Output directory" },
        { "type": "Double", "name": "ret_buffer", "description": "Return buffer address" },
        { "type": "Double", "name": "ret_size", "description": "Return buffer size" }
      ],
      "private": true
    },
    {
      "name": "ic_extract_file",
      "externalName": "__EXT_NATIVE__ic_extract_file",
      "help": "Extract a single file from an archive",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "archive", "description": "Archive file path" },
        { "type": "String", "name": "entry", "description": "Entry name within archive" },
        { "type": "String", "name": "output", "description": "Output file path" }
      ]
    },
    {
      "name": "ic_extract_mem",
      "externalName": "__EXT_NATIVE__ic_extract_mem",
      "help": "Extract a file from archive to memory",
      "returnType": "String",
      "args": [
        { "type": "String", "name": "archive", "description": "Archive file path" },
        { "type": "String", "name": "entry", "description": "Entry name within archive" }
      ]
    },
    {
      "name": "ic_create",
      "externalName": "__EXT_NATIVE__ic_create",
      "help": "Create a new archive file",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "archive", "description": "Output archive path" },
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" }
      ]
    },
    {
      "name": "ic_add_file",
      "externalName": "__EXT_NATIVE__ic_add_file",
      "help": "Add a file to the archive",
      "returnType": "Real",
      "args": [
        { "type": "Double", "name": "handle", "description": "Archive handle" },
        { "type": "String", "name": "path", "description": "Source file path" },
        { "type": "String", "name": "entry", "description": "Entry name in archive" }
      ]
    },
    {
      "name": "ic_add_data",
      "externalName": "__EXT_NATIVE__ic_add_data",
      "help": "Add data to the archive",
      "returnType": "Real",
      "args": [
        { "type": "Double", "name": "handle", "description": "Archive handle" },
        { "type": "String", "name": "entry", "description": "Entry name in archive" },
        { "type": "String", "name": "data", "description": "Data to add" }
      ]
    },
    {
      "name": "ic_close",
      "externalName": "__EXT_NATIVE__ic_close",
      "help": "Close the archive and finalize it",
      "returnType": "Real",
      "args": [
        { "type": "Double", "name": "handle", "description": "Archive handle" }
      ]
    },
    {
      "name": "ic_detect",
      "externalName": "__EXT_NATIVE__ic_detect",
      "help": "Detect compression format from data",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "data", "description": "Data bytes" },
        { "type": "Double", "name": "ret_buffer", "description": "Return buffer address" },
        { "type": "Double", "name": "ret_size", "description": "Return buffer size" }
      ],
      "private": true
    },
    {
      "name": "ic_detect_file",
      "externalName": "__EXT_NATIVE__ic_detect_file",
      "help": "Detect compression format from file",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "path", "description": "File path" },
        { "type": "Double", "name": "ret_buffer", "description": "Return buffer address" },
        { "type": "Double", "name": "ret_size", "description": "Return buffer size" }
      ],
      "private": true
    },
    {
      "name": "ic_from_ext",
      "externalName": "__EXT_NATIVE__ic_from_ext",
      "help": "Detect compression format from file extension",
      "returnType": "Real",
      "args": [
        { "type": "String", "name": "name", "description": "Filename" },
        { "type": "Double", "name": "ret_buffer", "description": "Return buffer address" },
        { "type": "Double", "name": "ret_size", "description": "Return buffer size" }
      ],
      "private": true
    },
    {
      "name": "ic_to_str",
      "externalName": "__EXT_NATIVE__ic_to_str",
      "help": "Convert compression format to string",
      "returnType": "String",
      "args": [
        { "type": "Double", "name": "format", "description": "CompressionFormat enum" }
      ]
    }
  ],
  "constants": [
    {
      "name": "CompressionFormat",
      "value": "0",
      "kind": "EnumKind",
      "description": "Enum: CompressionFormat - Zip=0, SevenZ=1, Gzip=2, Zstd=3, Lz4=4, Xz=5, Tar=6, Raw=7"
    },
    {
      "name": "CompressionLevel",
      "value": "0",
      "kind": "EnumKind",
      "description": "Enum: CompressionLevel - Fastest=0, Default=1, Optimal=2"
    }
  ],
  "resources": [],
  "iOS": {
    "infoPlist": ""
  },
  "Android": {
    "AndroidPermissions": [],
    "AndroidClasses": [],
    "AndroidPermissionsAuto": []
  }
}