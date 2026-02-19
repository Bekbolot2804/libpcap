# Фаззинг pcap_compile_nopcap

Фаззинг-тестирование функции `pcap_compile_nopcap` библиотеки libpcap с LibFuzzer и генерация HTML-отчёта покрытия llvm-cov.

## Быстрый старт

```bash
./run_fuzz_pcap_compile_nopcap.sh
```

По умолчанию фаззинг длится 5 часов (18000 с). Для быстрой проверки:

```bash
FUZZ_DURATION=60 ./run_fuzz_pcap_compile_nopcap.sh
```

## Требования

- clang (с libFuzzer, llvm-profdata, llvm-cov)
- cmake, make
- flex, bison

## Что создаётся

- **Сборка**: `build-fuzz-coverage/run/fuzz_pcap_compile_nopcap`
- **Корпус**: `testprogs/fuzz/corpus_pcap_compile_nopcap/`
- **Артефакты** (crash, leak): `artifacts/`
- **HTML-отчёт**: `fuzz_coverage_report/index.html`

Откройте `fuzz_coverage_report/index.html` в браузере для просмотра покрытия.

## Корпус

Семплы в `corpus_pcap_compile_nopcap/` взяты из тестов авторов (testprogs/BPF/*.txt):

- `01_host.bin` — базовый фильтр `host`
- `02_port.bin` — `port 80`
- `03_tcpflags.bin` — сложные `tcp[tcpflags]`
- `04_vlan_ip.bin` — `vlan` и `ip`
- `05_ether.bin` — `ether[12:2]`
- `06_complex_ip.bin` — вложенные примитивы

Подробнее в `testprogs/fuzz/corpus_pcap_compile_nopcap/README.md`.
