---
paths: "**/*.go, **/go.mod, **/go.work"
---

# Go Style Guide

Design and implementation guidance for modern Go. Examples target Go 1.27 and were checked with Go 1.27.1 on 14 September 2026. Feature introductions are identified where compatibility matters; use the project's declared minimum version when changing an existing module.

Start with the contract: what an operation reads, retains, mutates, returns, and releases. Use current language and standard-library facilities when they preserve that contract. Preferences below are defaults; language restrictions and API preconditions are identified explicitly.

| Guide                                | Use it for                                                            |
| ------------------------------------ | --------------------------------------------------------------------- |
| [composition.md](composition.md)     | Interfaces, structs, receivers, ownership, and fallible iterators     |
| [generics.md](generics.md)           | Type relationships, constraints, aliases, and generic methods         |
| [errors.md](errors.md)               | Error identity, inspection, wrapping, recovery, and closing resources |
| [concurrency.md](concurrency.md)     | Goroutine lifetimes, cancellation, synchronization, and memoization   |
| [test.md](test.md)                   | Tests, cleanup, virtual time, benchmarks, fuzzing, and fixtures       |
| [quality.md](quality.md)             | Naming, documentation, zero values, and validation                    |
| [modules.md](modules.md)             | Package boundaries, internal visibility, tools, and workspaces        |
| [modernization.md](modernization.md) | Version-aware upgrades, `go fix`, and semantic migration conditions   |
| [resources.md](resources.md)         | Authoritative references and examples from Go, Pebble, and bbolt      |

The main defaults are:

- Keep APIs focused. Use interfaces to describe behavior and type parameters to preserve useful type relationships.
- Document ownership and mutation of slices, maps, and other shared data. Passing a value does not necessarily copy its backing storage.
- Return errors for expected failures. Preserve inspection of underlying errors when that is part of the API contract.
- Give goroutines a known lifetime. Propagate cancellation where it can take effect and arrange any required join.
- Choose synchronization to protect invariants. Avoid unnecessary blocking under shared locks without breaking serialization.
- Make resource lifetime explicit. Close files, response bodies, iterators, and transactions according to their contracts.
- Prefer useful zero values where practical, and constructors where dependencies or invariants require initialization.
- Document exported APIs and non-obvious constraints. Clear names do not replace ownership, error, or concurrency documentation.
- Use native formatting, analysis, and focused tests. Preview modernization changes and inspect their effects.

A current compiler does not automatically raise a library's minimum supported Go version. Follow [modules.md](modules.md) for the `go` and `toolchain` directives and [modernization.md](modernization.md) for applying fixes to the appropriate build configurations. Experimental APIs belong in an explicitly experimental project or a dated watchlist.

Consult the [source catalog](resources.md) when a rule needs a concrete example or a language/API fact needs verification. Organizational style guides supplement the specification and package contracts.
