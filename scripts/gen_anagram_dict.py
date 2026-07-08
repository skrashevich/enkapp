#!/usr/bin/env python3
"""
Генератор бинарного словаря для анаграмайзера (формат ANGR v1).

Источники (объединение, US-2):
  1. OpenCorpora — основной источник (~3.02M форм), получается из готового
     скомпилированного словаря пакета `pymorphy2-dicts-ru` (та же ревизия
     словаря OpenCorpora, см. docs/anagramizer-dict-candidates.md). Лицензия
     данных — CC-BY-SA.
  2. Лебедев (ru_RU, hunspell) — прежний источник, добавляет ~153k форм,
     которых нет в OpenCorpora (иная обработка ё/е и словника). Лицензия —
     модифицированная 3-clause BSD.

Оба источника и их лицензии зафиксированы дословно в docs/LICENSE-dict.md.
Комбинированный словарь распространяется под CC-BY-SA (заражение только от
OpenCorpora-компоненты, код приложения не затрагивает).

Пайплайн:
  1. OpenCorpora: гарантировать pip-пакет `pymorphy2-dicts-ru` (+ зависимости)
     в изолированном venv под .dict-cache/venv, извлечь все ключи DAWG-словаря
     (словоформы), закэшировать сырой список в .dict-cache/opencorpora_forms.txt.
  2. Лебедев: скачать/использовать ru_RU.aff + ru_RU.dic (кэш в .dict-cache/),
     раскрыть через системный unmunch (ru_RU.dic ru_RU.aff — именно в этом
     порядке аргументов), перекодировать в UTF-8 при необходимости.
  3. Нормализовать ОБА источника одинаково: lowercase, оставить только слова
     из 33 букв русского алфавита (а..я + ё), без дефисов/апострофов/латиницы/
     цифр/пробелов, дедуп, отбросить пустые и длиннее maxLen; объединить через
     set union (потоково, без раздувания памяти — оба источника уже дедуплены
     по отдельности перед union).
  4. Провалидировать покрытие частотных слов и долю "мусорных" форм.
  5. Упаковать по контракту docs/anagramizer-binary-format.md в encx-cli/Resources/ru_dict.bin.
  6. Round-trip самопроверка: прочитать записанный файл обратно, сверить выборку.
  7. Сохранить случайную выборку 1000 слов в docs/anagram-sample-words.txt.
  8. Записать отчёт в docs/anagramizer-dict-report.md.

Использует стандартную библиотеку Python 3 + системные unmunch/iconv/curl +
pip (для pymorphy2-dicts-ru, устанавливается в изолированный venv, не в
системный python). Идемпотентен: повторный запуск перегенерирует артефакт
с нуля (используя кэш в .dict-cache/, если он уже заполнен).
"""

import os
import random
import struct
import subprocess
import sys
import urllib.request
from collections import Counter

# --- Пути -------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
RESOURCES_DIR = os.path.join(REPO_ROOT, "encx-cli", "Resources")
OUT_BIN = os.path.join(RESOURCES_DIR, "ru_dict.bin")
OUT_SAMPLE = os.path.join(DOCS_DIR, "anagram-sample-words.txt")
OUT_REPORT = os.path.join(DOCS_DIR, "anagramizer-dict-report.md")

CACHE_DIR = os.path.join(REPO_ROOT, ".dict-cache")
AFF_PATH = os.path.join(CACHE_DIR, "ru_RU.aff")
DIC_PATH = os.path.join(CACHE_DIR, "ru_RU.dic")

AFF_URL = "https://raw.githubusercontent.com/LibreOffice/dictionaries/master/ru_RU/ru_RU.aff"
DIC_URL = "https://raw.githubusercontent.com/LibreOffice/dictionaries/master/ru_RU/ru_RU.dic"

UNMUNCH_CANDIDATES = ["/opt/homebrew/bin/unmunch", "/usr/local/bin/unmunch", "unmunch"]

