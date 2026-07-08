# Лицензия исходного словаря

Комбинированный словарь анаграмайзера (US-2) собран из **двух источников**:
**OpenCorpora** (основной, ~3.02M форм) и **Лебедев** (`ru_RU`, ~1.25M форм,
добавляет 153 149 форм, которых нет в OpenCorpora). См. измерения и метод
выбора в [`docs/anagramizer-dict-candidates.md`](./anagramizer-dict-candidates.md).

**Итоговая лицензия комбинированного словаря: CC-BY-SA** (наследуется от
OpenCorpora — ShareAlike распространяется на саму базу словоформ, см. раздел
«Вердикт по App Store» ниже; лицензия Лебедева отдельно указана для его части).

---

## Источник 1: OpenCorpora (основной)

### Источник

- **Проект**: словарь OpenCorpora, получен из готового скомпилированного
  пакета `pymorphy2-dicts-ru` (PyPI) — это та же ревизия словаря OpenCorpora
  (`source_version 0.92`, `source: opencorpora.org`, ревизия 417127,
  подтверждено в `meta.json` пакета), а не пересборка третьей стороной.
- **Метод получения**: `pip install pymorphy2-dicts-ru pymorphy2 dawg-python
  docopt` в изолированный venv → `load_dict(pymorphy2_dicts_ru.get_path())` →
  перебор всех ключей DAWG-словаря (`d.words.iterkeys()`) — это словоформы.
  Прямой экспорт с `opencorpora.org` (`dict.opcorpora.txt.bz2`) на момент
  исследования недоступен (Cloudflare error 522, origin down) — использован
  этот рабочий путь.
- **Дата получения**: 2026-07-08.
- Сырых ключей DAWG: 5 140 055. После нормализации (33 буквы, lowercase,
  дедуп, ≤40 символов): **3 022 245** уникальных словоформ.

### Лицензия

- **Пакет-обёртка** `pymorphy2-dicts-ru`: `License: MIT license` (из METADATA
  пакета) — но это покрывает только скрипты сборки/упаковки, **не сами
  данные**. Официальное README проекта (`kmike/pymorphy2-dicts`) прямо
  указывает: *«For Russian it downloads data from http://opencorpora.org»*.
- **Данные OpenCorpora**: распространяются под **Creative Commons
  Attribution-ShareAlike (CC-BY-SA)** — общепринятая и повсеместно
  цитируемая лицензия словаря OpenCorpora при его редистрибуции. (Отдельно от
  движка аннотирования `OpenCorpora/opencorpora` на GitHub, который под
  GPL-2.0 и к словарю форм не относится.) Точную минорную версию (обычно 3.0)
  на самом сайте OpenCorpora подтвердить не удалось из-за недоступности origin
  (522) в момент исследования — но принадлежность семейству CC-BY-SA
  зафиксирована в документации pymorphy2 и многочисленных легитимных
  редистрибуциях этого датасета.

### Вердикт по App Store

**Совместимо**, при выполнении условий CC-BY-SA:

1. **Атрибуция** — обязательна: указать OpenCorpora + лицензию CC-BY-SA на
   экране «О программе»/лицензии (см. «Текст атрибуции для UI» ниже).
2. **ShareAlike** — производный словарь (`ru_dict.bin`, собранный из
   OpenCorpora-словоформ, отфильтрованных и перепакованных в бинарный формат)
   считается адаптацией **базы данных** и должен быть доступен под той же
   CC-BY-SA (на практике: приложить лицензию к артефакту, быть готовым
   раскрыть производный словарь/генератор по запросу — сам генератор
   `scripts/gen_anagram_dict.py` уже открыт в репозитории).
3. **Код приложения НЕ заражается** — ShareAlike распространяется на базу
   словоформ, а не на закрытый исходный код iOS-приложения, которое лишь её
   *использует*. Бинарный формат ANGR — упаковка данных, не производное ПО.

---

## Источник 2: Лебедев (`ru_RU`, hunspell)

### Источник

- **Проект**: `ru_RU` hunspell-словарь из официального репозитория LibreOffice dictionaries
  (`github.com/LibreOffice/dictionaries`, каталог `ru_RU/`), файлы `ru_RU.aff` и `ru_RU.dic`.
- **URL исходников**:
  - https://raw.githubusercontent.com/LibreOffice/dictionaries/master/ru_RU/ru_RU.aff
  - https://raw.githubusercontent.com/LibreOffice/dictionaries/master/ru_RU/ru_RU.dic
  - https://raw.githubusercontent.com/LibreOffice/dictionaries/master/ru_RU/README_ru_RU.txt
- **Дата скачивания**: 2026-07-08.
- **Автор**: Alexander I. Lebedev (классический русский словарь для ispell/hunspell, используется
  как системный словарь `ru_RU` в OpenOffice/LibreOffice и многих Linux-дистрибутивах).
  Модификация 2012-08-24 — Laszlo Nemeth (добавление строки `TRY` в `.aff` для улучшения подсказок,
  на состав словника не влияет).
- Раскрыт через `unmunch ru_RU.dic ru_RU.aff`: 1 290 243 сырых строки. После
  нормализации: **1 254 910** уникальных форм, из них **153 149** отсутствуют
  в OpenCorpora (иная обработка ё/е и различия словника) — реальное дополнение.

