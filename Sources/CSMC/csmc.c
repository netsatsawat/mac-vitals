#include "csmc.h"
#include <string.h>
#include <IOKit/IOKitLib.h>

typedef struct { char major, minor, build, reserved[1]; unsigned short release; } vers_t;
typedef struct { unsigned short version, length; unsigned int cpuPLimit, gpuPLimit, memPLimit; } plim_t;
typedef struct { unsigned int dataSize; unsigned int dataType; char dataAttributes; } keyInfo_t;
typedef struct {
    unsigned int key; vers_t vers; plim_t pLimitData; keyInfo_t keyInfo;
    char result, status, data8; unsigned int data32; unsigned char bytes[32];
} SMCKeyData_t;

#define KERNEL_INDEX_SMC 2
#define CMD_READ_BYTES   5
#define CMD_READ_KEYINFO 9
#define CMD_READ_INDEX   8

static io_connect_t conn = 0;

static unsigned int str_to_key(const char* s) {
    return ((unsigned int)s[0] << 24) | ((unsigned int)s[1] << 16) | ((unsigned int)s[2] << 8) | (unsigned int)s[3];
}
static void key_to_str(unsigned int k, char* s) {
    s[0] = k >> 24; s[1] = k >> 16; s[2] = k >> 8; s[3] = k; s[4] = 0;
}

int csmc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return 1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return r == 0 ? 0 : 2;
}
void csmc_close(void) { if (conn) { IOServiceClose(conn); conn = 0; } }

static int call(SMCKeyData_t* in, SMCKeyData_t* out) {
    size_t osz = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCKeyData_t), out, &osz);
}

int csmc_key_count(void) {
    double v;
    // #KEY is a ui32 count; read raw and reconstruct.
    SMCKeyData_t in = {0}, out = {0};
    in.key = str_to_key("#KEY"); in.data8 = CMD_READ_KEYINFO;
    if (call(&in, &out) != 0) return -1;
    keyInfo_t ki = out.keyInfo;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = str_to_key("#KEY"); in.keyInfo.dataSize = ki.dataSize; in.data8 = CMD_READ_BYTES;
    if (call(&in, &out) != 0) return -1;
    (void)v;
    return (out.bytes[0] << 24) | (out.bytes[1] << 16) | (out.bytes[2] << 8) | out.bytes[3];
}

int csmc_key_at(int index, char out_str[5]) {
    SMCKeyData_t in = {0}, out = {0};
    in.data8 = CMD_READ_INDEX; in.data32 = (unsigned int)index;
    if (call(&in, &out) != 0) return 1;
    key_to_str(out.key, out_str);
    return 0;
}

int csmc_read(const char* key, double* value) {
    SMCKeyData_t in = {0}, out = {0};
    in.key = str_to_key(key); in.data8 = CMD_READ_KEYINFO;
    if (call(&in, &out) != 0) return 1;
    keyInfo_t ki = out.keyInfo;

    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = str_to_key(key); in.keyInfo.dataSize = ki.dataSize; in.data8 = CMD_READ_BYTES;
    if (call(&in, &out) != 0) return 1;

    char t[5]; key_to_str(ki.dataType, t);
    unsigned char* b = out.bytes;
    if (strcmp(t, "flt ") == 0) { float f; memcpy(&f, b, 4); *value = f; return 0; }
    if (strcmp(t, "sp78") == 0) { short v = (short)((b[0] << 8) | b[1]); *value = v / 256.0; return 0; }
    if (strcmp(t, "fpe2") == 0) { *value = ((b[0] << 8) | b[1]) / 4.0; return 0; }
    if (strcmp(t, "ui16") == 0) { *value = (b[0] << 8) | b[1]; return 0; }
    if (strcmp(t, "ui8 ") == 0) { *value = b[0]; return 0; }
    return 2; // unhandled type
}