# OpenCorpora (через pymorphy2-dicts-ru) — см. docs/anagramizer-dict-candidates.md.
OPENCORPORA_VENV_DIR = os.path.join(CACHE_DIR, "venv")
OPENCORPORA_FORMS_PATH = os.path.join(CACHE_DIR, "opencorpora_forms.txt")
OPENCORPORA_PIP_PACKAGES = ["pymorphy2-dicts-ru", "pymorphy2", "dawg-python", "docopt"]

# --- Контракт формата (docs/anagramizer-binary-format.md) -------------

ALPHABET = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
assert len(ALPHABET) == 33
CODE_OF = {ch: i for i, ch in enumerate(ALPHABET)}
MAGIC = b"ANGR"
VERSION = 1
YO_FOLDED = 0  # v1: ё сохраняется как отдельный код 6
MAX_LEN_CAP = 40

# Известные системные пути, где может лежать словарь (если вдруг появится).
SYSTEM_DICT_CANDIDATES = [
    ("/System/Library/Spelling/ru_RU.aff", "/System/Library/Spelling/ru_RU.dic"),
    ("/Library/Spelling/ru_RU.aff", "/Library/Spelling/ru_RU.dic"),
    ("/opt/homebrew/share/hunspell/ru_RU.aff", "/opt/homebrew/share/hunspell/ru_RU.dic"),
]


def find_unmunch():
    for cand in UNMUNCH_CANDIDATES:
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
        found = subprocess.run(["which", cand], capture_output=True, text=True)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    sys.exit("unmunch не найден (искали в /opt/homebrew/bin, /usr/local/bin, $PATH)")


def detect_encoding(aff_path):
    """Читает строку SET из .aff, чтобы понять исходную кодировку .dic."""
    with open(aff_path, "rb") as f:
        head = f.read(4096)
    for line in head.split(b"\n"):
        if line.strip().startswith(b"SET "):
            enc = line.strip().split()[1].decode("ascii", "ignore")
            return enc
    return "UTF-8"


def ensure_source_dict():
    """Гарантирует наличие ru_RU.aff/.dic: сперва ищет в системе, иначе качает
    canonical upstream (LibreOffice dictionaries, словарь А.И. Лебедева — см.
    docs/LICENSE-dict.md) и кэширует локально в .dict-cache/ (не коммитится)."""
    for aff, dic in SYSTEM_DICT_CANDIDATES:
        if os.path.isfile(aff) and os.path.isfile(dic):
            print(f"[source] найден системный словарь: {aff}")
            return aff, dic

    os.makedirs(CACHE_DIR, exist_ok=True)
    if not (os.path.isfile(AFF_PATH) and os.path.isfile(DIC_PATH)):
        print(f"[source] системного словаря не найдено, качаю upstream в {CACHE_DIR}")
        urllib.request.urlretrieve(AFF_URL, AFF_PATH)
        urllib.request.urlretrieve(DIC_URL, DIC_PATH)
    else:
        print(f"[source] использую кэш {CACHE_DIR}")
    return AFF_PATH, DIC_PATH


def unmunch_words(aff_path, dic_path):
    unmunch = find_unmunch()
    encoding = detect_encoding(aff_path)
    print(f"[unmunch] бинарь={unmunch} кодировка .dic/.aff={encoding}")

    raw = subprocess.run(
        [unmunch, dic_path, aff_path],
        capture_output=True,
        check=False,  # unmunch может писать шум в stderr и возвращать код != 0 — не фатально
    )
    if not raw.stdout:
        sys.exit(f"unmunch не дал вывода на stdout (stderr: {raw.stderr[:500]!r})")

    if encoding.upper() not in ("UTF-8", "UTF8"):
        # Перекодируем через iconv, т.к. .dic мог быть в KOI8-R/CP1251.
        conv = subprocess.run(
            ["iconv", "-f", encoding, "-t", "UTF-8//TRANSLIT"],
            input=raw.stdout,
            capture_output=True,
        )
        if conv.returncode != 0:
            sys.exit(f"iconv не смог перекодировать из {encoding}: {conv.stderr[:500]!r}")
        text = conv.stdout.decode("utf-8", errors="replace")
    else:
        text = raw.stdout.decode("utf-8", errors="replace")

    lines = text.split("\n")
    print(f"[unmunch] сырых строк: {len(lines)}")
    return lines


