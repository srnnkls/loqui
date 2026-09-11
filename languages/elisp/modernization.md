---
paths: "**/*.el, **/Cask, **/Eask"
---

# Modern Emacs Lisp

Version policy, current APIs, and migration guidance for packages that support Emacs 29.1 and target Emacs 31.1.

## Version Policy

### Support Emacs 29.1 or newer

Declare the floor in package metadata:

```elisp
;; Package-Requires: ((emacs "29.1"))
```

Emacs 29.1 is a practical modern baseline: the starred binding forms are preloaded, lexical binding is established package practice, and the core `seq`, `map`, `pcase`, and `cl-lib` stack covers most collection and control-flow needs.

Emacs 31.1 was released on 2026-08-24 and is the current target. Ordinary examples in this guide remain valid on 29.1+. Sections labeled "Emacs 31" describe new tooling or migration constraints.

When a package needs newer APIs while retaining an older floor, use the GNU ELPA `compat` package and declare it. Do not copy compatibility definitions into the package under unprefixed names.

### Test the declared floor

A version header is a contract. Run byte compilation and ERT on the oldest supported Emacs and current stable Emacs. Run version-sensitive linting on current stable.

Raising the floor is a coordinated change:

1. update `Package-Requires`;
2. update the CI version matrix;
3. remove compatibility code made redundant by the new floor;
4. rerun package-lint against every package file;
5. record user-visible incompatibilities in the release notes.

---

## Modernization Table

| Old or fragile form | Current form | Reason |
|---------------------|--------------|--------|
| Missing lexical cookie | First-line `lexical-binding: t` | Closures and local bindings behave predictably |
| `if-let` | `if-let*` | `if-let` is obsolete in Emacs 31 |
| `when-let` | `when-let*` | `when-let` is obsolete in Emacs 31 |
| `(when-let (x form) ...)` | `(when-let* ((x form)) ...)` | Starred forms use the binding-list syntax |
| `map-put` | `(setf (map-elt map key) value)` or `map-put!` | `map-put` is obsolete |
| `map-elt` with `testfn` | Container-native equality or explicit lookup | The optional test argument is deprecated |
| `(require 'cl)` | `(require 'cl-lib)` | The old `cl` library is obsolete |
| `eval-after-load` | A package API, hook, or explicit dependency | Hidden cross-library mutation obstructs debugging |
| Unqualified globals | `package-name` / `package--private-name` | Elisp has global function and variable namespaces |
| Implicit preload dependency | Explicit `require` | Clean batch sessions expose missing dependencies |
| Recursive list traversal | `dolist`, `while`, `seq-*`, or `cl-loop` | General tail-call optimization is unavailable |
| `checkdoc-file` as a failing CI gate | `checkdoc-batch` on Emacs 31 | Older Checkdoc reports findings without a reliable failing exit |

### Use starred binding forms

Teach and write `if-let*`, `when-let*`, and `and-let*`:

```elisp
(if-let* ((account (invoice-repository-find account-id))
          (email (account-billing-email account)))
    (invoice-send-reminder account email)
  (invoice-record-missing-contact account-id))
```

The bindings are sequential and short-circuit on `nil`. Do not use the obsolete single-binding tuple syntax.

```elisp
;; ✘ WRONG: obsolete in Emacs 31
(when-let (account (invoice-repository-find account-id))
  (invoice-send-reminder account))

;; ✓ CORRECT: supported from the guide's baseline
(when-let* ((account (invoice-repository-find account-id)))
  (invoice-send-reminder account))
```

These forms are preloaded on Emacs 29+. They do not require `subr-x` at this baseline.

### Load the library that owns an API

A clean `emacs -Q` process does not load every built-in library:

```elisp
(require 'cl-lib)  ; cl-defstruct, cl-loop, cl-labels
(require 'map)     ; map-elt, map-keys, map-values
(require 'seq)     ; seq-map, seq-filter, seq-reduce
(require 'subr-x)  ; thread-first, thread-last
```

`pcase` is autoloaded, but explicit requirements are acceptable when a library depends substantially on its pattern language. Never rely on another package having loaded a dependency first.

### Keep `pcase` patterns portable to Emacs 31

Emacs 31 no longer supports nested backquotes in `pcase` patterns. Keep one quasiquoted pattern level and use predicates, guards, or a second match for deeper logic.

