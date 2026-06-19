// ##### extgen :: Auto-generated file do not edit!! #####

#import "ICompressionInternal_ios.h"
#import "native/ICompressionInternal_exports.h"
#import <objc/runtime.h>


extern "C" const char* extOptGetString(char* _ext, char* _opt);

// Adapter: matches const signature expected by the C++ API
static const char* ExtOptGetString(const char* ext, const char* opt)
{
    return extOptGetString(const_cast<char*>(ext), const_cast<char*>(opt));
}

static BOOL GMIsSubclassOf(Class cls, Class base)
{
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        if (c == base) return YES;
    }
    return NO;
}

static void GMInjectSelectorsIntoSubclass(Class subclass, Class base)
{
    // Build set of methods already defined on subclass
    unsigned subCount = 0;
    Method *subList = class_copyMethodList(subclass, &subCount);

    CFMutableSetRef owned = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
    for (unsigned i = 0; i < subCount; ++i) {
        CFSetAddValue(owned, method_getName(subList[i]));
    }

    // Walk base class methods
    unsigned baseCount = 0;
    Method *baseList = class_copyMethodList(base, &baseCount);

    for (unsigned i = 0; i < baseCount; ++i) {
        SEL sel = method_getName(baseList[i]);
        const char *name = sel_getName(sel);

        // Only inject extension selectors (methods prefixed with __EXT_NATIVE__)
        if (!name || strncmp(name, "__EXT_NATIVE__", 13) != 0) continue;

        // Add only if subclass doesn't already have it
        if (!CFSetContainsValue(owned, sel)) {
            IMP imp = method_getImplementation(baseList[i]);
            const char *types = method_getTypeEncoding(baseList[i]);
            if (class_addMethod(subclass, sel, imp, types)) {
                CFSetAddValue(owned, sel);
            }
        }
    }

    if (subList) free(subList);
    if (baseList) free(baseList);
    if (owned) CFRelease(owned);
}

@implementation ICompressionInternal

+ (void)load
{
    // Find all loaded classes
    int num = objc_getClassList(NULL, 0);
    if (num <= 0) return;

    Class *classes = (Class *)malloc(sizeof(Class) * (unsigned)num);
    num = objc_getClassList(classes, num);

    Class base = [ICompressionInternal class];

    for (int i = 0; i < num; ++i) {
        Class cls = classes[i];
        if (cls == base) continue;

        // We only care about direct or indirect subclasses
        if (GMIsSubclassOf(cls, base)) {
            GMInjectSelectorsIntoSubclass(cls, base);
        }
    }

    free(classes);

    gm::details::GMRTRunnerInterface ri{};
    ri.ExtOptGetString = &ExtOptGetString;
    GMExtensionInitialise(&ri, sizeof(ri));
}

- (char*)__EXT_NATIVE__ic_compress:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_compress(__arg_buffer, __arg_buffer_length);
}
- (char*)__EXT_NATIVE__ic_decompress:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_decompress(__arg_buffer, __arg_buffer_length);
}
- (double)__EXT_NATIVE__ic_compress_file:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_compress_file(__arg_buffer, __arg_buffer_length);
}
- (double)__EXT_NATIVE__ic_decompress_file:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_decompress_file(__arg_buffer, __arg_buffer_length);
}
- (double)__EXT_NATIVE__ic_compress_buf:(char*)__arg_buffer arg1:(double)__arg_buffer_length arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_compress_buf(__arg_buffer, __arg_buffer_length, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_decompress_buf:(char*)__arg_buffer arg1:(double)__arg_buffer_length arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_decompress_buf(__arg_buffer, __arg_buffer_length, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_list:(char*)archive arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_list(archive, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_extract:(char*)archive arg1:(char*)output_dir arg2:(char*)__ret_buffer arg3:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_extract(archive, output_dir, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_extract_file:(char*)archive arg1:(char*)entry arg2:(char*)output
{
    return __EXT_NATIVE__ic_extract_file(archive, entry, output);
}
- (char*)__EXT_NATIVE__ic_extract_mem:(char*)archive arg1:(char*)entry
{
    return __EXT_NATIVE__ic_extract_mem(archive, entry);
}
- (double)__EXT_NATIVE__ic_create:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_create(__arg_buffer, __arg_buffer_length);
}
- (double)__EXT_NATIVE__ic_add_file:(double)handle arg1:(char*)path arg2:(char*)entry
{
    return __EXT_NATIVE__ic_add_file(handle, path, entry);
}
- (double)__EXT_NATIVE__ic_add_data:(double)handle arg1:(char*)entry arg2:(char*)data
{
    return __EXT_NATIVE__ic_add_data(handle, entry, data);
}
- (double)__EXT_NATIVE__ic_close:(double)handle
{
    return __EXT_NATIVE__ic_close(handle);
}
- (double)__EXT_NATIVE__ic_detect:(char*)data arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_detect(data, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_detect_file:(char*)path arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_detect_file(path, __ret_buffer, __ret_buffer_length);
}
- (double)__EXT_NATIVE__ic_from_ext:(char*)name arg1:(char*)__ret_buffer arg2:(double)__ret_buffer_length
{
    return __EXT_NATIVE__ic_from_ext(name, __ret_buffer, __ret_buffer_length);
}
- (char*)__EXT_NATIVE__ic_to_str:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ic_to_str(__arg_buffer, __arg_buffer_length);
}
- (double)__EXT_NATIVE__ICompression_queue_buffer:(char*)__arg_buffer arg1:(double)__arg_buffer_length
{
    return __EXT_NATIVE__ICompression_queue_buffer(__arg_buffer, __arg_buffer_length);
}
@end