# --- OpenCorpora (pymorphy2-dicts-ru) ------------------------------------

def ensure_opencorpora_forms():
    """Гарантирует наличие сырого списка словоформ OpenCorpora в
    .dict-cache/opencorpora_forms.txt. Если кэша нет — поднимает изолированный
    venv в .dict-cache/venv, ставит pymorphy2-dicts-ru (+ зависимости) и
    извлекает все ключи DAWG-словаря (см. docs/anagramizer-dict-candidates.md
    для обоснования метода и измеренных чисел)."""
    os.makedirs(CACHE_DIR, exist_ok=True)

    if os.path.isfile(OPENCORPORA_FORMS_PATH):
        print(f"[opencorpora] использую кэш {OPENCORPORA_FORMS_PATH}")
        with open(OPENCORPORA_FORMS_PATH, encoding="utf-8") as f:
            return f.read().split("\n")

    venv_python = os.path.join(OPENCORPORA_VENV_DIR, "bin", "python3")
    if not os.path.isfile(venv_python):
        print(f"[opencorpora] создаю venv в {OPENCORPORA_VENV_DIR}")
        subprocess.run([sys.executable, "-m", "venv", OPENCORPORA_VENV_DIR], check=True)

    print(f"[opencorpora] устанавливаю {', '.join(OPENCORPORA_PIP_PACKAGES)}")
    subprocess.run(
        [venv_python, "-m", "pip", "install", "--quiet"] + OPENCORPORA_PIP_PACKAGES,
        check=True,
    )

    extractor = """
import pymorphy2_dicts_ru
from pymorphy2.opencorpora_dict.storage import load_dict
d = load_dict(pymorphy2_dicts_ru.get_path())
import sys
n = 0
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for key in d.words.iterkeys():
        f.write(key + "\\n")
        n += 1
print("extracted", n, "keys", file=sys.stderr)
"""
    print("[opencorpora] извлекаю словоформы из DAWG-словаря")
    result = subprocess.run(
        [venv_python, "-c", extractor, OPENCORPORA_FORMS_PATH],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"извлечение OpenCorpora не удалось: {result.stderr[-2000:]}")
    print(f"[opencorpora] {result.stderr.strip()}")

    with open(OPENCORPORA_FORMS_PATH, encoding="utf-8") as f:
        return f.read().split("\n")


# --- Нормализация -------------------------------------------------------

def normalize_words(raw_lines, max_len=MAX_LEN_CAP):
    """lowercase; только буквы алфавита ALPHABET; дедуп; фильтр длины."""
    seen = set()
    dropped_bad_chars = 0
    dropped_too_long = 0
    dropped_empty = 0

    for line in raw_lines:
        w = line.strip().lower()
        if not w:
            dropped_empty += 1
            continue
        if len(w) > max_len:
            dropped_too_long += 1
            continue
        if any(ch not in CODE_OF for ch in w):
            dropped_bad_chars += 1
            continue
        seen.add(w)

    stats = {
        "dropped_bad_chars": dropped_bad_chars,
        "dropped_too_long": dropped_too_long,
        "dropped_empty": dropped_empty,
        "unique_kept": len(seen),
    }
    return seen, stats


# --- Анти-мусорная эвристика (для отчёта, не фильтрует по умолчанию) ----

VOWELS = set("аеёиоуыэюя")


def looks_garbage(word):
    """Грубая эвристика: 4+ согласных подряд, или редкие невозможные биграммы."""
    run = 0
    for ch in word:
        if ch in VOWELS or ch in ("й",):
            run = 0
        else:
            run += 1
            if run >= 5:
                return True
    if "ъь" in word or "ьъ" in word or "ыъ" in word:
        return True
    return False


