---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Style Guide

Modern Emacs Lisp for package and application code, viewed as a functional core embedded in a stateful editor runtime.

New code supports Emacs 29.1 or newer. Emacs 31.1 is the current target; version-specific guidance lives in [modernization.md](modernization.md).

Start with [composition.md](composition.md): read state at the edge, transform explicit values in the core, then apply effects through a thin Emacs adapter.

---

## Quick Reference

| Resource | When to use |
|----------|-------------|
| [modernization.md](modernization.md) | Version floor, Emacs 31 changes, obsolete APIs, AI drift |
| [fundamentals.md](fundamentals.md) | Lexical scope, closures, symbols, equality, mutability |
| [domain-types.md](domain-types.md) | `cl-defstruct`, invariants, boundary parsing, value updates |
| [composition.md](composition.md) | Functional core, imperative shell, functions before macros |
| [control-flow.md](control-flow.md) | `if-let*`, `pcase`, destructuring, loops, recursion |
| [collections.md](collections.md) | Lists, vectors, maps, `seq`, `map`, `cl-lib`, `subr-x` |
| [state-effects.md](state-effects.md) | Buffers, point, hooks, processes, timers, cleanup |
| [modules.md](modules.md) | Package headers, prefixes, features, autoloads, file layout |
| [errors.md](errors.md) | Conditions, domain alternatives, `user-error`, cleanup |
| [test.md](test.md) | ERT, pure-core tests, state isolation, batch execution |
| [quality.md](quality.md) | Checkdoc, package-lint, warnings, profiling, CI gates |

---

## Working Model

Emacs Lisp has two simultaneous meanings:

- expressions return values that can feed other expressions;
- operations can mutate the editor, process state, filesystem, or UI.

Keep those meanings visible in the architecture:

```text
Emacs / files / processes
          |
          v
  adapter parses input
          |
          v
  domain transformations
          |
          v
  adapter applies effects
```

A pure-ish domain function accepts everything it needs and returns a value. An adapter owns `current-buffer`, point, minibuffer input, hooks, timers, and process callbacks.

```elisp
;; Domain
(defun invoice-overdue-p (invoice today)
  "Return non-nil when INVOICE is unpaid and due before TODAY."
  (and (eq (invoice-status invoice) 'unpaid)
       (time-less-p (invoice-due-at invoice) today)))

;; Emacs adapter
(defun invoice-mark-overdue-at-point ()
  "Mark the invoice at point when it is overdue."
  (interactive)
  (let ((invoice (invoice-ui--invoice-at-point)))
    (when (invoice-overdue-p invoice (current-time))
      (invoice-ui--apply-overdue-face invoice))))
```

The domain function is deterministic for explicit inputs. The command is intentionally effectful.

---

## Core Principles

### Use lexical binding in every library

The first line of every `.el` file carries the cookie:

```elisp
;;; invoice.el --- Manage invoices  -*- lexical-binding: t; -*-
```

Lexical binding gives local variables lexical scope and makes closures predictable. Variables declared special with `defvar` remain dynamically bindable by design.

### Parse at boundaries

Convert plists, alists, JSON objects, buffer text, and process output into named domain values before core logic sees them. Constructors enforce invariants; the rest of the program operates on canonical data.

### Keep effects at explicit edges

Treat these as infrastructure:

- current buffer, point, mark, narrowing, and match data;
- buffer-local and global variables;
- text properties, overlays, windows, and minibuffer interaction;
- hooks, advice, timers, processes, sentinels, and filesystem access.

### Prefer functions to macros

Use a function unless callers must pass unevaluated syntax or the construct must introduce bindings or control evaluation. Keep necessary macros thin and move their computation into ordinary functions.

### Prefer built-ins to convenience dependencies

Start with `seq`, `map`, `subr-x`, `pcase`, and `cl-lib`. Add a third-party collection library only when its vocabulary materially improves the package and its distribution cost is acceptable.

### Measure before rewriting clear code

Sequence transformations are appropriate in business logic. Measured hot traversal code often benefits from `dolist`, `while`, `cl-loop`, or `push` followed by `nreverse`. Profile first.

---

## Tooling

| Tool | Purpose |
|------|---------|
| Byte compiler | Undefined functions, free variables, obsolete calls, malformed forms |
| ERT | Unit and behavior tests in core Emacs |
| Checkdoc | Package headers, docstrings, comments, and documentation conventions |
| package-lint | Package metadata and declared version compatibility |
| `benchmark-run` | Compare bounded alternatives |
| Built-in profiler | Locate CPU, memory, and allocation hot spots |

The canonical commands and failure policy are in [quality.md](quality.md). Test organization and state isolation are in [test.md](test.md).

---

## Quick Anti-Patterns Checklist

Flag these in new code:

- missing first-line lexical-binding cookie;
- top-level side effects merely from loading a library;
- unprefixed global symbols;
- anonymous plists or positional lists deep in domain logic;
- reusable functions that silently depend on the current buffer or point;
- global variables used as hidden function parameters;
- macros where a function would work;
- mutation hidden inside a transformation pipeline;
- obsolete `if-let`, `when-let`, or `map-put` calls;
- implicit reliance on preloaded libraries;
- broad `condition-case` handlers for `error`;
- `ignore-errors` around domain or persistence logic;
- `message` used as error propagation;
- recursive collection traversal without a bounded depth;
- hot-path rewrites without benchmark or profiler evidence;
- byte-compiler, Checkdoc, package-lint, or ERT failures in CI.

---

## References

1. [GNU Emacs Lisp Manual: Tips and Conventions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Tips.html) - Canonical package and coding conventions
2. [Emacs Lisp Style Guide](https://github.com/bbatsov/emacs-lisp-style-guide) - Compact community style guidance
3. [Emacs Lisp Elements 2.0](https://protesilaos.com/emacs/emacs-lisp-elements) - Contemporary treatment of evaluation, state, functions, and control flow
4. [Emacs Package Developer's Handbook](https://github.com/alphapapa/emacs-package-dev-handbook) - Package-development reference
5. [awesome-elisp](https://github.com/emacs-tw/awesome-elisp) - Index of libraries, tools, and codebases
