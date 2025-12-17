# Go Style Guide

Language-specific patterns, anti-patterns, and best practices for writing Go code.

---

## Quick Reference

| Resource | When to Use |
|----------|-------------|
| [quality.md](quality.md) | Naming, comments, documentation, conventions |
| [composition.md](composition.md) | Structs vs interfaces vs packages, methods vs functions |
| [modules.md](modules.md) | Package structure, organization, public APIs |
| [errors.md](errors.md) | Error handling, wrapping, custom error types |

---

## Core Principles

### 1. Naming Over Comments (5x Rule)
Spend 5x more time finding good names than writing comments. Comments explain WHY, not WHAT.

### 2. Composition, Not Inheritance
Go has no inheritance. Use interfaces and composition. Keep interfaces small.

### 3. Packages for Organization
Use packages for namespacing, not empty structs. Organize by domain feature, not technical layer.

### 4. Errors Are Values
Return errors explicitly. Check immediately. Wrap with context using `%w`.

### 5. Simplicity
- Package-level functions are first-class (don't wrap in structs)
- Accept interfaces, return structs
- Design for zero values
- Keep interfaces small (1-3 methods)

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

---

## From Python to Go

Your Python style maps naturally to Go:

| Python Preference | Go Equivalent |
|-------------------|---------------|
| No behavioral inheritance | Go has no inheritance |
| Protocols over ABCs | Interfaces (structural typing) |
| No @staticmethod | Package-level functions |
| Classes only for state | Structs only for state |
| Modules for namespacing | Packages for namespacing |
| Feature-based organization | Same |
| Explicit public APIs | Capitalized exports |
| Comments for WHY | Same convention |

---

## Related Skills

- **code-review**: Review methodology (delegates here for Go specifics)
- **pr-review**: GitHub PR workflow (delegates to code-review)

---

## References

- [Effective Go](https://go.dev/doc/effective_go) - Official style guide
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) - Common review feedback
- [Go Proverbs](https://go-proverbs.github.io/) - Go philosophy in short phrases
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) - Comprehensive