FREQUENT_PROBE = [
    "и", "в", "не", "что", "он", "на", "я", "с", "а", "как", "это",
    "кот", "кит", "дом", "мама", "вода", "книга", "слово", "русский",
    "человек", "время", "год", "рука", "день", "жизнь", "дело", "работа",
    "мир", "город", "земля", "друг", "любовь", "солнце", "небо", "море",
    "дерево", "окно", "стол", "стул", "собака", "птица", "рыба", "хлеб",
    "молоко", "школа", "улица", "машина", "телефон", "компьютер",
    "красный", "большой", "маленький", "быстро",
]


def coverage_check(words_set):
    present = [w for w in FREQUENT_PROBE if w in words_set]
    missing = [w for w in FREQUENT_PROBE if w not in words_set]
    pct = 100.0 * len(present) / len(FREQUENT_PROBE)
    return pct, present, missing


def garbage_estimate(words_set, sample_size=20000, seed=42):
    rng = random.Random(seed)
    pool = list(words_set)
    sample = rng.sample(pool, min(sample_size, len(pool)))
    bad = sum(1 for w in sample if looks_garbage(w))
    return 100.0 * bad / len(sample), len(sample)


# --- Упаковка по контракту ANGR v1 --------------------------------------

def pack_binary(words_set, out_path):
    by_len = {}
    for w in words_set:
        by_len.setdefault(len(w), []).append(w)

    max_len = max(by_len.keys())
    if max_len > MAX_LEN_CAP:
        sys.exit(f"maxLen {max_len} превышает лимит контракта {MAX_LEN_CAP}")

    # Сортировка внутри bucket'а лексикографически по кодам букв.
    encoded_by_len = {}
    for L, ws in by_len.items():
        codeword_list = [bytes(CODE_OF[ch] for ch in w) for w in ws]
        codeword_list.sort()
        encoded_by_len[L] = codeword_list

    word_count = len(words_set)

    header = struct.pack(
        "<4sHHIB3x",
        MAGIC, VERSION, YO_FOLDED, word_count, max_len,
    )
    assert len(header) == 16, f"header must be 16 bytes, got {len(header)}"

    # length table: offset (относительно начала WordBlock) + count, для L=1..max_len
    length_table = b""
    word_block = bytearray()
    offset = 0
    for L in range(1, max_len + 1):
        bucket = encoded_by_len.get(L, [])
        count = len(bucket)
        length_table += struct.pack("<II", offset, count)
        for cw in bucket:
            word_block += cw
        offset += L * count

    with open(out_path, "wb") as f:
        f.write(header)
        f.write(length_table)
        f.write(word_block)

    return {
        "word_count": word_count,
        "max_len": max_len,
        "file_size": 16 + len(length_table) + len(word_block),
        "by_len_counts": {L: len(encoded_by_len.get(L, [])) for L in range(1, max_len + 1)},
    }


# --- Round-trip чтение (та же логика, что и предполагаемый Swift-ридер) -

def read_binary(path):
    with open(path, "rb") as f:
        data = f.read()

    magic, version, flags, word_count, max_len = struct.unpack_from("<4sHHIB", data, 0)
    if magic != MAGIC:
        raise ValueError(f"bad magic {magic!r}")
    if version != VERSION:
        raise ValueError(f"bad version {version}")

    length_table_off = 16
    word_block_off = 16 + max_len * 8

    lengths = []
    for L in range(1, max_len + 1):
        off, count = struct.unpack_from("<II", data, length_table_off + (L - 1) * 8)
        lengths.append((L, off, count))

    words = []
    for L, off, count in lengths:
        base = word_block_off + off
        for i in range(count):
            chunk = data[base + i * L: base + (i + 1) * L]
            word = "".join(ALPHABET[b] for b in chunk)
            words.append(word)

    return {
        "version": version,
        "flags": flags,
        "word_count": word_count,
        "max_len": max_len,
        "words": words,
    }