Локально на машине генератора (`/System/Library/Spelling`, `/Library/Spelling`,
`/opt/homebrew/share/hunspell`, вывод `brew list hunspell`, полнодисковый `find`) файлов
`ru_RU.aff`/`ru_RU.dic` найдено не было — используется указанный выше upstream-репозиторий
как canonical источник того же самого словаря Лебедева.

### Лицензия (дословно из `README_ru_RU.txt`)

```
* Copyright (c) 1997-2008, Alexander I. Lebedev

Modifications:
------------------------------------------------------------------
2012-08-24: Laszlo Nemeth (nemeth at numbertext org)
* ru_RU.aff: add TRY line for better suggestions
  (fix fdo#35001, reported by sasha.libreoffice at gmail)

Copyright:
------------------------------------------------------------------
* Copyright (c) 1997-2008, Alexander I. Lebedev

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Modified versions must be clearly marked as such.
* The name of Alexander I. Lebedev may not be used to endorse or promote
  products derived from this software without specific prior written
  permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

Это модифицированная 3-clause BSD-подобная лицензия (с дополнительным условием: изменённые
версии должны быть явно помечены как таковые, плюс запрет использовать имя автора для
продвижения производных продуктов без разрешения). Совместима с встраиванием производного
бинарного артефакта (`ru_dict.bin`) в приложение при условии сохранения этого уведомления
об авторстве в составе документации проекта (данный файл выполняет эту роль).

---

## Вывод в артефакт

`encx-cli/Resources/ru_dict.bin` — это **производный** артефакт от объединения
словоформ OpenCorpora и Лебедева: раскрытые/извлечённые словоформы обоих
источников, отфильтрованные, объединённые через `set` union и перекодированные
в бинарный формат ANGR v1 (см. `docs/anagramizer-binary-format.md`). Оба
копирайт-уведомления сохранены в этом документе согласно условиям обеих
лицензий.

Условие лицензии Лебедева «Modified versions must be clearly marked as such»
выполняется этим документом: артефакт `ru_dict.bin` явно задекларирован как
**модифицированная версия** — не побайтовая копия ни `ru_RU.aff`/`ru_RU.dic`,
ни оригинального DAWG-словаря OpenCorpora.

## Текст атрибуции для UI

Готовый к вставке текст для экрана «О программе»/Settings (используется как есть, дословно,
без перевода — обе лицензии требуют сохранения текста уведомлений в оригинальном виде).

Короткая форма (для компактного экрана, оба источника):

```
Словарь: содержит данные OpenCorpora (© OpenCorpora contributors, CC BY-SA)
и словарь © 1997–2008 Alexander I. Lebedev (лицензия BSD, модифицированная версия).
```

Полная форма (если в UI есть место под разворачиваемый блок «подробнее»/отдельный экран
лицензий) — обязательный минимум по условиям обеих лицензий:

```
Russian dictionary data: OpenCorpora (http://opencorpora.org), licensed under
Creative Commons Attribution-ShareAlike (CC BY-SA). This application includes
a modified/adapted version of the OpenCorpora word-form database, repackaged
into a binary format. The adapted database is available under the same
CC BY-SA license.

Additional dictionary data: Copyright (c) 1997-2008, Alexander I. Lebedev.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:
* Redistributions of source code must retain the above copyright notice, this list of
  conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of
  conditions and the following disclaimer in the documentation and/or other materials
  provided with the distribution.
* Modified versions must be clearly marked as such.
* The name of Alexander I. Lebedev may not be used to endorse or promote products derived
  from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Эта версия дистрибутива — модифицированная (словоформы обоих источников,
отфильтрованные, объединённые и перепакованные в бинарный формат ANGR v1),
что соответствует условиям обеих лицензий (ShareAlike у OpenCorpora,
«Modified versions must be clearly marked as such» у Лебедева).

## Риски

- **OpenCorpora**: прямой экспорт с `opencorpora.org` был недоступен на момент
  генерации (Cloudflare 522) — использован опосредованный, но canonical путь
  через `pymorphy2-dicts-ru` (та же ревизия словаря, подтверждено в
  `meta.json` пакета). Точная минорная версия CC-BY-SA (обычно 3.0) не
  подтверждена напрямую с сайта из-за недоступности origin, но принадлежность
  семейству CC-BY-SA — многократно задокументированный факт в экосистеме
  pymorphy2/OpenCorpora.
- **ShareAlike-обязательство**: комбинированный словарь (в том числе часть от
  Лебедева) распространяется как единая база под CC-BY-SA — это осознанный
  компромисс ради существенно большего покрытия словоформ (~3.18M против
  1.25M). Код iOS-приложения не заражается.
- **Лебедев**: прямого файла LICENSE в каталоге `ru_RU/` репозитория нет — текст лицензии
  зафиксирован в `README_ru_RU.txt`, который является частью того же официального
  дистрибутива и распространяется вместе с `.aff`/`.dic`. Риск неоднозначности минимальный:
  это общеизвестный, десятилетиями используемый в открытых системах
  (OpenOffice/LibreOffice/apt `hunspell-ru`) словарь с известной атрибуцией.
