---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Modules

Library headers, global symbol names, features, dependencies, autoloads, and domain-oriented package layout.

## Follow the Conventional Library Shape

A distributable package file has a first-line summary and lexical-binding cookie, package metadata, commentary, code, a provided feature, and a footer.

```elisp
;;; invoice.el --- Manage invoices in Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Example Maintainer

;; Author: Example Maintainer <maintainer@example.net>
;; Maintainer: Example Maintainer <maintainer@example.net>
;; Package-Requires: ((emacs "29.1"))
;; Keywords: data
;; URL: https://example.net/invoice

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `invoice-mode' displays and updates invoices through a repository
;; configured by `invoice-repository-function'.

;;; Code:

(require 'invoice-ui)

(defgroup invoice nil
  "Manage invoices."
  :group 'applications)

(defcustom invoice-repository-function #'invoice-repository-load
  "Function used to load an invoice by identifier."
  :type 'function
  :group 'invoice)

;;;###autoload
(defun invoice-open (invoice-id)
  "Open the invoice named INVOICE-ID."
  (interactive (list (read-string "Invoice ID: ")))
  (invoice-ui-open
   (funcall invoice-repository-function invoice-id)))

(provide 'invoice)

;;; invoice.el ends here
```

The first line must be the first line. The filename, provided feature, and footer agree. Checkdoc and package-lint enforce much of this shape.

License text depends on the package's actual distribution terms. Do not copy GNU Emacs's copyright holder or claim that a package is part of GNU Emacs unless that is true.

---

## Prefix Every Global Symbol

Elisp has global function and variable namespaces. Pick a short package prefix and apply it consistently:

```elisp
invoice-open
invoice-mode
invoice-default-currency
invoice-repository-load
invoice--parse-line
invoice-ui--refresh-timer
```

Use one hyphen for public names and two hyphens for implementation details:

```elisp
(defun invoice-total (invoice) ...)
(defun invoice--normalize-currency (currency) ...)
```

The double hyphen communicates an API boundary but does not make a symbol inaccessible.

Prefix these too:

- conditions;
- faces;
- hooks;
- keymap variables;
- customization groups and options;
- struct names and generated accessors;
- constants and buffer-local variables;
- macros and feature names.

Established command naming conventions can put a verb before the prefix, such as `list-invoices`. Use those exceptions only when the result is idiomatic for users.

### Follow predicate and variable conventions

Function predicates end in `p` for one-word names or `-p` for multi-word names:

```elisp
invoicep
invoice-overdue-p
```

Boolean variable names should describe state rather than imitate predicate functions:

```elisp
invoice-refresh-enabled
invoice-debug-flag
```

A variable holding one function ends in `-function`; a normal hook ends in `-hook`.

---

## Align Files, Features, and Dependency Direction

A feature-oriented package can use this layout:

```text
invoice/
├── invoice.el
├── invoice-domain.el
├── invoice-repository.el
├── invoice-service.el
├── invoice-ui.el
└── test/
    ├── invoice-domain-test.el
    ├── invoice-service-test.el
    └── invoice-ui-test.el
```

Responsibilities:

| File | Owns |
|------|------|
| `invoice-domain.el` | Structs, parsers, invariants, predicates, transformations |
| `invoice-repository.el` | File, SQLite, process, or network conversion |
| `invoice-service.el` | Workflows combining domain and repository contracts |
| `invoice-ui.el` | Commands, buffers, completion, modes, keymaps |
| `invoice.el` | Public facade, customization, activation |

Dependencies point inward:

```text
invoice.el -> invoice-ui.el -> invoice-service.el -> invoice-domain.el
                              -> invoice-repository.el -> invoice-domain.el
```

The domain never requires UI, process, buffer, or package-facade files.

Avoid technical junk drawers:

```text
;; ✘ WRONG
models.el
services.el
utils.el
helpers.el
```

Split by bounded feature when the package grows. A file named `utils.el` usually collects unrelated responsibilities and creates dependency cycles.

---

## Use `require` and `provide` Deliberately

`require` loads a named feature at most once:

```elisp
(require 'cl-lib)
(require 'invoice-domain)
(require 'invoice-repository)
```

Use `require`, not `load` or `load-library`, for package dependencies. Direct loading can evaluate the same library multiple times and bypass the feature contract.

Every separate library ends with its matching feature:

```elisp
(provide 'invoice-domain)

;;; invoice-domain.el ends here
```

### Distinguish compile-time and runtime dependencies

If a library uses only macros from another library and the expanded code has no runtime dependency, load it while compiling:

```elisp
(eval-when-compile
  (require 'invoice-macros))
```

If expanded code calls functions or reads variables from that library, the runtime dependency still needs a normal `require` or a separate runtime module.

Prefer ordinary functions over a shared macro module. Compile-time dependency edges are harder to inspect and reload correctly.

### Avoid optional dependencies at startup

When only one command needs an optional built-in or package, require it in that adapter:

```elisp
(defun invoice-export-org (invoice)
  "Export INVOICE as an Org buffer."
  (require 'org)
  (invoice-ui--render-org invoice))
```

