# loqui

*Build with consequence*  
*Code with eloquence and style*

> *loquī* • present active infinitive of *loquor*; third conjugation
>
> Pronunciation: /ˈɫɔ.kʷiː/ (Classical), /ˈlɔː.kʷi/ (Ecclesiastical)
>
> to speak, to talk, to say

The root gives us *eloquence*, *colloquial*, *loquacious*, and *soliloquy*.

## About

Modern language guidelines for the age of AI. Opinionated style guides that help both humans and AI assistants write better code.

## Resources

[Phora](https://github.com/srnnkls/phora) manages reference snapshots under `resources/`, declared in `phora.toml` and pinned in `phora.lock`. The configuration requires Phora 0.2.0, pinned in [mise.toml](mise.toml). Git mirrors live in Phora's cache; URL sources are integrity-pinned by digest. Git bindings disable template rendering and use per-file snapshots to preserve source files and names:

```sh
mise install github:srnnkls/phora
mise exec -- phora sync --frozen
```

Advance every source with `mise exec -- phora update`, or one source with `mise exec -- phora update <source>`.

The Rust collection in `resources/languages/rust/` includes API Guidelines, Rust Design Patterns, Idiomatic Rust, and these language and implementation references:

| Source | Local directory | Useful for studying |
| --- | --- | --- |
| [The Rust Book](https://github.com/rust-lang/book) | `rust-book/` | Ownership, lifetimes, traits, and language fundamentals |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `ripgrep/` | CLI and library boundaries, ownership, builders, and streaming I/O |
| [redb](https://github.com/cberner/redb) | `redb/` | Transaction APIs, typed tables, storage, and durability |
| [Tokio](https://github.com/tokio-rs/tokio) | `tokio/` | Async tasks, synchronization, cancellation, and runtime design |
| [Serde](https://github.com/serde-rs/serde) | `serde/` | Trait contracts, borrowed deserialization, visitors, and derive macros |

Use these implementations as contextual examples when assessing the guides; their choices reflect different API and performance requirements. The manifest excludes upstream symlink aliases in Patterns, ripgrep, and Serde while retaining their target files. These snapshots are intended for source review; building upstream packages may require restoring those aliases.

`mise exec -- phora verify` checks deployed contents against the recorded digests. The `resources/` tree is Git-ignored; commit manifest and lock changes to make additions reproducible.

## Languages

- *[Python](languages/python/)* — Types first, composition over inheritance, feature-based organization
- *[Go](languages/go/)* — Interfaces for abstraction, packages for namespacing, errors as values
- *[Rust](languages/rust/)* — Ownership, domain types, explicit errors, trait-based composition
- *[Zig](languages/zig/)* — Bounded state transitions, explicit ownership, executable invariants
- *[Bash](languages/bash/)* — Command patterns, shell scripting, explicit error handling
- *[Emacs Lisp](languages/elisp/)* — Functional core, explicit editor effects, lexical binding

## Principles

These guides share common themes:

- *Naming over comments* — Spend 5x more time on names than comments
- *Composition over inheritance* — Even in languages that support inheritance
- *Feature-based organization* — Group by domain, not technical layer
- *Parse at boundaries* — Accept permissive input, convert to strict types immediately
- *Explicit over implicit* — Make intent clear through code structure
