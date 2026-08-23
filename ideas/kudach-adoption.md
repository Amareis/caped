---
name: kudach-adoption
summary: Первый adopting-проект — kudach: реестр всё-legacy, advisory, первая enforced-капа feed с фасадным пилотом
phase: v0
priority: medium
depends_on: [caped-check, test-hooks, secretary, render]
spawned_from: null
---

## Why

Модель проверена только на самом caped (зелёное поле, два капа). Настоящий тест — переезд существующей
кодовой базы: kudach с его openspec-наследием, 27 фича-модулями и историей «спеки болтаются сбоку».

## Context

Ретро-замер по истории kudach (скрипт classification report живёт в `scripts/`): ~7% подозрительных коммитов,
концентрация в web_version — отсюда advisory-first роллаут и первый пилот на feed (замеры 79/4 публичных
символов). Фасады: mod.rs объявляет сабмодули приватными, наружу — явные pub use; задуманные поверхности
(commands, workflow, mcp, telegram) — фасад по умолчанию.

## Requirements

- PR в kudach: `caped.sh init`, реестр со всеми src/features/* как legacy + технические капы (entities,
   platform, app, ingress), advisory-режим; AGENTS.md получает стаб-указатель на caped.
- Отчёт покрытия как метрика переезда; openspec/ мигрирует: идеи → ideas/, текущие спеки — в README капов
   (по одному, по мере флипа в enforced), changes/ — как есть.
- Первая enforced-капа — feed: README капы из openspec-спеки + код, фасадный пилот (приватные сабмодули,
   pub use; разбор хелперов categories/formatting по замерам пилота).
- Калибровка: 1–2 недели advisory, разбор ложных срабатываний, затем решение о blocking.

## Decisions

—

## Rejected alternatives

—

## Provenance

Человек: «путь переезда надо предусмотреть, чтобы капабилити вводились по очереди, а непокрытые тул игнорил»;
пилот на feed и исключение web_version — из ретро-замера (см. корневой README, променанс). Агент: depends_on
check+test-hooks — тянуть непроверенный тул в чужую кодовую базу без verify-инфраструктуры нельзя, репутационная
цена первого неправильного отказа хука высока. Позже добавлен secretary: агенты в kudach будут работать по
дампу, а не по README тула — с непроверенно-полным дампом они получат неполные правила.

## Open questions

- Судьба openspec-скиллов и validate-шага в kudach после миграции.
- Хранить ли caped как сабмодуль/копию scripts/ в kudach, или ставить тул глобально.
