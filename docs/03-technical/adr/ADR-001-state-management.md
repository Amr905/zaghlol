# ADR-001: State management & dependency injection

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | CLAUDE.md §8; architecture §4.5 |

## Context
The app has about 25 feature modules, background isolates, a headless ingestion engine and heavy testing needs (domain tests without Flutter, provider overrides in widget tests). CLAUDE.md prefers Riverpod.

## Options considered
1. **Riverpod 3 (+ generator)** — Compile-safe providers; DI and state in one tool; easy overrides in tests; async notifiers; works outside widgets (headless engine). Code generation adds a build step.
2. **Bloc / Cubit** — Explicit events and states; verbose for about 25 modules; DI needs a separate tool (get_it).
3. **Provider + get_it** — Simple, but runtime lookup errors and weaker async patterns.

## Decision
**Riverpod 3.x** with `riverpod_generator`. Repositories, use cases and view models are providers. The domain stays framework-free: Riverpod lives only in `app/`.

## Consequences
One pattern across the app. Tests override providers. The team must follow the `ref.watch` / `ref.read` rules, enforced by lints (`riverpod_lint`).
