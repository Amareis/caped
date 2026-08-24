---
name: idea-withdrawn-event
summary: Событие idea-withdrawn в шиме — снятие идеи (D ideas/*.md + Archives:) даёт факт в ленту; сейчас шим молчит (кейс 2026-08-24: kimi-code-plugin снят без события)
phase: v0.1
priority: medium
depends_on: []
spawned_from: multiagent-events
---

## Why

Снятие идеи (D ideas/*.md + `Archives:`) событие в фиде НЕ эмитит: ветка archived
в post_commit ловит только `D changes/<ent>.md`, снятие проваливается сквозь все
ветки в тишину. Живой кейс 2026-08-24: снятие kimi-code-plugin (релей соседу)
прошло без факта в ленте — для параллельных агентов снятие/передача невидимы,
как было с правками `_backlog` до backlog-edited.

## Context

Требование добавлено в multiagent-events 2026-08-24 (хэндофф по правилу
территории): «лента обязана показывать снятие/передачу — событие idea-withdrawn
в шиме (или фиксация в derived-view render events)». Человек решил: фикс
архивации — сразу, мултиагент-рендер — потом. Шим: после archived-ветки добавляем
ветку на `D ideas/<ent>.md`; архивный коммит (D changes/) остаётся archived —
граница dominant-событий.

## Requirements

- Шим: `Archives: <ent>` + `D ideas/<ent>.md` → событие `idea-withdrawn` в ленту
  (и диспатч `.caped/hooks/idea-withdrawn` по общей схеме); `D changes/` не трогаем —
  там archived.
- Список типов событий в спеке (README `[#event-feed]`, `[#idea-archival]`) и дампе
  пополняется; `[#idea-archival]` упоминает событие.
- Тест: сценарий в tests/events — снять идею с `Archives:`, фид содержит
  `idea-withdrawn`.

## Decisions

- Сейчас — событие в шиме, а не только фиксация в будущем derived-view: потребители
  фида (плагин соседа) работают на событиях сейчаs; render events — отдельный чейндж
  multiagent-events.
- Новых маркеров не вводим: событийная норма уже покрыта дефами `[#event-feed]` /
  `[#idea-archival]` — правки текста, не новые определения.

## Rejected alternatives

- Только derived-view фиксация: фид остаётся без факта до чейнджа multiagent-events —
  потребители ленты (плагин) не узнают о релеях в принципе. Отклонено.
- Новый деф `[#idea-withdrawn-event dump]` + маркер в дампе: избыточно — событие —
  фасад уже существующих правил (архивация идеи, лента событий). Отклонено.

## Provenance

Человек (2026-08-24): «Давай правку по архивации идеи сделаем наверное сразу, тут
все сразу понятно, а вот по мультиагентности и мультирепности я подумаю пока».

Додумано агентом (с основаниями): ветка после archived — основания: dominant-
события; коммит, удаляющий и changes/ и ideas/ одного имени, редок, archived выигрывает.

## Open questions

—