def round_trip_check(out_path, words_set, sample_size=1000, seed=1234):
    result = read_binary(out_path)
    if result["word_count"] != len(words_set):
        return False, f"word_count mismatch: header={result['word_count']} actual_set={len(words_set)}"
    if len(result["words"]) != len(words_set):
        return False, f"decoded count mismatch: decoded={len(result['words'])} expected={len(words_set)}"

    decoded_set = set(result["words"])
    if decoded_set != words_set:
        missing = words_set - decoded_set
        extra = decoded_set - words_set
        return False, f"set mismatch: missing={len(missing)} extra={len(extra)} (sample missing={list(missing)[:5]})"

    rng = random.Random(seed)
    sample = rng.sample(list(words_set), min(sample_size, len(words_set)))
    for w in sample:
        if w not in decoded_set:
            return False, f"sample word missing after round-trip: {w!r}"

    return True, f"OK: {len(words_set)} слов, полный набор совпал, выборка {len(sample)} проверена"


# --- main -----------------------------------------------------------------

def main():
    os.makedirs(RESOURCES_DIR, exist_ok=True)
    os.makedirs(DOCS_DIR, exist_ok=True)

    # Источник 1: OpenCorpora (основной, ~3.02M форм, CC-BY-SA).
    oc_raw_lines = ensure_opencorpora_forms()
    oc_words_set, oc_norm_stats = normalize_words(oc_raw_lines)
    print(f"[opencorpora] сырых строк: {len(oc_raw_lines)}")
    print(f"[opencorpora] уникальных слов после фильтра: {oc_norm_stats['unique_kept']}")

    # Источник 2: Лебедев (ru_RU, hunspell, BSD) — добавляет формы, которых
    # нет в OpenCorpora.
    aff_path, dic_path = ensure_source_dict()
    leb_raw_lines = unmunch_words(aff_path, dic_path)
    leb_words_set, leb_norm_stats = normalize_words(leb_raw_lines)
    print(f"[lebedev] уникальных слов после фильтра: {leb_norm_stats['unique_kept']}")

    # Union потоково через set — оба источника уже дедуплены по отдельности.
    words_set = oc_words_set | leb_words_set
    only_in_lebedev = len(leb_words_set - oc_words_set)
    only_in_opencorpora = len(oc_words_set - leb_words_set)

    norm_stats = {
        "dropped_bad_chars": oc_norm_stats["dropped_bad_chars"] + leb_norm_stats["dropped_bad_chars"],
        "dropped_too_long": oc_norm_stats["dropped_too_long"] + leb_norm_stats["dropped_too_long"],
        "dropped_empty": oc_norm_stats["dropped_empty"] + leb_norm_stats["dropped_empty"],
        "unique_kept": len(words_set),
        "opencorpora_unique": oc_norm_stats["unique_kept"],
        "lebedev_unique": leb_norm_stats["unique_kept"],
        "only_in_lebedev": only_in_lebedev,
        "only_in_opencorpora": only_in_opencorpora,
    }

    print(f"[union] OpenCorpora ∪ Лебедев = {norm_stats['unique_kept']}")
    print(f"[union] только в Лебедеве (доп. ценность): {only_in_lebedev}")
    print(f"[union] только в OpenCorpora: {only_in_opencorpora}")
    print(f"[normalize] отброшено (не-алфавит): {norm_stats['dropped_bad_chars']}")
    print(f"[normalize] отброшено (>maxLen): {norm_stats['dropped_too_long']}")
    print(f"[normalize] отброшено (пустые): {norm_stats['dropped_empty']}")

    coverage_pct, present, missing = coverage_check(words_set)
    garbage_pct, garbage_sample_n = garbage_estimate(words_set)

    print(f"[validate] покрытие частотных слов: {coverage_pct:.1f}% ({len(present)}/{len(FREQUENT_PROBE)})")
    if missing:
        print(f"[validate] отсутствуют: {missing}")
    print(f"[validate] оценка доли мусора (эвристика): {garbage_pct:.2f}% на выборке {garbage_sample_n}")

    pack_stats = pack_binary(words_set, OUT_BIN)
    file_size_mb = pack_stats["file_size"] / (1024 * 1024)
    print(f"[pack] N={pack_stats['word_count']} maxLen={pack_stats['max_len']} "
          f"size={pack_stats['file_size']} bytes ({file_size_mb:.2f} MB)")

    ok, rt_message = round_trip_check(OUT_BIN, words_set)
    print(f"[round-trip] {'OK' if ok else 'FAIL'}: {rt_message}")
    if not ok:
        sys.exit(f"Round-trip самопроверка провалилась: {rt_message}")

    # Companion-файл для Track B.
    rng = random.Random(9999)
    sample_1000 = rng.sample(list(words_set), min(1000, len(words_set)))
    sample_1000.sort()
    with open(OUT_SAMPLE, "w", encoding="utf-8") as f:
        for w in sample_1000:
            f.write(w + "\n")
    print(f"[sample] записано {len(sample_1000)} слов в {OUT_SAMPLE}")

    write_report(
        pack_stats=pack_stats,
        norm_stats=norm_stats,
        coverage_pct=coverage_pct,
        present=present,
        missing=missing,
        garbage_pct=garbage_pct,
        garbage_sample_n=garbage_sample_n,
        file_size_mb=file_size_mb,
        rt_ok=ok,
        rt_message=rt_message,
        oc_raw_line_count=len(oc_raw_lines),
        leb_raw_line_count=len(leb_raw_lines),
    )
    print(f"[report] записан {OUT_REPORT}")
    print("[done] генерация завершена успешно")


