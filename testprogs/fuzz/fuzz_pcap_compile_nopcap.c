/*
 * LibFuzzer harness for pcap_compile_nopcap().
 *
 * Targets the BPF filter compiler entry point that works without an open
 * pcap handle. Fuzzes filter expression strings with varying snaplen,
 * linktype, and netmask to exercise gencode.c, grammar, and optimizer paths.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <pcap/pcap.h>

/* Harness specifically targets pcap_compile_nopcap */
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif

void fuzz_openFile(const char *name)
{
    (void)name;
}

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
    struct bpf_program bpf;
    char *filter;
    int snaplen;
    int linktype;
    bpf_u_int32 netmask;
    int optimize;

    /* Need at least 2 bytes: 1 for filter + 1 for linktype/params */
    if (Size < 2) {
        return 0;
    }

    filter = malloc(Size);
    if (filter == NULL) {
        return 0;
    }
    memcpy(filter, Data, Size);

    /*
     * Last byte: linktype (1=EN10MB, 12=RAW, 113=LINUX_SLL are common)
     * Penultimate byte: snaplen hint, netmask, optimize
     */
    linktype = Data[Size - 1] & 0xFF;
    snaplen = (Data[Size - 2] & 1) ? 65535 : 256;
    netmask = (Data[Size - 2] & 2) ? 0xFFFFFF00 : PCAP_NETMASK_UNKNOWN;
    optimize = (Data[Size - 2] & 4) ? 1 : 0;

    /* Filter = Data[0..Size-2], null-terminated */
    filter[Size - 1] = '\0';

    if (pcap_compile_nopcap(snaplen, linktype, &bpf, filter, optimize, netmask) == 0) {
        pcap_freecode(&bpf);
    }

    free(filter);
    return 0;
}
