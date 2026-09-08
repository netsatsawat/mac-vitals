// gpucal — dump GPU "GPU Performance States" (GPUPH) residency over a window, so
// its numbers can be correlated with powermetrics' "GPU active residency". No root
// needed for this part. Build: clang -fblocks gpucal.c -o gpucal -framework CoreFoundation
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <CoreFoundation/CoreFoundation.h>

typedef struct S* SubRef;
typedef CFMutableDictionaryRef(*fc)(CFStringRef,CFStringRef,uint64_t,uint64_t,uint64_t);
typedef SubRef(*fs)(void*,CFMutableDictionaryRef,CFMutableDictionaryRef*,uint64_t,CFTypeRef);
typedef CFDictionaryRef(*fsa)(SubRef,CFMutableDictionaryRef,CFTypeRef);
typedef CFDictionaryRef(*fd)(CFDictionaryRef,CFDictionaryRef,CFTypeRef);
typedef void(*fi)(CFDictionaryRef,int(^)(CFDictionaryRef));
typedef CFStringRef(*fstr)(CFDictionaryRef);
typedef int(*fcn)(CFDictionaryRef);
typedef CFStringRef(*fsn)(CFDictionaryRef,int);
typedef int64_t(*fr)(CFDictionaryRef,int);
static void* H; static void* G(const char* n){ return dlsym(H, n); }

int main(int argc, char** argv) {
    double T = argc > 1 ? atof(argv[1]) : 1.0;
    H = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
    if (!H) { printf("dlopen failed\n"); return 1; }
    fc Copy = (fc)G("IOReportCopyChannelsInGroup");
    fs Sub = (fs)G("IOReportCreateSubscription");
    fsa Samp = (fsa)G("IOReportCreateSamples");
    fd Delta = (fd)G("IOReportCreateSamplesDelta");
    fi Iter = (fi)G("IOReportIterate");
    fstr Nm = (fstr)G("IOReportChannelGetChannelName");
    fcn Cnt = (fcn)G("IOReportStateGetCount");
    fsn SN = (fsn)G("IOReportStateGetNameForIndex");
    fr Res = (fr)G("IOReportStateGetResidency");

    CFMutableDictionaryRef gpu = Copy(CFSTR("GPU Stats"), NULL, 0, 0, 0);
    CFMutableDictionaryRef sb = NULL;
    SubRef s = Sub(NULL, gpu, &sb, 0, NULL);
    CFDictionaryRef a = Samp(s, sb, NULL);
    struct timespec ts = { .tv_sec = (long)T, .tv_nsec = (long)((T - (long)T) * 1e9) };
    nanosleep(&ts, NULL);
    CFDictionaryRef b = Samp(s, sb, NULL);
    CFDictionaryRef d = Delta(a, b, NULL);

    Iter(d, ^int(CFDictionaryRef c) {
        char cn[40] = {0};
        if (Nm(c)) CFStringGetCString(Nm(c), cn, 40, 0x08000100);
        if (strcmp(cn, "GPUPH")) return 0;
        int n = Cnt(c);
        long long tot = 0, off = 0, p1 = 0, p2 = 0;
        for (int i = 0; i < n; i++) {
            long long r = Res(c, i);
            tot += r;
            if (i == 0) off = r; else if (i == 1) p1 = r; else if (i == 2) p2 = r;
        }
        if (tot <= 0) { printf("GPUPH total=0\n"); return 0; }
        printf("GPUPH total=%lld\n", tot);
        for (int i = 0; i < n; i++) {
            char st[24] = {0};
            if (SN(c, i)) CFStringGetCString(SN(c, i), st, 24, 0x08000100);
            long long r = Res(c, i);
            if (r > 0) printf("   %-6s %14lld  %6.2f%%\n", st, r, 100.0 * r / tot);
        }
        printf("  candidate active%% = 1-OFF/tot        : %6.2f%%\n", 100.0 * (tot - off) / tot);
        printf("  candidate active%% = 1-(OFF+P1)/tot   : %6.2f%%\n", 100.0 * (tot - off - p1) / tot);
        printf("  candidate active%% = 1-(OFF+P1+P2)/tot: %6.2f%%\n", 100.0 * (tot - off - p1 - p2) / tot);
        return 0;
    });
    return 0;
}
