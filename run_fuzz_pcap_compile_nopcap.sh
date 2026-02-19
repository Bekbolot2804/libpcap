#!/bin/bash
#
# Фаззинг pcap_compile_nopcap с LibFuzzer и генерация HTML-отчёта llvm-cov.
# Запуск: 5 часов, без многопоточности (-jobs=1).
#
# Требует: clang (с libFuzzer и llvm-cov), cmake
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-fuzz-coverage"
CORPUS_DIR="${SCRIPT_DIR}/testprogs/fuzz/corpus_pcap_compile_nopcap"
REPORT_DIR="${SCRIPT_DIR}/fuzz_coverage_report"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
: "${FUZZ_DURATION:=18000}"   # 5 часов по умолчанию; для теста: FUZZ_DURATION=60
PROFDATA="${BUILD_DIR}/fuzz.profdata"
PROFRAW_PATTERN="${BUILD_DIR}/fuzz_*.profraw"

# Проверка clang
if ! command -v clang &>/dev/null; then
    echo "Ошибка: clang не найден. Установите llvm/clang."
    exit 1
fi

# Флаги: ASan+coverage глобально (чтобы проверка компилятора CMake прошла),
# LibFuzzer только для fuzz-таргета (добавляется в fuzz/CMakeLists.txt).
COVERAGE_CFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping -O1 -g -fno-omit-frame-pointer"
COVERAGE_LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

echo "=== Шаг 1: Конфигурация и сборка ==="
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
cmake -DCMAKE_C_COMPILER=clang \
      -DEXTRA_CFLAGS="${COVERAGE_CFLAGS}" \
      -DCMAKE_EXE_LINKER_FLAGS="${COVERAGE_LDFLAGS}" \
      -DENABLE_LIBFUZZER=ON \
      -DPCAP_TYPE=null \
      "${SCRIPT_DIR}"
make -j"$(nproc)" fuzz_pcap_compile_nopcap

FUZZ_BIN="${BUILD_DIR}/run/fuzz_pcap_compile_nopcap"
if [[ ! -x "${FUZZ_BIN}" ]]; then
    echo "Ошибка: fuzz_pcap_compile_nopcap не найден после сборки"
    exit 1
fi

echo ""
echo "=== Шаг 2: Запуск фаззинга на ${FUZZ_DURATION} с ==="
echo "Corpus: ${CORPUS_DIR}"
echo "Артефакты (crash/leak): ${ARTIFACTS_DIR}/"
echo "Без многопоточности (-jobs=1)"
echo ""

export LLVM_PROFILE_FILE="${BUILD_DIR}/fuzz_%p.profraw"
export ASAN_OPTIONS="detect_leaks=0:symbolize=1"
rm -f ${PROFRAW_PATTERN} 2>/dev/null || true

mkdir -p "${ARTIFACTS_DIR}"
# Используем -max_total_time вместо timeout: LibFuzzer завершится нормально
# и успеет записать profraw (timeout посылает SIGTERM и профиль не сохраняется)
timeout $((FUZZ_DURATION + 120)) "${FUZZ_BIN}" \
    -jobs=1 \
    -workers=1 \
    -max_total_time="${FUZZ_DURATION}" \
    -artifact_prefix="${ARTIFACTS_DIR}/" \
    "${CORPUS_DIR}" \
    || true

echo ""
echo "=== Шаг 3: Слияние профилей ==="
PROFRAW_FILES=$(ls ${PROFRAW_PATTERN} 2>/dev/null || true)
if [[ -z "${PROFRAW_FILES}" ]]; then
    echo "Profraw не найдены (короткий запуск?). Генерируем минимальный профиль..."
    LLVM_PROFILE_FILE="${BUILD_DIR}/fuzz_1.profraw" "${FUZZ_BIN}" -runs=10 "${CORPUS_DIR}" 2>/dev/null || true
    PROFRAW_FILES=$(ls ${PROFRAW_PATTERN} 2>/dev/null || true)
fi

if [[ -n "${PROFRAW_FILES}" ]]; then
    llvm-profdata merge -sparse -o "${PROFDATA}" ${PROFRAW_FILES} 2>/dev/null || \
        llvm-profdata merge -o "${PROFDATA}" ${PROFRAW_FILES}
else
    echo "Внимание: профиль пуст, отчёт покрытия будет неполным."
    touch "${PROFDATA}"
fi

echo ""
echo "=== Шаг 4: Генерация HTML-отчёта покрытия ==="
mkdir -p "${REPORT_DIR}"

# Генерация HTML-отчёта (бинарник уже содержит coverage mapping)
llvm-cov show "${FUZZ_BIN}" \
    -instr-profile="${PROFDATA}" \
    -format=html \
    -output-dir="${REPORT_DIR}" \
    -show-line-counts-or-regions \
    -path-equivalence="/," \
    2>/dev/null || \
llvm-cov show "${FUZZ_BIN}" \
    -instr-profile="${PROFDATA}" \
    -format=html \
    -output-dir="${REPORT_DIR}" \
    -show-line-counts-or-regions \
    2>/dev/null || true

echo ""
echo "=== Готово ==="
echo "HTML-отчёт: ${REPORT_DIR}/index.html"
echo "Откройте в браузере: file://${REPORT_DIR}/index.html"