Do not scatter conditional `require` calls through the domain. Optional capability belongs at a feature boundary.

---

## Make Loading Behavior-Preserving

Loading a library should define functions, variables, faces, modes, and features. It should not silently change editing behavior.

```elisp
;; ✘ WRONG: package activation at load time
(add-hook 'after-save-hook #'invoice-sync-all)
(global-set-key (kbd "C-c i") #'invoice-open)
(invoice-start-background-refresh)
```

Expose a command, mode, or setup function:

```elisp
;;;###autoload
(define-minor-mode invoice-mode
  "Display invoice information in the current buffer."
  :lighter " Invoice"
  (if invoice-mode
      (invoice-ui--enable)
    (invoice-ui--disable)))
```

The disable path reverses resources owned by the mode: local hooks, timers, overlays, processes, and keymaps.

Avoid `with-eval-after-load` in distributed libraries when a documented API or hook can express the integration. Hidden mutation of another library complicates debugging and unloading.

---

## Autoload Only Public Entry Points

An autoload cookie tells package tools to generate a lightweight entry point without loading the full library.

Appropriate targets include:

- major and minor mode definitions;
- common interactive commands;
- explicit setup functions;
- file-extension associations for a major mode.

```elisp
;;;###autoload
(defun invoice-open (invoice-id)
  "Open the invoice named INVOICE-ID."
  ...)
```

Do not autoload private functions or variables:

```elisp
;; ✘ WRONG
;;;###autoload
(defun invoice--parse-line (line) ...)

;;;###autoload
(defvar invoice--cache nil)
```

An autoloaded top-level form must not activate the package. Adding a major-mode association is the narrow conventional exception.

---

## Separate Options from Mutable Runtime State

Use `defcustom` for user configuration and `defvar` for internal state:

```elisp
(defcustom invoice-default-currency "EUR"
  "Currency used when imported data omits one."
  :type 'string
  :group 'invoice)

(defvar-local invoice-ui--refresh-timer nil
  "Refresh timer owned by the current invoice buffer.")
```

A custom setter can have effects, but it then becomes part of the option's public behavior and must work during initialization and Customize operations. Prefer a simple option plus an explicit refresh command where practical.

Do not use a global variable as a mutable service locator. A configurable function option can define a public extension point; core functions should still accept their dependencies explicitly.

---

## Keep the Public Facade Small

The main feature exports the package's stable entry points:

- commands and modes;
- customization options;
- documented extension functions and hooks;
- stable domain constructors when callers need them.

Internal modules may provide features for package composition without making every function public. Double-hyphen names can still be called, but callers accept that they are not compatibility promises.

Do not re-export wrappers that merely rename every internal function. A facade is a deliberate API, not a second copy of the package.

---

## Avoid Cycles

A cycle such as `invoice-domain -> invoice-service -> invoice-domain` usually means responsibilities point in both directions.

Break it by:

- moving shared domain data to the inward module;
- passing a function callback into the inward layer;
- returning a decision that the outward layer applies;
- extracting a genuinely independent protocol module.

Do not solve a design cycle with delayed `require`, `declare-function`, or load-order tricks. Those can silence symptoms while preserving the architectural knot.

`declare-function` is correct when an external function is intentionally resolved at runtime and a hard load dependency is undesirable. Include the source file and signature so the compiler can check calls.

---

## Summary

- Follow the conventional header, Commentary, Code, provide, and footer shape
- Put the lexical-binding cookie on the first line
- Prefix every top-level symbol
- Use double hyphens for private implementation details
- Align filenames and provided features
- Organize by domain feature and point dependencies inward
- Use `require` for feature dependencies
- Keep compile-only macro dependencies genuinely compile-only
- Make library loading behavior-preserving
- Autoload public entry points, not implementation details
- Separate user options from mutable runtime state
- Keep the public facade smaller than the implementation
- Fix dependency cycles in the design rather than through load order

---

## Related

- [composition.md](composition.md) - Dependency direction and command shells
- [domain-types.md](domain-types.md) - Domain module contents
- [state-effects.md](state-effects.md) - Mode setup and teardown
- [quality.md](quality.md) - Header, Checkdoc, and package-lint gates

## References

- [GNU Emacs Lisp Manual: Library Headers](https://www.gnu.org/software/emacs/manual/html_node/elisp/Library-Headers.html) - Conventional package file structure
- [GNU Emacs Lisp Manual: Coding Conventions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Coding-Conventions.html) - Prefixes, features, and loading
- [GNU Emacs Lisp Manual: Named Features](https://www.gnu.org/software/emacs/manual/html_node/elisp/Named-Features.html) - `provide` and `require`
- [GNU Emacs Lisp Manual: Autoload](https://www.gnu.org/software/emacs/manual/html_node/elisp/Autoload.html) - Deferred loading
- [GNU Emacs Lisp Manual: Packaging Basics](https://www.gnu.org/software/emacs/manual/html_node/elisp/Packaging-Basics.html) - Package metadata
