---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Quality

Naming, documentation, formatting, compiler warnings, lint gates, benchmarking, and profiling.

## Name for the Global Namespace

Prefix every top-level symbol with the package name:

```elisp
;; ✓ CORRECT
invoice-open
invoice-overdue-p
invoice--parse-line
invoice-default-currency
invoice-after-save-hook
invoice-render-function

;; ✘ WRONG
open
parse-line
currency
```

Use one hyphen for public names and two for implementation details. Keep predicates and protocol variables conventional:

| Kind | Convention | Example |
|------|------------|---------|
| One-word predicate | suffix `p` | `invoicep` |
| Multi-word predicate | suffix `-p` | `invoice-overdue-p` |
| One function value | suffix `-function` | `invoice-render-function` |
| Normal hook | suffix `-hook` | `invoice-after-save-hook` |
| Abnormal hook | document arguments | `invoice-after-save-functions` |
| Internal symbol | prefix plus `--` | `invoice--parse-line` |

Do not use Scheme question marks, Java `is-` prefixes, or surrounding asterisks for ordinary variable names.

Unused lexical parameters begin with an underscore:

```elisp
(lambda (invoice _context)
  (invoice-id invoice))
```

A leading underscore communicates intent and suppresses the corresponding compiler warning.

---

## Write Docstrings as API Contracts

Public functions, commands, variables, modes, faces, and hooks have docstrings. Private definitions should have one when their contract is not obvious.

```elisp
(defun invoice-find-overdue (invoices today)
  "Return overdue members of INVOICES at TODAY.
The returned list preserves input order and shares invoice objects with
INVOICES."
  ...)
```

Docstring rules:

- begin with a complete imperative sentence;
- mention important arguments in call order using uppercase names;
- end the first sentence with punctuation;
- describe return values, mutation, ownership, conditions, and effects;
- use active voice and present tense;
- quote Elisp symbols as `` `invoice-id' `` in source;
- do not indent continuation lines to align with the opening quote;
- use `\\[command]` in source for key bindings rather than hard-coded keys;
- say when a command requires a particular mode or buffer state.

```elisp
;; ✘ WRONG: restates the name and omits the contract
(defun invoice-find-overdue (invoices today)
  "Find overdue invoices."
  ...)
```

A docstring is user-visible documentation, not a place to narrate the implementation.

---

## Keep Comments Sparse and Structural

Prefer names and small functions over explanatory comments. Write comments for:

- a non-obvious invariant;
- an external protocol constraint;
- a compatibility boundary;
- a measured performance choice;
- why an apparently simpler approach is incorrect.

```elisp
;; The server frames messages by NUL, not newline; chunks may split UTF-8.
(invoice-process--accept-chunk process chunk)
```

Do not restate code:

```elisp
;; ✘ WRONG: increment retries
(setq retries (1+ retries))
```

Follow standard semicolon levels:

- `;;;` for required library sections such as Commentary and Code;
- `;;` for comments aligned with surrounding code;
- `;` for a short margin comment when it remains readable.

Use standard package sections, not decorative ASCII dividers. Split a file when independent responsibilities develop their own dependency boundary.

Do not leave task-state notes in shipped code. Track unfinished work in the project system; retain a source comment only when the code's reader needs the constraint.

---

## Let Emacs Format Elisp

Use `emacs-lisp-mode` indentation with spaces. Do not hand-align code against the mode's result. Pin the project setting in `.dir-locals.el`:

```elisp
((emacs-lisp-mode
  (indent-tabs-mode . nil)))
```

A local non-writing CI check can validate parentheses and canonical indentation:

```sh
emacs -Q --batch --file invoice.el \
  --eval '(condition-case condition
              (progn
                (setq-local indent-tabs-mode nil)
                (check-parens)
                (indent-region (point-min) (point-max))
                (when (buffer-modified-p)
                  (princ "invoice.el is not canonically indented\n")
                  (kill-emacs 1)))
            (error
             (princ (error-message-string condition))
             (kill-emacs 1)))'
```

Run this once per source and test file. Load libraries that provide custom indentation metadata before `--file`; add `-l ert` for ERT tests and load the package's macro declarations when they define indentation. The command edits only the in-memory batch buffer and exits nonzero when syntax or indentation differs.

Keep trailing whitespace out of source and use UTF-8 unless a file declares another coding system.

---

## Make Byte-Compiler Warnings Fail

The byte compiler detects undefined functions, free variables, obsolete APIs, malformed declarations, and other problems that interpreted loading can tolerate.

```sh
emacs -Q --batch \
  -L . \
  --eval '(setq byte-compile-error-on-warn t)' \
  --funcall batch-byte-compile \
  invoice-domain.el \
  invoice-repository.el \
  invoice-service.el \
  invoice-ui.el \
  invoice.el
