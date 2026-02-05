#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "pcap.h"

/*
 * Идея:
 *  - Интерпретируем fuzz-данные как строку фильтра (BPF expression).
 *  - Гарантируем NUL-терминацию.
 *  - Часть данных используем как флаги optimize и netmask.
 *  - Вызываем pcap_compile(...) на pre-opened "dead" pcap handle.
 */

static pcap_t *get_dead_pcap(void) {
    static pcap_t *dead = NULL;
    if (!dead) {
        // DLT_EN10MB и типичный snaplen
        dead = pcap_open_dead(DLT_EN10MB, 65535);
    }
    return dead;
}

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    if (Size == 0) {
        return 0;
    }

    pcap_t *p = get_dead_pcap();
    if (!p) {
        return 0;
    }

    // Возьмём первые байты под флаги/маску, а остальное — как строку фильтра.
    int optimize = 1;
    bpf_u_int32 netmask = 0xFFFFFFFF;

    const size_t header_bytes = 5; // 1 байт на optimize, 4 байта на netmask
    if (Size > header_bytes) {
        optimize = (Data[0] & 1);  // 0 или 1
        if (Size >= 5) {
            // netmask из следующих 4 байт
            netmask = ( (bpf_u_int32)Data[1]       ) |
                      (((bpf_u_int32)Data[2]) << 8 ) |
                      (((bpf_u_int32)Data[3]) << 16) |
                      (((bpf_u_int32)Data[4]) << 24);
        }
        Data  += header_bytes;
        Size  -= header_bytes;
    } else {
        // Слишком мало данных — используем дефолты
        Data  += Size;
        Size   = 0;
    }

    // Преобразуем оставшиеся байты в NUL-терминированную строку
    char *expr = NULL;
    if (Size > 0) {
        expr = (char *)malloc(Size + 1);
        if (!expr) {
            return 0;
        }
        memcpy(expr, Data, Size);
        expr[Size] = '\0';

        // Лёгкая нормализация: заменим \0 внутри на пробелы, чтобы не обрезать строку
        for (size_t i = 0; i < Size; ++i) {
            if (expr[i] == '\0') {
                expr[i] = ' ';
            }
        }
    } else {
        // Пустой фильтр тоже интересен
        expr = strdup("");
    }

    struct bpf_program prog;
    memset(&prog, 0, sizeof(prog));

    // Собственно вызов, который мы fuzz'им
    int ret = pcap_compile(p, &prog, expr, optimize, netmask);

    if (ret == 0) {
        // Если компиляция успешна — обязательно освободим
        pcap_freecode(&prog);
    }

    free(expr);
    return 0;
}