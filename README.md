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

Reference sources under `resources/` are declared in `phora.toml` and resolved by `phora.lock`. Git sources can retain history; URL sources are integrity-pinned by digest:

```sh
phora sync
```

Advance every source with `phora update`, or one source with `phora update <source>`.

## Languages

- *[Python](languages/python/)* — Types first, composition over inheritance, feature-based organization
- *[Go](languages/go/)* — Interfaces for abstraction, packages for namespacing, errors as values
- *[Emacs Lisp](languages/elisp/)* — Functional core, explicit editor effects, lexical binding

## Principles

These guides share common themes:

- *Naming over comments* — Spend 5x more time on names than comments
- *Composition over inheritance* — Even in languages that support inheritance
- *Feature-based organization* — Group by domain, not technical layer
- *Parse at boundaries* — Accept permissive input, convert to strict types immediately
- *Explicit over implicit* — Make intent clear through code structure
