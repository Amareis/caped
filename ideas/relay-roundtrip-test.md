---
name: relay-roundtrip-test
summary: Тест директ-релея туда-обратно — верни идею обратно в caped через caped relay, финальная копия архивируется
---

## Why

Проверка директ-релея в обе стороны (2026-08-24): идея посылается БЕЗ домашних
коммитов, принимается у соседа, возвращается тем же механизмом.

## Context

Для возврата (на стороне получателя):
1. В корне своей репы добавь `caped.neighbors` со строкой
   `caped<TAB>/Users/joe/work/caped<TAB>plugin` (TAB-формат, больше ничего не надо).
2. Затем: `CAPED_AGENT=<твой id> caped relay caped relay-roundtrip-test`
   (директ-режим: локальный файл незакоммичен → соседу уйдёт один коммит, дома
   ноль коммитов; локальная копия удалится — можно `--keep`).
3. Приёмщик (caped) финальную копию архивирует: `Archives: relay-roundtrip-test`,
   причина — тест релея в обе стороны.

## Requirements

-

## Decisions

-

## Rejected alternatives

-

## Provenance

Инициирован человеком (2026-08-24): «директ релеем ему тестовую идею отправь,
пусть он тебе ее вернет и ты заархивируешь уже».

## Open questions

-
## Handoff

Релей из caped@6ee6ee5 (`caped relay caped-context relay-roundtrip-test`, 2026-08-24); происхождение — /Users/joe/work/caped.

## Handoff

Релей из caped-context@83dff98 (`caped relay caped relay-roundtrip-test`, 2026-08-24); происхождение — /Users/joe/work/caped-context.
