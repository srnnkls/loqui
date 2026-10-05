---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Control Flow

Branching, conditional bindings, pattern matching, destructuring, and iteration choices.

## Choose the Smallest Clear Conditional

Use `if` for two branches, `when` or `unless` for one branch, and `cond` when several predicates differ:

```elisp
(defun invoice-payment-label (invoice)
  "Return a payment label for INVOICE."
  (cond
   ((eq (invoice-status invoice) 'paid) "Paid")
   ((invoice-overdue-p invoice (current-time)) "Overdue")
   (t "Open")))
```

The final `cond` fallback is `t`. Do not use foreign-language markers such as `else` or `:else`.

Avoid `progn` in an `if` else branch; the else branch already accepts multiple forms:

```elisp
;; ✓ CORRECT
(if invoice
    (invoice-render invoice)
  (invoice-log-missing invoice-id)
  nil)

;; ✘ WRONG: redundant progn in the else branch
(if invoice
    (invoice-render invoice)
  (progn
    (invoice-log-missing invoice-id)
    nil))
```

A multi-form then branch does require `progn`, though extracting a named function is often clearer.

---

## Bind and Test with Starred Forms

Use `if-let*`, `when-let*`, and `and-let*`. Their bindings are sequential and stop at the first `nil` value.

```elisp
(if-let* ((invoice (invoice-repository-load invoice-id))
          (account (invoice-account invoice))
          (email (account-billing-email account)))
    (invoice-send-reminder invoice email)
  (invoice-record-missing-contact invoice-id))
```

Later bindings can use earlier ones. A predicate-only clause can be included without naming a value:

```elisp
(when-let* ((invoice (invoice-repository-load invoice-id))
            ((eq (invoice-status invoice) 'unpaid))
            ((invoice-overdue-p invoice today)))
  (invoice-send-reminder invoice))
```

Use `and-let*` when the useful result is the final expression:

```elisp
(defun invoice-billing-email (invoice-id)
  "Return the billing email for INVOICE-ID, or nil."
  (and-let* ((invoice (invoice-repository-load invoice-id))
             (account (invoice-account invoice)))
    (account-billing-email account)))
```

Do not teach obsolete unstarred forms or their single-binding shorthand:

```elisp
;; ✘ WRONG: obsolete on Emacs 31
(if-let (invoice (invoice-repository-load invoice-id))
    (invoice-render invoice)
  nil)
```

Conditional bindings treat `nil` as failure. Use plain `let*` when `nil` is a valid bound value that must continue through the computation.

---

## Use `pcase` for Structural Decisions

`pcase` combines branching, binding, predicates, and destructuring:

```elisp
(defun invoice-handle-event (event)
  "Handle one invoice EVENT."
  (pcase event
    (`(issued ,invoice)
     (invoice-index invoice))
    (`(paid ,invoice-id ,paid-at)
     (invoice-record-payment invoice-id paid-at))
    (`(rejected ,reason)
     (invoice-log-rejection reason))
    (_
     (signal 'invoice-invalid-event (list event)))))
```

Quote literal symbols in patterns. Unquoted symbols usually bind values:

```elisp
(pcase status
  ('paid "Paid")
  ('unpaid "Open")
  (_ "Unknown"))
```

### Combine predicates and bindings

```elisp
(pcase value
  ((and (pred invoice-p) invoice)
   (invoice-render invoice))
  ((pred stringp)
   (invoice-render (invoice-parse-line value)))
  (_
   (signal 'wrong-type-argument (list 'invoice-p value))))
```

A guard can keep a domain predicate visible:

```elisp
(pcase invoice
  ((and candidate
        (guard (invoice-overdue-p candidate today)))
   (invoice-send-reminder candidate))
  (_ nil))
```

When a guard contains most of the business logic, move that logic into an ordinary function and use `cond` or `if`.

### Destructure structs explicitly

```elisp
(require 'cl-lib)

(pcase invoice
  ((cl-struct invoice (status 'paid) (id id))
   (format "%s is paid" id))
  ((cl-struct invoice (status 'unpaid) (id id))
   (format "%s remains open" id)))
```

`cl-struct` patterns call generated accessors. Require `cl-lib` in the library defining or consuming the struct protocol.

### Keep one backquote level

Emacs 31 rejects nested backquotes in `pcase` patterns. Split deeper matching into stages:

```elisp
;; ✓ CORRECT: sequential, shallow patterns
(pcase event
  (`(invoice ,payload)
   (pcase payload
     (`(:id ,id :status ,status)
      (invoice-handle id status))
     (_ (signal 'invoice-invalid-event (list event)))))
  (_ nil))
```

Do not compress nested domain parsing into one quasiquoted pattern. Separate stages produce better error locations and remain portable.

---

## Use `pcase-let*` for Sequential Destructuring

`pcase-let*` is useful when each destructuring step depends on the previous result:

```elisp
(defun invoice-row-total (row)
  "Return the total encoded by ROW."
  (pcase-let* ((`(,invoice-id . ,payload) row)
               (`(:amount ,amount :tax ,tax) payload))
    (list invoice-id (+ amount tax))))
```

Use ordinary `let*` when no structural match is needed. Destructuring should reveal a stable shape, not hide loose assumptions about external input. Parse untrusted values through a boundary function first.

A failed `pcase-let*` pattern signals an error. Use `pcase` with a fallback when mismatch is expected input rather than an invariant violation.

---

## Choose Transformations or Loops by Intent

### Transform when the result is a collection

```elisp
(require 'seq)

(defun invoice-open-ids (invoices)
  "Return IDs of unpaid INVOICES."
  (seq-map #'invoice-id
           (seq-filter
            (lambda (invoice)
              (eq (invoice-status invoice) 'unpaid))
            invoices)))
```

### Use `dolist` for effectful traversal

```elisp
(defun invoice-refresh-buffers (buffers)
  "Refresh every live buffer in BUFFERS."
  (dolist (buffer buffers)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (revert-buffer :ignore-auto :noconfirm)))))
```

Do not allocate a discarded result with `mapcar`:

```elisp
;; ✘ WRONG
(mapcar #'invoice-refresh-buffer buffers)

;; ✓ CORRECT
(dolist (buffer buffers)
  (invoice-refresh-buffer buffer))
```

### Use `push` and `nreverse` for a local builder

```elisp
(defun invoice-large-ids (invoices threshold)
  "Return IDs whose invoice amount exceeds THRESHOLD."
  (let (ids)
    (dolist (invoice invoices (nreverse ids))
      (when (> (invoice-amount invoice) threshold)
        (push (invoice-id invoice) ids)))))
```

This confines mutation to fresh local state and traverses the input once.

### Use `cl-loop` when it improves the whole expression

```elisp
(require 'cl-lib)

(defun invoice-total-open (invoices)
  "Return the total amount of unpaid INVOICES."
  (cl-loop for invoice in invoices
           when (eq (invoice-status invoice) 'unpaid)
           sum (invoice-amount invoice)))
```

Do not use `cl-loop` merely to make simple iteration look clever. Prefer it when its accumulation, destructuring, or early-exit vocabulary is clearer than manual state.

---

## Do Not Assume Tail-Call Optimization

General recursive list processing consumes stack and adds function-call overhead. Use recursion for naturally recursive, bounded structures; use iteration for ordinary long sequences.

```elisp
;; ✘ WRONG for an unbounded flat list
(defun invoice-sum (amounts)
  (if amounts
      (+ (car amounts) (invoice-sum (cdr amounts)))
    0))

;; ✓ CORRECT
(defun invoice-sum (amounts)
  (let ((total 0))
    (dolist (amount amounts total)
      (setq total (+ total amount)))))
```

For tree traversal, document the expected depth and consider an explicit worklist when input depth is untrusted.

---

## Keep Control Flow Boring

- Extract domain predicates instead of embedding business rules in patterns.
- Use early validation to reduce nesting.
- Avoid nonlocal `catch`/`throw` for routine function returns.
- Reserve `condition-case` for conditions, not ordinary branching.
- Preserve `quit`; do not catch it under a broad handler.
- Prefer a named intermediate binding over deeply nested calls.

---

## Summary

- Use `if`, `when`, `unless`, and `cond` for predicate-based branches
- Use only starred conditional-binding forms
- Use `pcase` for genuine structural decisions
- Quote literal symbols and retain a fallback at external boundaries
- Keep `pcase` patterns shallow and free of nested backquotes
- Use `pcase-let*` for trusted sequential destructuring
- Transform collections when returning collections
- Use loops for effects, local accumulation, and measured hot paths
- Do not assume tail-call optimization
- Keep domain behavior in named functions rather than clever patterns

---

## Related

- [domain-types.md](domain-types.md) - Struct and variant representations
- [collections.md](collections.md) - Sequence operations and costs
- [errors.md](errors.md) - Conditions versus ordinary branches
- [quality.md](quality.md) - Profiling loops and transformations

## References

- [GNU Emacs Lisp Manual: Conditionals](https://www.gnu.org/software/emacs/manual/html_node/elisp/Conditionals.html) - Conditional forms
- [GNU Emacs Lisp Manual: Pattern-Matching Conditional](https://www.gnu.org/software/emacs/manual/html_node/elisp/Pattern_002dMatching-Conditional.html) - `pcase` pattern language
- [GNU Emacs Lisp Manual: Iteration](https://www.gnu.org/software/emacs/manual/html_node/elisp/Iteration.html) - `while`, `dolist`, and `dotimes`
- [Emacs Lisp Elements: Pattern match with pcase](https://protesilaos.com/emacs/emacs-lisp-elements#h:pattern-match-with-pcase-and-related) - Contemporary examples