```elisp
;; ✓ CORRECT: one structural pattern and an explicit predicate
(pcase event
  (`(:invoice ,invoice)
   (if (invoice-valid-p invoice)
       (invoice-handle invoice)
     (signal 'invoice-invalid (list invoice))))
  (_ nil))
```

Pattern matching is an interface, not a contest in terseness. Extract domain predicates when a pattern starts encoding business rules.

---

## Lexical Binding Is Still Explicit

Emacs 31 warns when a loaded file lacks a lexical-binding cookie, but dynamic binding remains the default dialect for files without one. Put the cookie on the first line:

```elisp
;;; invoice.el --- Manage invoices  -*- lexical-binding: t; -*-
```

Setting `lexical-binding` later in the file cannot retroactively change how the file was read. Do not suppress the missing-cookie warning in authored package code.

Special variables remain available through `defvar` and `defcustom`. Dynamic rebinding is useful for established Emacs protocols, but it should be local and visible.

---

## Emacs 31 Tooling Changes

### Use `checkdoc-batch` as the failing gate

Emacs 31 adds `checkdoc-batch`, which checks the current buffer, prints findings, and signals failure in batch mode:

```sh
emacs -Q --batch --file invoice.el --funcall checkdoc-batch
```

On Emacs 30 and older, `checkdoc-file` is useful for diagnostics but does not provide an equivalent reliable failure status. Run the mandatory Checkdoc gate in the Emacs 31 job.

### Keep ERT helpers version-aware

Several helpers have moved between `ert-x` and core ERT across releases. Require `ert-x` explicitly when using one of its helpers, and verify that the helper exists at the declared minimum version. Core tests should prefer stable primitives such as `with-temp-buffer`, `make-temp-file`, and `unwind-protect` when that keeps the test clear.

### Avoid accidental 31-only APIs

Emacs 31 adds and promotes APIs that are unavailable at the 29.1 floor. package-lint checks whether symbols agree with `Package-Requires`; use it before release. If a 31-only API is essential, raise the declared floor or supply it through `compat`.

---

## AI Drift Warning

Generated Elisp frequently reflects old configuration snippets rather than current package practice. Review specifically for:

- no lexical-binding cookie;
- `if-let` or `when-let` and their old single-binding syntax;
- implicit `cl`, `map`, or `subr-x` availability;
- `map-put` or a custom equality argument to `map-elt`;
- `eval-after-load`, advice, or hooks used instead of an explicit API;
- unprefixed global symbols;
- macros that only wrap an ordinary function call;
- nested-backquote `pcase` patterns;
- `checkdoc-file` presented as a failing CI gate;
- `dash.el` introduced for operations already clear with built-ins;
- a `Package-Requires` floor older than the APIs actually used.

Byte compilation and package-lint catch much of this drift. They do not prove architectural boundaries; review buffer, process, hook, and global-variable access separately.

---

## Upgrade Checklist

- [ ] Every `.el` file has a first-line lexical-binding cookie
- [ ] `Package-Requires` matches the oldest tested Emacs
- [ ] Starred binding forms use a list of bindings
- [ ] Every non-preloaded library is explicitly required
- [ ] No obsolete APIs remain without an isolated compatibility reason
- [ ] `pcase` patterns avoid nested backquotes
- [ ] Byte compilation is warning-free at the minimum and current versions
- [ ] ERT passes at the minimum and current versions
- [ ] Checkdoc and package-lint pass on Emacs 31
- [ ] Compatibility shims are prefixed, bounded, and covered by tests

---

## Related

- [fundamentals.md](fundamentals.md) - Lexical scope and special variables
- [control-flow.md](control-flow.md) - Starred bindings and portable `pcase`
- [collections.md](collections.md) - Current collection APIs and requirements
- [quality.md](quality.md) - Batch commands and warning policy

## References

- [GNU Emacs Lisp Manual: Selecting Lisp Dialect](https://www.gnu.org/software/emacs/manual/html_node/elisp/Selecting-Lisp-Dialect.html) - Lexical and dynamic binding
- [GNU Emacs 31.1 release announcement](https://lists.gnu.org/archive/html/emacs-devel/2026-08/msg00760.html) - Current release
- [GNU Emacs NEWS for Emacs 31](https://raw.githubusercontent.com/emacs-mirror/emacs/emacs-31/etc/NEWS) - Language and tooling changes
- [GNU ELPA compat](https://elpa.gnu.org/packages/compat.html) - Compatibility APIs for older Emacs versions
- [package-lint](https://github.com/purcell/package-lint) - API/version-floor checks