```

Compile in dependency order when files define macros used by later files. Keep every dependency explicit so a clean batch process succeeds.

Treat warnings as design feedback:

| Warning | Preferred response |
|---------|--------------------|
| Free variable | Pass it, declare an intentional special variable, or require its owner |
| Unknown function | Require its feature or declare an intentional runtime function |
| Obsolete function | Migrate to the current API |
| Wrong argument count | Fix the call or declared signature |
| Docstring width/style | Rewrite the documentation |
| Unused lexical argument | Remove it or prefix the intentional argument with `_` |

Do not globally suppress warning classes. `with-no-warnings` is a last resort for a reviewed compatibility boundary and should be smaller than the warning-producing expression.

Byte compilation creates `.elc` files. CI workspaces may discard them; local validation should remove them after the check. Do not commit generated bytecode.

Native compilation is an additional compatibility and performance check, not a substitute for byte compilation. Packages are normally distributed as source and compiled by the target Emacs.

---

## Run Checkdoc as a Failing Gate

On Emacs 31, `checkdoc-batch` checks the visited buffer, prints every finding, and signals failure:

```sh
emacs -Q --batch \
  -l checkdoc \
  --file invoice.el \
  --funcall checkdoc-batch
```

Run it once for every package `.el` file, including tests when their documentation is distributed.

On Emacs 30 and older, `checkdoc-file` reports diagnostics but does not provide an equivalent dependable failing exit status. It is useful interactively and in editor integration; the mandatory CI gate belongs in the Emacs 31 job.

Review findings rather than weakening Checkdoc globally. A justified exception stays local and documented.

---

## Run package-lint Against the Declared Floor

package-lint checks package headers, naming conventions, dependencies, and whether APIs agree with `Package-Requires`.

With package-lint installed on an explicit load path:

```sh
emacs -Q --batch \
  -L /path/to/package-lint \
  -l package-lint \
  --funcall package-lint-batch-and-exit \
  invoice.el
```

Run the command for every package entry file. Keep `-Q`; loading a personal package directory can hide missing metadata or dependencies.

A package-lint failure about symbol availability means one of three things:

1. the package floor is too low;
2. a compatibility dependency is missing;
3. the code should use an older stable API.

Resolve the contract. Do not add a fake declaration or silence the finding.

---

## Use One Quality Gate

For every supported Emacs major version:

1. check parentheses and canonical indentation;
2. byte-compile all source and test files with warnings as errors;
3. run the complete ERT suite under `emacs -Q`.

On Emacs 31.1 additionally:

4. run `checkdoc-batch` for every `.el` file;
5. run package-lint for package entry files.

Finally:

6. reject `.elc`, native-comp output, package archives, coverage files, and scratch buffers written to the repository;
7. require a clean generated-file status.

This is the canonical gate. Editor diagnostics are fast feedback, not a replacement.

---

## Measure Performance Before Changing Style

### Benchmark a bounded expression

```elisp
(require 'benchmark)

(benchmark-run 1000
  (invoice-large-open-ids invoices 1000))
```

Benchmark realistic input sizes and retain the result. Compare complete alternatives in the same Emacs process after warm-up.

`benchmark-run` reports elapsed time, garbage collections, and GC time. Allocation often explains why an elegant sequence pipeline loses to one local loop.

Microbenchmarks do not measure redisplay, process latency, filesystem behavior, or user-perceived responsiveness. Use the profiler for integrated work.

### Profile before optimizing

```elisp
(profiler-start 'cpu)
(invoice-refresh-all)
(profiler-stop)
(profiler-report)
```

Use memory profiling when allocation is the suspected cost. Profile the real command and realistic buffers.

Likely hot-path improvements include:

- replace repeated list indexing with one traversal;
- fuse several allocating sequence passes;
- use `push` plus `nreverse` for list construction;
- avoid repeated buffer scans and redisplay;
- batch text changes inside the correct buffer primitive;
- use primitive lookup functions for native container shapes;
- move blocking I/O to an asynchronous process design.

Do not trade clear domain code for a loop without evidence. Keep optimized code bounded and add a benchmark or performance test that protects the reason.

---

## Review Checklist

- [ ] Every global symbol has the package prefix
- [ ] Predicate, hook, and function-variable names follow conventions
- [ ] Public contracts have complete docstrings
- [ ] Comments explain constraints rather than restating code
- [ ] Emacs indentation and parentheses checks pass
- [ ] Byte compilation has zero warnings at every supported version
- [ ] Checkdoc passes on Emacs 31
- [ ] package-lint agrees with `Package-Requires`
- [ ] ERT passes under `emacs -Q`
- [ ] No warning is globally suppressed
- [ ] No generated compiler or scratch artifact is tracked
- [ ] Performance changes include profiler or benchmark evidence

---

## Related

- [modernization.md](modernization.md) - Version floor and obsolete APIs
- [modules.md](modules.md) - Headers, prefixes, and package metadata
- [collections.md](collections.md) - Allocation-aware traversal
- [test.md](test.md) - ERT organization and batch runner

## References

- [GNU Emacs Lisp Manual: Tips and Conventions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Tips.html) - Canonical style and documentation rules
- [GNU Emacs Lisp Manual: Byte Compilation](https://www.gnu.org/software/emacs/manual/html_node/elisp/Byte-Compilation.html) - Compiler behavior and warnings
- [GNU Emacs Lisp Manual: Profiling](https://www.gnu.org/software/emacs/manual/html_node/elisp/Profiling.html) - Built-in CPU and memory profiler
- [package-lint](https://github.com/purcell/package-lint) - Package metadata and compatibility checks
- [Emacs Lisp Style Guide](https://github.com/bbatsov/emacs-lisp-style-guide) - Community naming, layout, and tool guidance