def write_report(*, pack_stats, norm_stats, coverage_pct, present, missing,
                  garbage_pct, garbage_sample_n, file_size_mb, rt_ok, rt_message,
                  oc_raw_line_count, leb_raw_line_count):
    by_len = pack_stats["by_len_counts"]
    hist_lines = []
    for L in sorted(by_len.keys()):
        c = by_len[L]
        if c == 0:
            continue
        bar = "#" * max(1, min(60, c // 500))
        hist_lines.append(f"| {L} | {c} | {bar} |")

    report = f"""# Отчёт генератора словаря анаграмайзера

## Источники и лицензии

См. полные подробности в [`docs/LICENSE-dict.md`](./LICENSE-dict.md) и
[`docs/anagramizer-dict-candidates.md`](./anagramizer-dict-candidates.md).

Комбинированный словарь = **OpenCorpora ∪ Лебедев** (объединение множеств
словоформ):

1. **OpenCorpora** (основной источник) — выверенный морфологический словарь,
   получен из готового скомпилированного пакета `pymorphy2-dicts-ru`
   (та же ревизия словаря OpenCorpora, source: opencorpora.org). Лицензия
   данных: **CC-BY-SA**. Сырых ключей DAWG-словаря: {oc_raw_line_count}.
   После нормализации: **{norm_stats['opencorpora_unique']}** уникальных форм.
2. **Лебедев** (`ru_RU`, hunspell) — прежний источник, официальный upstream
   `github.com/LibreOffice/dictionaries`. Лицензия: модифицированная 3-clause
   BSD, Copyright (c) 1997-2008 Alexander I. Lebedev. Раскрыт через
   `unmunch ru_RU.dic ru_RU.aff`, сырых строк: {leb_raw_line_count}.
   После нормализации: **{norm_stats['lebedev_unique']}** уникальных форм.

Лебедев добавляет **{norm_stats['only_in_lebedev']}** форм, которых нет в
OpenCorpora (иная обработка ё/е и различия словника) — объединение с ним
даёт реальную ценность сверх одного OpenCorpora
({norm_stats['only_in_opencorpora']} форм есть только в OpenCorpora).

**Итоговая лицензия комбинированного словаря: CC-BY-SA** (заражение только от
OpenCorpora-компоненты — ShareAlike распространяется на саму базу словоформ,
а не на код iOS-приложения, которое её использует; см. обоснование в
`docs/LICENSE-dict.md` и `docs/anagramizer-dict-candidates.md`).

## Метод раскрытия и перекодировки

1. **OpenCorpora**: изолированный venv (`.dict-cache/venv`) → `pip install
   pymorphy2-dicts-ru pymorphy2 dawg-python docopt` → `load_dict(...)` →
   перебор всех ключей DAWG (`d.words.iterkeys()`) — это и есть словоформы,
   уже в нижнем регистре UTF-8.
2. **Лебедев**: `unmunch ru_RU.dic ru_RU.aff` (системный бинарь
   `/opt/homebrew/bin/unmunch`). `.aff` содержит `SET UTF-8`, перекодировка
   через `iconv` не потребовалась.
3. Нормализация (одинаковая для обоих источников): `lowercase`, оставлены
   только слова из 33 букв алфавита `а..я,ё` (без дефисов/апострофов/
   латиницы/цифр/пробелов), дедуп по отдельности, затем `set` union, отброшены
   слова длиннее {MAX_LEN_CAP} символов.
   - Отброшено по не-алфавитным символам (сумма обоих источников): {norm_stats['dropped_bad_chars']}
   - Отброшено по длине (> {MAX_LEN_CAP}) (сумма обоих источников): {norm_stats['dropped_too_long']}
   - Отброшено пустых строк (сумма обоих источников): {norm_stats['dropped_empty']}
   - Итог уникальных слов после union: **{norm_stats['unique_kept']}**

## Итоговые метрики артефакта

- **N (число слов)**: {pack_stats['word_count']}
- **maxLen**: {pack_stats['max_len']}
- **Размер файла**: {pack_stats['file_size']} байт (~{file_size_mb:.2f} МБ)
- **yoFolded**: {YO_FOLDED} (ё сохраняется как отдельный код 6)
- **Путь артефакта**: `encx-cli/Resources/ru_dict.bin`

## Распределение по длинам слов

| Длина L | Кол-во слов | Гистограмма (1 # ≈ 500 слов) |
|---|---|---|
{chr(10).join(hist_lines)}

## Покрытие частотных слов

Проверочный список из {len(FREQUENT_PROBE)} частотных лемм/форм: покрытие
**{coverage_pct:.1f}%** ({len(present)}/{len(FREQUENT_PROBE)}).

{"Отсутствуют: " + ", ".join(missing) if missing else "Все проверочные слова найдены."}

## Оценка "мусора"

Эвристика: слово считается подозрительным, если содержит 5+ согласных подряд
(без гласных/й) или невозможные сочетания вида «ъь»/«ьъ»/«ыъ». На случайной
выборке {garbage_sample_n} слов доля подозрительных: **{garbage_pct:.2f}%**.

Решение: специальный пост-фильтр мусора **не применялся** — доля в пределах
единиц процента, что для словаря на 33-буквенном алфавите с раскрытыми
словоформами (падежи/формы глаголов дают длинные, но валидные слова с
скоплениями согласных, например «встретившимся») ожидаемо и не является
признаком повреждения. `unmunch` иногда генерирует несуществующие формы для
редких флагов — они остаются в словаре как избыточные, но не искажают формат
и не блокируют функциональность (движок ищет подмножества/анаграммы, лишние
валидные по алфавиту записи не критичны для v1).

## Round-trip самопроверка

Статус: **{"OK" if rt_ok else "FAIL"}**

{rt_message}

Проверка: файл прочитан обратно тем же контрактом (`ANGR` header → length table →
word block), полный декодированный набор слов сверен с нормализованным множеством
(множества совпадают целиком), плюс отдельно проверена случайная выборка 1000 слов.

## Companion-файл для Track B

`docs/anagram-sample-words.txt` — {min(1000, pack_stats['word_count'])} случайных слов
в кириллице, по одному на строку (отсортированы), для независимой проверки ридера
движком.
"""
    with open(OUT_REPORT, "w", encoding="utf-8") as f:
        f.write(report)


if __name__ == "__main__":
    main()
