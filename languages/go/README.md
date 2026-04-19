---
paths: "**/*.go, **/go.mod"
---

# Go Style Guide

Language-specific patterns, anti-patterns, and best practices for writing modern Go (target: 1.26+).

**Start here:** [modernization.md](modernization.md) — run `go fix ./...` after every code-gen session. AI agents systematically produce obsolete Go idioms; modernizers fix them in seconds.

---

## Quick Reference

| Resource | When to Use |
|----------|-------------|
| [modernization.md](modernization.md) | `go fix`, AI-drift guidance, 1.21–1.26 feature tour, stdlib-first migration |
| [quality.md](quality.md) | Naming, comments, documentation, conventions |
| [composition.md](composition.md) | Structs vs interfaces, methods, embedding, iterators |
| [generics.md](generics.md) | Type parameters, constraints, when to prefer generics |
| [concurrency.md](concurrency.md) | Goroutines, channels, context, `sync.OnceFunc`, structured concurrency |
| [test.md](test.md) | Table tests, `t.Context`, `testing.B.Loop`, fuzzing, `testing/synctest` |
| [modules.md](modules.md) | Package structure, `go.mod` tool directives, workspaces |
| [errors.md](errors.md) | `errors.Join`, wrapping with `%w`, sentinel and custom error types |

---

## Core Principles

### 1. Naming Over Comments (5x Rule)
Spend 5x more time finding good names than writing comments. Comments explain WHY, not WHAT.

### 2. Composition, Not Inheritance
Go has no inheritance. Use interfaces for runtime polymorphism, generics for compile-time parametricity, composition for structure. Keep interfaces small.

### 3. Packages for Organization
Use packages for namespacing, not empty structs. Organize by domain feature, not technical layer.

### 4. Errors Are Values
Return errors explicitly. Check immediately. Wrap with `%w`. Combine multiple errors with `errors.Join` (Go 1.20+) — never `hashicorp/go-multierror`.

### 5. Simplicity
- Package-level functions are first-class (don't wrap in structs)
- Accept interfaces, return structs
- Design for zero values
- Keep interfaces small (1-3 methods)

### 6. Modern Go
Target the current toolchain. Prefer stdlib (`slices`, `maps`, `slog`, `cmp`, `errors.Join`) over third-party equivalents. Run `go fix ./...` after every code-gen session to apply modernizers. See [modernization.md](modernization.md).

---

## Quick Anti-Patterns Checklist

Flag these when writing or reviewing Go code:

**Structure:**
- ✘ Empty structs as namespaces (use packages)
- ✘ Fat interfaces (split into smaller ones)
- ✘ Mixing pointer and value receivers
- ✘ Utils/common packages (use specific names)
- ✘ Layer-based organization (models/, services/)

**Errors:**
- ✘ Ignoring errors (`_ = foo()`)
- ✘ Panic in library code
- ✘ Using `%v` instead of `%w` for wrapping
- ✘ Direct error comparison with `==`
- ✘ `hashicorp/go-multierror` (use `errors.Join` — Go 1.20+)

**Style:**
- ✘ Comments restating code
- ✘ Section dividers (`// ====`)
- ✘ Getters named GetX (just X)
- ✘ Capitalized error messages
- ✘ Receiver names like "this" or "self"

**Concurrency:**
- ✘ Goroutine leaks (no cleanup)
- ✘ Missing context.Context
- ✘ Global mutable state
- ✘ Shadow-copy `x := x` inside `range` loops (obsolete in Go 1.22+)
- ✘ Hand-rolled `sync.Once` closures (use `sync.OnceFunc` / `OnceValue` — Go 1.21+)

**Modernization:**
- ✘ `any` / `interface{}` where generics would carry the type (see [generics.md](generics.md))
- ✘ `tools.go` blank imports (use `go.mod` tool directives — Go 1.24+)
- ✘ `ptr[T]` helpers (use `new(expr)` — Go 1.26+)
- ✘ Custom loggers when `log/slog` covers it
- ✘ Shipping without running `go fix ./...`

---

## From Python to Go

Your Python style maps naturally to Go:

| Python Preference | Go Equivalent |
|-------------------|---------------|
| No behavioral inheritance | Go has no inheritance |
| Protocols over ABCs | Interfaces (structural typing) |
| `TypeVar` / PEP 695 generics | Type parameters — see [generics.md](generics.md) |
| No @staticmethod | Package-level functions |
| Classes only for state | Structs only for state |
| Modules for namespacing | Packages for namespacing |
| Feature-based organization | Same |
| Explicit public APIs | Capitalized exports |
| Comments for WHY | Same convention |
| `asyncio.TaskGroup` | `errgroup.Group` — see [concurrency.md](concurrency.md) |
| `logging` module | `log/slog` (Go 1.21+ stdlib) |
| `ExceptionGroup` | `errors.Join` (Go 1.20+) |
| Generators (`yield`) | `iter.Seq[T]` (Go 1.23+) |
| `pytest.mark.parametrize` | Table-driven tests with `t.Run` |

---

## Related

- [modernization.md](modernization.md), [quality.md](quality.md), [composition.md](composition.md), [generics.md](generics.md), [concurrency.md](concurrency.md), [test.md](test.md), [modules.md](modules.md), [errors.md](errors.md)
- **code-review**: Review methodology

---

## References

- [Effective Go](https://go.dev/doc/effective_go) - Official style guide
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) - Common review feedback
- [Go Proverbs](https://go-proverbs.github.io/) - Go philosophy in short phrases
- [Go release notes](https://go.dev/doc/devel/release) - Per-version feature lists
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) - Comprehensive
- [log/slog package](https://pkg.go.dev/log/slog) - Stdlib structured logging
- [go fix documentation](https://pkg.go.dev/cmd/go#hdr-Update_packages_to_use_modern_features) - Modernizer command
