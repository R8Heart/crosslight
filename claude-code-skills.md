# Скиллы для Claude Code — подборка

## Игры (общее + Godot)

- **[awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)** — 67 скиллов на все движки (Godot, Unity, Unreal, Phaser, three.js, Bevy и др.) с автороутером под движок и задачу.
  `claude plugin install godot@awesome-gamedev-agent-skills`

- **[GodotPrompter](https://github.com/jame581/GodotPrompter)** — 55 скиллов конкретно под Godot 4.x: state machines, мультиплеер, шейдеры, оптимизация, процедурная генерация. Построен поверх Superpowers.

- **[Godot-Claude-Skills](https://github.com/Randroids-Dojo/Godot-Claude-Skills)** — упор на тестирование: GdUnit4 (юнит/сценарные тесты) + "PlayGodot" — аналог Playwright для автоматизации геймплея.

- **[Godot-Skills](https://github.com/fenixnix/Godot-Skills)** — узкие практические скиллы: удаление дочерних нод, TSCN-формат, паттерн синглтона, пул объектов.

## Веб-дизайн / фронтенд

- **[ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** — ~100 формализованных правил дизайн-мышления + 67 готовых UI-стилей/пресетов.

- **[awesome-claude-skills (ComposioHQ)](https://github.com/ComposioHQ/awesome-claude-skills)** — каталог 1000+ скиллов; из интересного — D3.js-визуализации, автоматизация реального Chrome без Playwright/MCP.

## Память / мышление / экономия токенов

- **[caveman](https://github.com/JuliusBrussee/caveman)** — вирусный скилл (89k+ звёзд): Клод отвечает предельно сжато, без вводных слов и артиклей. Реальное сокращение output-токенов ~65%, три уровня (`lite/full/ultra`), есть экспериментальный режим на классическом китайском для ещё большей компрессии.
  Форк под claude.ai (веб/десктоп, не Claude Code): **[caveman-skill](https://github.com/3idhMind/caveman-skill)**

- **[superpowers](https://github.com/obra/superpowers)** — библиотека методологии работы: TDD, систематический дебаг в 4 фазы, "verification-before-completion" (проверка, что баг реально исправлен). Одна из самых авторитетных в экосистеме.

- **[claude-mem](https://github.com/thedotmack/claude-mem)** — сжимает историю сессии AI-компрессией и подгружает контекст в начале новой сессии. Решает проблему "каждая сессия начинается с нуля".

- **[claude-code-token-optimization](https://github.com/khasky/claude-code-token-optimization)** — не скилл, а разбор: что реально жрёт контекст (конфиги, лишние MCP, устаревшая память) и какие инструменты решают каждый слой отдельно.

---

**Куда класть:**
- Глобально (все проекты): `~/.claude/skills/<имя>/`
- Только для проекта: `.claude/skills/<имя>/` внутри репозитория
- Если оформлено как плагин-маркетплейс — команда `/plugin marketplace add owner/repo` есть в README репозитория

**Рекомендация под твои задачи (Pu1se в Godot):** начать с GodotPrompter или Godot-Claude-Skills + claude-mem для непрерывности между сессиями, и попробовать caveman lite для экономии токенов на рутинных задачах.
