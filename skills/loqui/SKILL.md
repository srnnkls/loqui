---
name: loqui
description: |
  Access language-specific coding guidelines from loqui. Use when implementing code and needing patterns, style guidance, or best practices for Python, Go, Rust, Zig, Bash, or Emacs Lisp.
metadata:
  type: generic
henia:
  provides:
    code.style.bash: {path: languages/bash/README.md}
    code.style.elisp: {path: languages/elisp/README.md}
    code.style.go: {path: languages/go/README.md}
    code.style.python: {path: languages/python/README.md}
    code.style.rust: {path: languages/rust/README.md}
    code.style.zig: {path: languages/zig/README.md}
    code.validation.go: {command: go vet ./... && go build ./...}
    code.validation.rust: {command: cargo clippy --all-targets -- -D warnings && cargo build}
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

Shared across all languages. Each language guide works a principle out in its own idiom; the links lead there.

### Naming over comments

Spend 5x more time on names than on comments; a comment records only what no name can carry.

Python [5x rule](languages/python/quality.md#the-5x-rule-naming-over-comments) · Rust [naming](languages/rust/quality.md#naming) · Go [naming](languages/go/quality.md#naming-and-organization) · Zig [naming](languages/zig/quality.md#naming-and-layout) · Emacs Lisp [comments](languages/elisp/quality.md#keep-comments-sparse-and-structural)

### Composition over inheritance

Build behavior from functions, values and small interfaces; never share behavior through class hierarchies or the constructs that imitate them.

Python [no behavioral inheritance](languages/python/composition.md#no-behavioral-inheritance-except-exceptions) · Rust [`Deref` is not inheritance](languages/rust/traits.md#conversions-and-extension-traits) · Go [embedding is not inheritance](languages/go/composition.md#interfaces-and-constructors) · Zig [tagged unions and direct calls](languages/zig/design.md#compose-around-the-domain) · Emacs Lisp [EIEIO only for domain dispatch](languages/elisp/domain-types.md#choose-structs-eieio-or-maps-by-semantics)

### Feature-based organization

Group code by domain feature, not technical layer; dependencies point toward the domain core.

Python [features](languages/python/modules.md#feature-based-organization-not-layer-based), [dependency flow](languages/python/modules.md#dependencies-flow-toward-domain-core) · Rust [modules and crates](languages/rust/modules.md#modules-and-crates) · Go [layout and names](languages/go/modules.md#layout-and-names), [visibility and dependencies](languages/go/modules.md#visibility-and-dependencies) · Zig [organize by feature](languages/zig/design.md#compose-around-the-domain) · Emacs Lisp [files and features](languages/elisp/modules.md#align-files-features-and-dependency-direction), [toward the domain](languages/elisp/composition.md#organize-dependencies-toward-the-domain)

### Model the domain in types

Make illegal states unrepresentable: distinct states are distinct types, and a value of the type is proof of its validity.

Python [illegal states](languages/python/domain-types.md#make-illegal-states-unrepresentable), [DDD through types](languages/python/domain-types.md#domain-driven-design-through-types) · Rust [distinct states](languages/rust/types.md#model-distinct-states), [newtypes](languages/rust/types.md#newtypes-and-representation) · Go [domain types](languages/go/composition.md#domain-types-and-boundaries) · Zig [encode the domain](languages/zig/invariants.md#encode-the-domain) · Emacs Lisp [variants](languages/elisp/domain-types.md#model-variants-explicitly), [DDD](languages/elisp/domain-types.md#domain-driven-design-in-elisp)

### Parse at boundaries

Accept permissive input at the edge and convert it to strict types once; inside, trust the type instead of re-checking it.

Python [parse, don't validate](languages/python/domain-types.md#parse-dont-validate) · Go [parse at the boundary](languages/go/composition.md#domain-types-and-boundaries) · Rust [invariants at boundaries](languages/rust/types.md#preserve-invariants-at-boundaries), [validate once](languages/rust/errors.md#validate-once-preserve-the-invariant) · Zig [parse at the boundary](languages/zig/invariants.md#parse-at-the-boundary), [external bytes](languages/zig/memory.md#bytes-at-external-boundaries) · Emacs Lisp [parse at the boundary](languages/elisp/domain-types.md#parse-at-the-boundary)

### Explicit errors

Expected failure is part of the contract, in the language's idiom: typed exceptions in Python, error values in Rust, Go and Zig, conditions in Emacs Lisp. Failures carry their cause and are never silently swallowed.

Python [exceptions](languages/python/errors.md#exceptions-are-the-default) · Rust [expected failures](languages/rust/errors.md#expected-failures-and-context), [error types](languages/rust/errors.md#choose-error-types-by-caller-needs) · Go [wrapping](languages/go/errors.md#identity-and-wrapping), [panics](languages/go/errors.md#panics-and-recovery) · Zig [failure semantics](languages/zig/invariants.md#define-failure-semantics) · Emacs Lisp [conditions](languages/elisp/errors.md#define-a-package-condition-hierarchy), [optional work](languages/elisp/errors.md#reserve-ignore-errors-for-truly-optional-work) · Bash [error handling](languages/bash/reference/scripts.md#error-handling)

### Explicit side effects

Keep a functional core of value-in, value-out code; I/O, clocks, randomness and environment access live at named edges.

Python [pure domain, adapters](languages/python/composition.md#rendereradapter-pattern), [async boundaries](languages/python/async-io.md#keep-async-boundaries-explicit) · Rust [effects at the edges](languages/rust/README.md#keep-effects-at-the-edges) · Go [effects at the edges](languages/go/composition.md#package-state-and-effects), [initialization](languages/go/composition.md#optional-values-and-initialization) · Zig [policy apart from effects](languages/zig/design.md#compose-around-the-domain), [effects outside comptime](languages/zig/comptime.md#generate-bounded-data-keep-effects-outside) · Emacs Lisp [functional core](languages/elisp/composition.md#build-a-functional-core-inside-the-runtime), [effects as data](languages/elisp/composition.md#return-effects-as-data-when-coordination-grows), [UI effects](languages/elisp/state-effects.md#keep-ui-effects-at-commands)

### No global mutable state

State that outlives a call has one owner and is passed explicitly; no module-level mutable values or hidden singletons.

Python [classes for state](languages/python/composition.md#only-create-classes-for-mutable-and-encapsulated-state), [module constants](languages/python/modules.md#module-level-constants) · Rust [owned state](languages/rust/README.md#keep-mutable-state-owned) · Go [package state](languages/go/composition.md#package-state-and-effects), [mutable data](languages/go/composition.md#ownership-of-mutable-data) · Zig [state ownership](languages/zig/memory.md#state-ownership-in-the-api), [state transitions](languages/zig/design.md#centralize-state-transitions) · Emacs Lisp [runtime state](languages/elisp/modules.md#separate-options-from-mutable-runtime-state)

### Explicit over implicit

Dependencies, conversions and contracts are named where they are used; nothing important happens by convention alone.

Python [public APIs](languages/python/modules.md#explicit-public-apis) · Rust [ownership contract](languages/rust/README.md#express-the-ownership-contract) · Go [main defaults](languages/go/README.md) · Zig [core rules](languages/zig/README.md#core-rules) · Emacs Lisp [lexical binding](languages/elisp/modernization.md#lexical-binding-is-still-explicit)

---

## Related

- `implement` - Generic implementation methodology
- `test` - TDD workflow
- `code` - Code domain (references loqui for compliance review)
