# Python Style Guide

Language-specific patterns, anti-patterns, and best practices for writing Python code.

---

## Quick Reference

| Resource | When to Use |
|----------|-------------|
| [quality.md](quality.md) | Naming, comments, docstrings, anti-patterns |
| [composition.md](composition.md) | Classes vs functions, protocols, inheritance |
| [control-flow.md](control-flow.md) | Pattern matching, iteration vs recursion |
| [domain-types.md](domain-types.md) | Dataclasses, Pydantic, discriminated unions |
| [errors.md](errors.md) | Exceptions vs Result types, error propagation |
| [modules.md](modules.md) | Package structure, imports, public APIs |
| [async-io.md](async-io.md) | Async/await, TaskGroups, timeouts, blocking I/O |
| [test.md](test.md) | Testing patterns and practices |

---

## Core Principles

### 1. Naming Over Comments (5x Rule)
**Spend 5x more time finding good names than writing comments.**

Comments explain WHY, not WHAT. The code should be self-documenting through clear naming.

### 2. NO Behavioral Inheritance (Except Exceptions)
**NEVER use inheritance for code reuse. ONLY for exception hierarchies.**

This rule is absolute. Use composition, protocols, and module functions instead.

### 3. NEVER Use @staticmethod
**@staticmethod is ALWAYS wrong. Use module-level functions.**

Python has namespaces: modules. This is not Java.

### 4. Classes ONLY for Mutable and Encapsulated State
**Create classes ONLY when you need mutable state encapsulated across multiple method calls.**

Otherwise use module functions. Classes are not namespaces.

### 5. ALWAYS Use src Layout
**NEVER use flat layout. ALWAYS use `src/myproject/` structure.**

Ensures tests run against installed package, catches packaging issues early.

### 6. Feature-Based Organization (NOT Layer-Based)
**Organize by domain feature (`chat/`, `storage/`), NOT technical layer (`models/`, `services/`).**

Keep related types and functions together in cohesive modules.

### 7. START with Types
**ALWAYS model your domain with types FIRST.**

- Types ARE the design, not documentation
- Use `@dataclass(frozen=True, kw_only=True)` for value objects
- Make illegal states unrepresentable through discriminated unions
- Parse at boundaries, NEVER pass `dict[str, Any]` into core logic

### 8. Parse Don't Validate
**Accept permissive input at boundaries, immediately parse to strict canonical types internally.**

Core logic MUST work with guaranteed-valid, typed data only.

### 9. Exceptions are the Default
**USE exceptions by default. Result types ONLY for:**
- Async task coordination (collect all results without canceling)
- Batching validation errors (show user all errors at once)

Catch at application boundaries. Propagate in core logic.

### 10. Trustful Delegation
**Validate YOUR invariants, not theirs.**

Don't duplicate validation that dependencies already do.

---

## Tooling

**Never use system Python.** Always use `uv` for package management and execution.

| Tool | Purpose |
|------|---------|
| `uv` | Package management, virtual environments, script execution |
| `pyright` | Type checking |
| `ruff` | Linting and formatting |

**Self-contained scripts:** Use [PEP 723](https://peps.python.org/pep-0723/) inline metadata with `uv run`:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///
```

---

## Quick Anti-Patterns Checklist

Flag these when writing or reviewing Python code:

**Structure:**
- ✘ Behavioral inheritance (except exceptions)
- ✘ @staticmethod (use module functions)
- ✘ Classes as namespaces (use modules)
- ✘ Utils/common modules (use specific names)
- ✘ Layer-based organization (models/, services/)

**Types:**
- ✘ dict[str, Any] deep in logic (parse at boundaries)
- ✘ Positional pattern matching (use keyword patterns)
- ✘ Mutable default arguments

**Async:**
- ✘ Blocking I/O in async context
- ✘ Missing timeouts on async I/O
- ✘ asyncio.gather without proper error handling

**Style:**
- ✘ Comments restating code
- ✘ Section divider comments (split into modules)
- ✘ Global mutable state
- ✘ Multiple unrelated classes in one module

---

## Type Hints

Use type hints consistently:
- Always annotate function signatures
- Use `from __future__ import annotations` for forward references
- Prefer protocols over abstract base classes
- Use TypedDict or dataclasses over dict[str, Any]

---

## Related

- [quality.md](quality.md), [composition.md](composition.md), [domain-types.md](domain-types.md), etc.
- **code-review**: Review methodology
- **code-test**: Test-driven development workflow

---

## References

- [PEP 8](https://peps.python.org/pep-0008/) - Style Guide for Python Code
- [PEP 20](https://peps.python.org/pep-0020/) - The Zen of Python
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
- [Type Hints Cheat Sheet](https://mypy.readthedocs.io/en/stable/cheat_sheet_py3.html)
