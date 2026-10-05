---
name: loqui
description: |
  Access language-specific coding guidelines from loqui. Use when implementing code and needing patterns, style guidance, or best practices for Python, Go, Rust, Zig, Bash, or Emacs Lisp.
metadata:
  type: generic
henia:
  provides:
    code.style.bash:
    code.style.elisp:
    code.style.go:
    code.style.python:
    code.style.rust:
    code.style.zig:
    code.validation.go: {command: go vet ./... && go build ./...}
  targets:
    codex:
      openai:
        interface:
          display_name: Loqui
          short_description: Apply the canonical loqui skill workflow
          default_prompt: Use $loqui for the requested task.
---

# Loqui

Language guidelines for writing code with eloquence and style.

---

## Location

Read the guidelines with `henia show`:

```bash
henia show loqui/languages/{language}/README.md
```

Read the relevant language README first, then follow its topic links with the same address prefix.

---

## Languages

| Language | Read |
|----------|------|
| Python | `henia show loqui/languages/python/README.md` |
| Go | `henia show loqui/languages/go/README.md` |
| Rust | `henia show loqui/languages/rust/README.md` |
| Zig | `henia show loqui/languages/zig/README.md` |
| Bash | `henia show loqui/languages/bash/README.md` |
| Emacs Lisp | `henia show loqui/languages/elisp/README.md` |

---

## Structure

Each language directory follows this structure:

```
{language}/
├── README.md        # Overview, core principles, anti-patterns checklist
├── quality.md       # Naming, comments, documentation conventions
├── composition.md   # Structuring behavior (classes/functions/modules)
├── modules.md       # Package structure, organization, public APIs
├── errors.md        # Error handling patterns
└── ...              # Additional language-specific resources
```

Start with the README for the working model, priorities, invariants, and topic map. For Zig async/I/O,
read `henia show loqui/languages/zig/async-io.md` and verify APIs against the consuming project's
pinned compiler; do not substitute remembered APIs from another Zig release.

---

## Principles

Shared across all languages:

- Naming over comments — spend 5x more time on names than comments
- Composition over inheritance
- Feature-based organization — group by domain, not technical layer
- Parse at boundaries — accept permissive input, convert to strict types immediately
- Explicit over implicit

---

## Related

- `implement` - Generic implementation methodology
- `test` - TDD workflow
- `code` - Code domain (references loqui for compliance review)
