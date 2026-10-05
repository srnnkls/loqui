---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Testing

ERT tests for domain logic, package conditions, editor adapters, and stateful lifecycle behavior.

## Use ERT by Default

ERT ships with Emacs and integrates with batch execution, the debugger, and Emacs objects.

```elisp
;;; invoice-domain-test.el --- Tests for invoice-domain  -*- lexical-binding: t; -*-

(require 'ert)
(require 'invoice-domain)

(ert-deftest invoice-domain-overdue-p ()
  (let ((invoice (invoice-create
                  "INV-204"
                  1250
                  (encode-time 0 0 0 1 8 2026))))
    (should (invoice-overdue-p
             invoice
             (encode-time 0 0 0 2 8 2026)))))

(provide 'invoice-domain-test)

;;; invoice-domain-test.el ends here
```

Name tests after the public behavior and scenario:

```elisp
invoice-create-rejects-negative-amount
invoice-mark-paid-preserves-original
invoice-ui-refresh-retains-point
invoice-repository-missing-file-is-empty
```

A test name should explain the contract without reading its body.

---

## Put Most Coverage Around the Functional Core

Pure-ish functions need little setup and produce useful failures:

```elisp
(ert-deftest invoice-reminder-decision-cases ()
  (dolist (case '((paid future (skip already-paid))
                  (unpaid past (send "INV-204"))
                  (unpaid future (skip not-due))))
    (pcase-let ((`(,status ,due ,expected) case))
      (ert-info ((format "status=%S due=%S" status due))
        (let ((invoice (invoice-test--invoice
                        :id "INV-204"
                        :status status
                        :due due)))
          (should (equal (invoice-reminder-decision
                          invoice invoice-test--today)
                         expected)))))))
