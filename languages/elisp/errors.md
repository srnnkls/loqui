---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Errors

Domain alternatives, package-specific conditions, interactive errors, narrow handlers, and reliable cleanup.

## Separate Alternatives from Exceptional Conditions

Use a return value when callers are expected to branch as part of ordinary domain flow:

```elisp
(defun invoice-payment-decision (invoice payment)
  "Return the payment decision for INVOICE and PAYMENT."
  (cond
   ((eq (invoice-status invoice) 'paid)
    '(rejected already-paid))
   ((/= (invoice-amount invoice) (payment-amount payment))
    '(rejected amount-mismatch))
   (t
    (list 'accepted (invoice-id invoice)))))
```

Use a condition when normal computation cannot honor its contract:

- malformed external data;
- unavailable storage;
- missing required entity;
- violated invariant;
- invalid API use.

Do not return `nil` for every failure. It collapses absence, false, empty, and failure into one value and discards context.

---

## Define a Package Condition Hierarchy

```elisp
(define-error 'invoice-error "Invoice error")
(define-error 'invoice-invalid "Invalid invoice" 'invoice-error)
(define-error 'invoice-not-found "Invoice not found" 'invoice-error)
(define-error 'invoice-storage-error "Invoice storage error" 'invoice-error)
```

Signal the narrowest useful condition with structured data:

```elisp
(defun invoice-repository-require (invoice-id)
  "Return INVOICE-ID's invoice or signal `invoice-not-found'."
  (or (invoice-repository-load invoice-id)
      (signal 'invoice-not-found (list invoice-id))))
```

The displayed message comes from the condition definition. The data carries values callers can inspect without parsing prose.

```elisp
(condition-case condition
    (invoice-repository-require invoice-id)
  (invoice-not-found
   (let ((missing-id (cadr condition)))
     (invoice-log-missing missing-id)
     nil)))
```

Prefix condition symbols like every other package global.

### Preserve the original category when re-signaling

If a layer performs cleanup or logging but cannot recover, re-signal the same condition:

```elisp
(condition-case condition
    (invoice-repository-require invoice-id)
  (invoice-not-found
   (invoice-metrics-record 'missing invoice-id)
   (signal (car condition) (cdr condition))))
```

Do not replace a precise condition with a generic `error` string.

### Add boundary context structurally

A repository can translate a low-level condition into its public condition while retaining the original value:

```elisp
(defun invoice-repository-read-file (file)
  "Read invoice data from FILE."
  (condition-case condition
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string))
    (file-error
     (signal 'invoice-storage-error
             (list :file file :cause condition)))))
```

The repository API now exposes its own stable condition. Diagnostic data still contains the underlying file error.

---

## Catch Only What You Can Handle

```elisp
;; ✓ CORRECT: known recovery
(condition-case condition
    (invoice-import payload)
  (invoice-invalid
   (invoice-import-rejected payload condition)))

;; ✘ WRONG: hides programming errors and unrelated failures
(condition-case condition
    (invoice-import payload)
  (error
   (message "Import failed: %s" condition)
   nil))
```

A handler should do one of three things:

- recover and return a documented value;
- translate into a boundary-specific condition;
- perform required side work and re-signal.

Do not catch an error merely to log it; the debugger and batch runner already preserve backtraces.

### Preserve quit

User quit is a control signal, not a routine package failure. Do not catch `quit` unless the operation has a specific cancellation contract. Never use a catch-all handler that swallows keyboard quit.

Long loops should remain interruptible. Avoid binding `inhibit-quit` across substantial work; use it only around a tiny state transition that must be atomic with respect to quit.

---

## Use `user-error` at Interactive Boundaries

Commands can report correctable user input or context problems with `user-error`:

```elisp
(defun invoice-open (invoice-id)
  "Open the invoice named INVOICE-ID."
  (interactive (list (read-string "Invoice ID: ")))
  (condition-case condition
      (invoice-ui-open
       (invoice-repository-require invoice-id))
    (invoice-not-found
     (user-error "No invoice named %s" (cadr condition)))))
```

Domain and repository functions should signal package conditions rather than `user-error`; they may run in batch jobs, timers, tests, or another package with no interactive user.

Do not use `message` as failure propagation:

```elisp
;; ✘ WRONG: caller receives a formatted string, not a failure
(defun invoice-repository-require (invoice-id)
  (or (invoice-repository-load invoice-id)
      (message "Missing invoice %s" invoice-id)))
```

Emacs error messages conventionally start with a capital letter and omit trailing punctuation.

---

## Reserve `ignore-errors` for Truly Optional Work

`ignore-errors` turns any `error` condition into `nil` and discards its category:

```elisp
;; ✘ WRONG: corrupt or unavailable data becomes unexplained nil
(ignore-errors
  (invoice-repository-read-file file))
```

Use a narrow handler when absence is expected:

```elisp
(condition-case nil
    (invoice-repository-read-file file)
  (file-missing nil))
```

Even here, consider whether a missing file is a valid empty repository or a deployment problem. Encode the actual contract.

`with-demoted-errors` is appropriate only for best-effort peripheral work where continuing is intentional and a diagnostic is still useful, such as an optional mode-line decoration. Keep it out of domain, persistence, and migration logic.

---

## Guarantee Cleanup with `unwind-protect`

```elisp
(defun invoice-repository-with-transaction (function)
  "Call FUNCTION inside an invoice repository transaction."
  (invoice-repository-begin)
  (let ((committed nil))
    (unwind-protect
        (prog1 (funcall function)
          (let ((inhibit-quit t))
            (invoice-repository-commit)
            (setq committed t)))
      (unless committed
        (invoice-repository-rollback)))))
```

Cleanup runs after normal return, errors, and quit. The commit and its state update form one quit-inhibited transition, so a pending quit cannot trigger rollback after a successful commit. Keep resource ownership local: the layer that acquires a resource defines how it is released.

This shape does not make external operations transactional. A process request already sent or file already replaced may require explicit compensation rather than rollback.

Prefer dedicated save forms when they match the resource:

- `save-excursion` for point and current buffer;
- `save-restriction` for narrowing;
- `save-match-data` for regexp match state;
- `atomic-change-group` for buffer text rollback.

---

## Distinguish Conditions from Nonlocal Control Flow

`catch` and `throw` provide named nonlocal exits. They are useful for escaping nested traversal when the exit is part of the algorithm:

```elisp
(defun invoice-find-first (tree predicate)
  "Return the first node in TREE satisfying PREDICATE."
  (catch 'invoice-found
    (invoice-walk
     tree
     (lambda (node)
       (when (funcall predicate node)
         (throw 'invoice-found node))))
    nil))
```

They do not carry a condition hierarchy or debugger semantics. Do not use `throw` to report storage, validation, or API failures.

Conversely, do not signal an error merely to break out of a normal search. Use `seq-find`, a loop, or a named catch.

---

## Fail Fast on Invariants and Bugs

A public constructor can signal `invoice-invalid` for malformed input. An impossible internal state after successful construction indicates a bug:

```elisp
(defun invoice-status-label (invoice)
  "Return a label for INVOICE's status."
  (pcase (invoice-status invoice)
    ('unpaid "Open")
    ('paid "Paid")
    ('void "Void")
    (status
     (error "Unexpected invoice status: %S" status))))
```

Do not silently invent a fallback for an invariant violation. A clear failure preserves the first useful backtrace.

Assertions can document internal preconditions during development, but public APIs should signal documented package conditions for caller errors.

---

## Summary

- Return tagged values for expected domain alternatives
- Signal conditions when a function cannot honor its contract
- Define a prefixed package condition hierarchy
- Put machine-readable values in condition data
- Catch only conditions the current layer can recover from or translate
- Re-signal precise conditions after side work
- Preserve quit and debugger visibility
- Translate package conditions to `user-error` only at commands
- Do not use `message`, `ignore-errors`, or generic `error` handlers as propagation
- Guarantee owned cleanup with `unwind-protect`
- Use dedicated save forms for editor state
- Reserve `catch` and `throw` for normal nonlocal control flow
- Fail visibly on violated internal invariants

---

## Related

- [domain-types.md](domain-types.md) - Result variants and constructor invariants
- [composition.md](composition.md) - Effect plans and boundary translation
- [state-effects.md](state-effects.md) - Resource cleanup and cancellation
- [test.md](test.md) - Asserting precise conditions

## References

- [GNU Emacs Lisp Manual: Signaling Errors](https://www.gnu.org/software/emacs/manual/html_node/elisp/Signaling-Errors.html) - `signal`, `error`, and condition data
- [GNU Emacs Lisp Manual: Handling Errors](https://www.gnu.org/software/emacs/manual/html_node/elisp/Handling-Errors.html) - `condition-case` and handlers
- [GNU Emacs Lisp Manual: Cleaning Up from Nonlocal Exits](https://www.gnu.org/software/emacs/manual/html_node/elisp/Cleanups.html) - `unwind-protect`
- [GNU Emacs Lisp Manual: Catch and Throw](https://www.gnu.org/software/emacs/manual/html_node/elisp/Catch-and-Throw.html) - Nonlocal control flow
