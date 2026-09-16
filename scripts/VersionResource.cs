// Updates an unsigned temporary DLL after a successful link. The caller owns
// atomic publication of the DLL and of its build counter.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace ICompressionBuild
{
    public static class VersionResource
    {
        private static readonly IntPtr VersionType = new IntPtr(16);
        private static readonly IntPtr VersionName = new IntPtr(1);
        private static readonly Encoding Utf16 = new UnicodeEncoding(false, false, true);

        private sealed class Node
        {
            internal ushort Type;
            internal string Key;
            internal byte[] Value;
            internal readonly List<Node> Children = new List<Node>();
        }

        private sealed class Resource
        {
            internal ushort Language;
            internal byte[] Data;
        }

        public static void Stamp(string dllPath, string version)
        {
            if (String.IsNullOrWhiteSpace(dllPath))
                throw new ArgumentException("A DLL path is required.", "dllPath");
            ushort[] parts = ParseVersion(version);
            string path = Path.GetFullPath(dllPath);
            RejectSignedImage(path);

            List<Resource> resources = ReadResources(path);
            foreach (Resource resource in resources)
            {
                int end;
                Node root = ParseNode(resource.Data, 0, resource.Data.Length, 0, out end);
                RequireZeroPadding(resource.Data, end, resource.Data.Length);
                if (root.Key != "VS_VERSION_INFO" || root.Type != 0 ||
                    root.Value.Length < 52 || ReadUInt32(root.Value, 0) != 0xFEEF04BDu)
                    throw new InvalidDataException("The DLL has an invalid VS_FIXEDFILEINFO resource.");

                uint ms = ((uint)parts[0] << 16) | parts[1];
                uint ls = ((uint)parts[2] << 16) | parts[3];
                SetUInt32(root.Value, 8, ms);
                SetUInt32(root.Value, 12, ls);
                SetUInt32(root.Value, 16, ms);
                SetUInt32(root.Value, 20, ls);
                UpdateVersionStrings(root, version);
                resource.Data = Serialize(root);
            }

            IntPtr update = BeginUpdateResourceW(path, false);
            if (update == IntPtr.Zero)
                throw NativeError("BeginUpdateResourceW");
            try
            {
                foreach (Resource resource in resources)
                {
                    if (!UpdateResourceW(update, VersionType, VersionName,
                        resource.Language, resource.Data, (uint)resource.Data.Length))
                        throw NativeError("UpdateResourceW");
                }

                bool committed = EndUpdateResourceW(update, false);
                int commitError = Marshal.GetLastWin32Error();
                // EndUpdateResource closes the update transaction, including
                // when it reports a failure while writing the temporary DLL.
                update = IntPtr.Zero;
                if (!committed)
                    throw NativeError("EndUpdateResourceW", commitError);
            }
            catch (Exception error)
            {
                if (update != IntPtr.Zero)
                {
                    if (!EndUpdateResourceW(update, true))
                        error.Data["ResourceUpdateDiscardError"] = NativeError("EndUpdateResourceW(discard)");
                    update = IntPtr.Zero;
                }
                throw;
            }
        }

        private static ushort[] ParseVersion(string version)
        {
            if (version == null)
                throw new ArgumentNullException("version");
            string[] text = version.Split('.');
            if (text.Length != 4)
                throw new ArgumentException("A version must contain four decimal components.", "version");
            ushort[] values = new ushort[4];
            for (int i = 0; i < text.Length; ++i)
            {
                if (text[i].Length == 0 || text[i].Length > 5 ||
                    (text[i].Length > 1 && text[i][0] == '0') ||
                    !UInt16.TryParse(text[i], NumberStyles.None, CultureInfo.InvariantCulture, out values[i]))
                    throw new ArgumentException("Version components must be canonical decimal integers from 0 to 65535.", "version");
            }
            return values;
        }

        private static void RejectSignedImage(string path)
        {
            // The certificate table is a file offset, not an RVA. Altering
            // VERSIONINFO invalidates Authenticode; signing must happen later.
            byte[] bytes = File.ReadAllBytes(path);
            if (bytes.Length < 64 || ReadUInt16(bytes, 0) != 0x5A4D)
                throw new InvalidDataException("The input is not a PE image.");
            uint peValue = ReadUInt32(bytes, 0x3C);
            if (peValue > (uint)(bytes.Length - 24))
                throw new InvalidDataException("The PE header is truncated.");
            int pe = (int)peValue;
            if (ReadUInt32(bytes, pe) != 0x00004550u)
                throw new InvalidDataException("The PE signature is invalid.");
            int optional = pe + 24;
            int optionalSize = ReadUInt16(bytes, pe + 20);
            if (optionalSize < 2 || optionalSize > bytes.Length - optional)
                throw new InvalidDataException("The PE optional header is truncated.");
            ushort magic = ReadUInt16(bytes, optional);
            int directories;
            int countOffset;
            if (magic == 0x20B) { directories = 112; countOffset = 108; }
            else if (magic == 0x10B) { directories = 96; countOffset = 92; }
            else throw new InvalidDataException("The PE optional header is unsupported.");
            if (optionalSize < countOffset + 4)
                throw new InvalidDataException("The PE data-directory count is missing.");
            uint count = ReadUInt32(bytes, optional + countOffset);
            if (count <= 4) return;
            int certificate = directories + 4 * 8;
            if (optionalSize < certificate + 8)
                throw new InvalidDataException("The PE certificate directory is truncated.");
            if (ReadUInt32(bytes, optional + certificate) != 0 ||
                ReadUInt32(bytes, optional + certificate + 4) != 0)
                throw new InvalidOperationException("Cannot stamp a signed DLL. Stamp the build version before signing.");
        }

        private static List<Resource> ReadResources(string path)
        {
            // LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE: do not
            // load imports or execute DllMain while inspecting the build output.
            IntPtr module = LoadLibraryExW(path, IntPtr.Zero, 0x00000022);
            if (module == IntPtr.Zero)
                throw NativeError("LoadLibraryExW");
            try
            {
                List<Resource> resources = new List<Resource>();
                Exception callbackError = null;
                EnumResourceLanguageProc callback = delegate(IntPtr image, IntPtr type,
                    IntPtr name, ushort language, IntPtr parameter)
                {
                    try
                    {
                        IntPtr info = FindResourceExW(image, type, name, language);
                        if (info == IntPtr.Zero) throw NativeError("FindResourceExW");
                        uint size = SizeofResource(image, info);
                        if (size == 0) throw NativeError("SizeofResource");
                        if (size > Int32.MaxValue)
                            throw new InvalidDataException("The version resource is too large.");
                        IntPtr loaded = LoadResource(image, info);
                        if (loaded == IntPtr.Zero) throw NativeError("LoadResource");
                        IntPtr address = LockResource(loaded);
                        // LockResource does not supply extended error details.
                        if (address == IntPtr.Zero) throw NativeError("LockResource", 13);
                        byte[] data = new byte[(int)size];
                        Marshal.Copy(address, data, 0, data.Length);
                        resources.Add(new Resource { Language = language, Data = data });
                        return true;
                    }
                    catch (Exception error)
                    {
                        callbackError = error;
                        return false;
                    }
                };
                bool enumerated = EnumResourceLanguagesW(module, VersionType, VersionName,
                    callback, IntPtr.Zero);
                int enumerationError = Marshal.GetLastWin32Error();
                GC.KeepAlive(callback);
                if (callbackError != null) throw callbackError;
                if (!enumerated) throw NativeError("EnumResourceLanguagesW", enumerationError);
                if (resources.Count == 0)
                    throw new InvalidDataException("The DLL has no VERSIONINFO resource with ID 1.");
                return resources;
            }
            finally
            {
                // Windows forbids updating resources while this image is mapped.
                if (!FreeLibrary(module)) throw NativeError("FreeLibrary");
            }
        }

        private static Node ParseNode(byte[] data, int start, int limit, int depth, out int end)
        {
            if (depth > 64 || start < 0 || limit > data.Length || limit - start < 6)
                throw new InvalidDataException("The version resource tree is invalid.");
            int length = ReadUInt16(data, start);
            int valueLength = ReadUInt16(data, start + 2);
            ushort type = ReadUInt16(data, start + 4);
            if (length < 6 || length > limit - start || type > 1)
                throw new InvalidDataException("The version resource node has invalid bounds.");
            end = start + length;
            int cursor = start + 6;
            int keyStart = cursor;
            while (cursor + 2 <= end && ReadUInt16(data, cursor) != 0) cursor += 2;
            if (cursor + 2 > end)
                throw new InvalidDataException("The version resource key is unterminated.");
            string key = Utf16.GetString(data, keyStart, cursor - keyStart);
            cursor += 2;
            int aligned = Align4(cursor);
            if (aligned > end)
            {
                if (valueLength != 0 || cursor != end)
                    throw new InvalidDataException("The version resource value is truncated.");
                return new Node { Type = type, Key = key, Value = new byte[0] };
            }
            cursor = aligned;
            int valueBytes = type == 1 ? valueLength * 2 : valueLength;
            if (valueBytes > end - cursor)
                throw new InvalidDataException("The version resource value exceeds its node.");
            byte[] value = new byte[valueBytes];
            Buffer.BlockCopy(data, cursor, value, 0, valueBytes);
            cursor += valueBytes;
            Node node = new Node { Type = type, Key = key, Value = value };
            while (cursor < end)
            {
                aligned = Align4(cursor);
                if (aligned >= end)
                {
                    RequireZeroPadding(data, cursor, end);
                    break;
                }
                RequireZeroPadding(data, cursor, aligned);
                cursor = aligned;
                if (end - cursor < 6 || ReadUInt16(data, cursor) == 0)
                {
                    RequireZeroPadding(data, cursor, end);
                    break;
                }
                int childEnd;
                node.Children.Add(ParseNode(data, cursor, end, depth + 1, out childEnd));
                cursor = childEnd;
            }
            return node;
        }

        private static void UpdateVersionStrings(Node root, string version)
        {
            byte[] text = Utf16.GetBytes(version + "\0");
            foreach (Node section in root.Children)
            {
                if (section.Key != "StringFileInfo") continue;
                foreach (Node table in section.Children)
                {
                    bool fileFound = false;
                    bool productFound = false;
                    foreach (Node field in table.Children)
                    {
                        if (field.Key == "FileVersion" || field.Key == "ProductVersion")
                        {
                            field.Type = 1;
                            field.Value = (byte[])text.Clone();
                            if (field.Key == "FileVersion") fileFound = true;
                            else productFound = true;
                        }
                    }
                    if (!fileFound)
                        table.Children.Add(new Node { Type = 1, Key = "FileVersion", Value = (byte[])text.Clone() });
                    if (!productFound)
                        table.Children.Add(new Node { Type = 1, Key = "ProductVersion", Value = (byte[])text.Clone() });
                }
            }
        }

        private static byte[] Serialize(Node node)
        {
            if (node.Type == 1 && (node.Value.Length & 1) != 0)
                throw new InvalidDataException("A version resource text value has an odd byte length.");
            int valueLength = node.Type == 1 ? node.Value.Length / 2 : node.Value.Length;
            if (valueLength > UInt16.MaxValue)
                throw new InvalidDataException("The version resource value is too long.");
            using (MemoryStream stream = new MemoryStream())
            {
                WriteUInt16(stream, 0);
                WriteUInt16(stream, (ushort)valueLength);
                WriteUInt16(stream, node.Type);
                byte[] key = Utf16.GetBytes(node.Key + "\0");
                stream.Write(key, 0, key.Length);
                Pad4(stream);
                stream.Write(node.Value, 0, node.Value.Length);
                foreach (Node child in node.Children)
                {
                    Pad4(stream);
                    byte[] bytes = Serialize(child);
                    stream.Write(bytes, 0, bytes.Length);
                }
                if (stream.Length > UInt16.MaxValue)
                    throw new InvalidDataException("The version resource node exceeds 65535 bytes.");
                byte[] result = stream.ToArray();
                SetUInt16(result, 0, (ushort)result.Length);
                return result;
            }
        }

        private static int Align4(int value) { return (value + 3) & ~3; }
        private static void Pad4(Stream stream) { while ((stream.Position & 3) != 0) stream.WriteByte(0); }
        private static void RequireZeroPadding(byte[] data, int start, int end)
        {
            for (int i = start; i < end; ++i)
                if (data[i] != 0) throw new InvalidDataException("The version resource contains unexpected trailing data.");
        }
        private static ushort ReadUInt16(byte[] data, int offset)
        {
            return (ushort)(data[offset] | (data[offset + 1] << 8));
        }
        private static uint ReadUInt32(byte[] data, int offset)
        {
            return (uint)data[offset] | ((uint)data[offset + 1] << 8) |
                ((uint)data[offset + 2] << 16) | ((uint)data[offset + 3] << 24);
        }
        private static void SetUInt16(byte[] data, int offset, ushort value)
        {
            data[offset] = (byte)value;
            data[offset + 1] = (byte)(value >> 8);
        }
        private static void SetUInt32(byte[] data, int offset, uint value)
        {
            for (int i = 0; i < 4; ++i) data[offset + i] = (byte)(value >> (i * 8));
        }
        private static void WriteUInt16(Stream stream, ushort value)
        {
            stream.WriteByte((byte)value);
            stream.WriteByte((byte)(value >> 8));
        }
        private static Win32Exception NativeError(string operation)
        {
            return NativeError(operation, Marshal.GetLastWin32Error());
        }
        private static Win32Exception NativeError(string operation, int code)
        {
            if (code == 0) code = 13;
            return new Win32Exception(code, operation + ": " + new Win32Exception(code).Message);
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private delegate bool EnumResourceLanguageProc(IntPtr module, IntPtr type,
            IntPtr name, ushort language, IntPtr parameter);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr LoadLibraryExW(string fileName, IntPtr file, uint flags);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumResourceLanguagesW(IntPtr module, IntPtr type,
            IntPtr name, EnumResourceLanguageProc callback, IntPtr parameter);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr FindResourceExW(IntPtr module, IntPtr type, IntPtr name, ushort language);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", ExactSpelling = true)]
        private static extern IntPtr LockResource(IntPtr resource);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr BeginUpdateResourceW(string fileName, [MarshalAs(UnmanagedType.Bool)] bool deleteExisting);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateResourceW(IntPtr update, IntPtr type, IntPtr name,
            ushort language, [In] byte[] data, uint size);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EndUpdateResourceW(IntPtr update, [MarshalAs(UnmanagedType.Bool)] bool discard);
    }
}