```

Table-driven tests work well for parsers, predicates, `pcase` branches, and normalization. Include the case data in `ert-info` so a failure identifies the row.

Prefer explicit time, configuration, and repository arguments. Do not mock the clock when the function can simply accept `today`.

---

## Assert Invariants and Copy Semantics

```elisp
(ert-deftest invoice-create-rejects-negative-amount ()
  (should-error
   (invoice-create "INV-204" -1 invoice-test--today)
   :type 'invoice-invalid))

(ert-deftest invoice-mark-paid-preserves-original ()
  (let* ((original (invoice-test--invoice :status 'unpaid))
         (paid (invoice-mark-paid original)))
    (should (eq (invoice-status original) 'unpaid))
    (should (eq (invoice-status paid) 'paid))
    (should-not (eq original paid))))
```

When shallow sharing is intentional, test it or test the domain operation that protects callers from it:

```elisp
(ert-deftest invoice-add-tag-does-not-mutate-original-tags ()
  (let* ((original (invoice-test--invoice :tags '(priority)))
         (updated (invoice-add-tag original 'review)))
    (should (equal (invoice-tags original) '(priority)))
    (should (equal (invoice-tags updated) '(review priority)))))
```

Do not assert that all nested values differ unless the API promises independent ownership.

---

## Assert Specific Conditions

```elisp
(ert-deftest invoice-repository-require-signals-missing-id ()
  (let ((condition
         (should-error
          (invoice-repository-require "INV-404")
          :type 'invoice-not-found)))
    (should (equal (cdr condition) '("INV-404")))))
```

`should-error` returns the signaled condition, so tests can inspect data without parsing the displayed message.

Avoid tests that accept any error:

```elisp
;; ✘ WRONG: a void-function bug also passes
(should-error (invoice-repository-require "INV-404"))

;; ✓ CORRECT
(should-error (invoice-repository-require "INV-404")
              :type 'invoice-not-found)
```

Test `user-error` only at command boundaries. Domain tests should expect package conditions or explicit result values.

---

## Use Temporary Buffers for Adapter Behavior

```elisp
(ert-deftest invoice-status-at-point-reads-current-line ()
  (with-temp-buffer
    (insert "INV-204|1250|2026-08-01\n")
    (goto-char (point-min))
    (should (eq (invoice-status-at-point) 'overdue))))
```

Make the buffer's mode, contents, point, narrowing, and local variables explicit when behavior depends on them.

Test state restoration through observable behavior:

```elisp
(ert-deftest invoice-buffer-ids-preserves-point ()
  (with-temp-buffer
    (insert "INV-204\nINV-205\n")
    (goto-char 4)
    (let ((original-point (point)))
      (should (equal (invoice-buffer-ids (current-buffer))
                     '("INV-204" "INV-205")))
      (should (= (point) original-point)))))
```

Do not test that a private helper called `save-excursion`; test that the public operation preserves point.

### Test properties separately from plain text

`buffer-string` includes text but not a useful assertion of all text properties. Use `get-text-property`, overlays, faces, and buffer modified state explicitly when those are part of the feature.

---

## Isolate Filesystem State

Use a unique temporary directory and guarantee cleanup:

```elisp
(ert-deftest invoice-repository-round-trip ()
  (let ((directory (make-temp-file "invoice-test-" t)))
    (unwind-protect
        (let* ((file (expand-file-name "INV-204.el" directory))
               (invoice (invoice-test--invoice :id "INV-204")))
          (invoice-repository-write-file file invoice)
          (should (equal (invoice-repository-read-file file)
                         invoice)))
      (delete-directory directory t))))
```

Never use a developer's real configuration, cache, package directory, or home files in tests. Bind package paths to the temporary directory through explicit parameters or documented options.

Test filenames with spaces, non-ASCII text, missing parents, and permission failures where those are part of the contract.

---

## Replace Dependencies at Narrow Seams

Explicit arguments are the preferred seam:

```elisp
(ert-deftest invoice-find-overdue-uses-loader ()
  (let ((loaded nil)
        (invoices (list (invoice-test--invoice :id "INV-204"))))
    (invoice-find-overdue
     '("INV-204")
     (lambda (id)
       (push id loaded)
       (car invoices))
     invoice-test--today)
    (should (equal loaded '("INV-204")))))
```

When an Emacs callback is fixed by protocol, `cl-letf` can replace its function binding for the dynamic extent of a test:

```elisp
(require 'cl-lib)

(ert-deftest invoice-open-delegates-domain-value-to-ui ()
  (let ((invoice (invoice-test--invoice :id "INV-204"))
        received)
    (cl-letf (((symbol-function 'invoice-repository-require)
               (lambda (_invoice-id) invoice))
              ((symbol-function 'invoice-ui-open)
               (lambda (value) (setq received value))))
      (invoice-open "INV-204"))
    (should (eq received invoice))))
```

Use this sparingly. Replacing global function bindings couples tests to implementation and can obscure missing integration behavior. Ensure created buffers are killed in cleanup.

---

## Test Lifecycle Ownership

A mode that adds hooks, starts timers, creates overlays, or launches a process must reverse those effects.

```elisp
(ert-deftest invoice-mode-removes-local-hook-when-disabled ()
  (with-temp-buffer
    (invoice-mode 1)
    (should (memq #'invoice-ui--after-save after-save-hook))
    (invoice-mode -1)
    (should-not (memq #'invoice-ui--after-save after-save-hook))))
```

Test these lifecycle pairs:

- enable / disable;
- start / cancel;
- attach / detach;
- add-hook / remove-hook;
- add advice / remove advice;
- create process / terminate process;
- create buffer or marker / release it.

Use `unwind-protect` in the test whenever failure before the final assertion could leak state into later tests.

### Test callback logic synchronously

Extract process framing and timer decisions into ordinary functions. Test those functions with chunks and explicit state rather than sleeping until a real timer happens.

Use an integration test for actual process lifecycle only when the process protocol itself is under test. Bound waits with a deadline and clean up on every exit.

---

## Keep Tests Independent

A test must not depend on:

- execution order;
- a package loaded by another test;
- a globally selected buffer;
- existing user options;
- timers or processes left by a previous test;
- network availability unless explicitly marked as an integration test;
- files outside its fixture directory.

Load each test suite under `emacs -Q`. A clean session catches hidden dependencies and accidental reliance on personal configuration.

Do not use `skip-unless` to hide a missing declared dependency. Skip only when the tested capability is genuinely optional and the skip reason is visible.

---

## Use `ert-x` Deliberately

`ert-x` contains useful test helpers, but helper placement changes across Emacs versions. If a test uses one:

```elisp
(require 'ert-x)
```

Verify that the helper exists at the package's minimum Emacs version. Do not assume loading `ert` also loads `ert-x`.

Core primitives are often sufficient and have stable availability:

- `with-temp-buffer`;
- `generate-new-buffer` plus `unwind-protect`;
- `make-temp-file`;
- `cl-letf`;
- `should-error`;
- explicit setup and cleanup functions.

---

## Run Tests in Batch

```sh
emacs -Q --batch \
  -L . \
  -L test \
  -l test/invoice-domain-test.el \
  -l test/invoice-service-test.el \
  -l test/invoice-ui-test.el \
  --funcall ert-run-tests-batch-and-exit
```

The command exits nonzero on test failure. Run the suite on every supported Emacs major version.

Keep test files out of package autoloads and runtime dependency paths. Tests may access private functions when the behavior cannot be observed through a stable public seam, but prefer public contracts.

---

## Summary

- Use ERT as the default test framework
- Put most coverage around deterministic domain functions
- Use table-driven cases for parsers and branching
- Assert exact condition types and structured data
- Test copy and non-mutation promises explicitly
- Use temporary buffers and directories for adapters
- Assert observable state restoration, not implementation forms
- Pass dependencies as functions before replacing globals
- Use `cl-letf` only at narrow fixed protocol seams
- Test enable/disable and start/stop ownership pairs
- Exercise callback logic synchronously where possible
- Keep tests independent under `emacs -Q`
- Require `ert-x` explicitly and verify baseline availability
- Run ERT in batch on every supported Emacs version

---

## Related

- [domain-types.md](domain-types.md) - Invariants and shallow-copy contracts
- [composition.md](composition.md) - Dependency seams and pure cores
- [state-effects.md](state-effects.md) - Lifecycle ownership
- [errors.md](errors.md) - Condition hierarchies
- [quality.md](quality.md) - Full CI gate

## References

- [GNU Emacs Lisp Manual: ERT](https://www.gnu.org/software/emacs/manual/html_node/ert/) - Test definition, assertions, and batch execution
- [Emacs Package Developer's Handbook: Testing](https://github.com/alphapapa/emacs-package-dev-handbook#testing) - Package-oriented test practices
