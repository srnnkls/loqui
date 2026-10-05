---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Domain Types

Named domain values, invariant-preserving constructors, boundary parsing, and honest copy semantics.

## Prefer Named Values in the Core

Property lists, association lists, and hash tables are good interchange formats. They are poor long-lived domain models because keys, required fields, and invariants remain implicit.

```elisp
;; ✘ WRONG: shape and invariants remain implicit everywhere
(defun invoice-overdue-p (invoice today)
  (and (eq (plist-get invoice :status) 'unpaid)
       (time-less-p (plist-get invoice :due-at) today)))
```

Define a domain vocabulary with `cl-defstruct` and ordinary functions:

```elisp
(require 'cl-lib)
(require 'subr-x)

(define-error 'invoice-invalid "Invalid invoice")

(cl-defstruct (invoice (:constructor invoice--create))
  (id nil :read-only t)
  (amount 0 :read-only t)
  (due-at nil :read-only t)
  status
  tags)

(defun invoice--time-value-p (value)
  "Return non-nil when VALUE is a non-nil Emacs time value."
  (and value
       (condition-case nil
           (progn (time-convert value 'list) t)
         (error nil))))

(defun invoice-create (id amount due-at &optional tags)
  "Return an invoice for ID, AMOUNT, DUE-AT, and TAGS.
Signal `invoice-invalid' when an invariant is violated."
  (unless (and (stringp id) (not (string-empty-p id)))
    (signal 'invoice-invalid (list "ID must be a non-empty string" id)))
  (unless (and (numberp amount)
               (>= amount 0)
               (not (and (floatp amount)
                         (= amount 1.0e+INF))))
    (signal 'invoice-invalid (list "AMOUNT must be finite and non-negative" amount)))
  (unless (invoice--time-value-p due-at)
    (signal 'invoice-invalid (list "DUE-AT must be an Emacs time value" due-at)))
  (invoice--create :id id
                   :amount amount
                   :due-at due-at
                   :status 'unpaid
                   :tags (copy-sequence tags)))
```

The private raw constructor keeps ordinary callers on the validating path. The double hyphen communicates package-private intent; it is not access control.

### Slot metadata does not validate values

A `:type` slot option documents intent and can help tools, but it does not enforce runtime validation. Constructors and parsers own invariants.

```elisp
;; ✘ WRONG: annotation presented as enforcement
(cl-defstruct payment
  (amount 0 :type number))

(make-payment :amount "many")
;; Construction is not rejected merely because of :type.
```

Read-only slots prevent ordinary `setf` through generated accessors. They do not make nested objects persistent or protect against every lower-level mutation.

---

## Parse at the Boundary

Let adapters accept permissive external shapes, then construct a canonical domain value:

```elisp
(defun invoice-parse (payload)
  "Parse plist PAYLOAD into an invoice."
  (invoice-create
   (or (plist-get payload :id)
       (signal 'invoice-invalid (list "Missing :id" payload)))
   (or (plist-get payload :amount) 0)
   (or (plist-get payload :due-at)
       (signal 'invoice-invalid (list "Missing :due-at" payload)))
   (plist-get payload :tags)))
```

Core functions now receive a known shape:

```elisp
(defun invoice-overdue-p (invoice today)
  "Return non-nil when INVOICE is unpaid and due before TODAY."
  (and (eq (invoice-status invoice) 'unpaid)
       (time-less-p (invoice-due-at invoice) today)))
```

Do not repeatedly validate the same raw keys throughout application logic:

```elisp
;; ✘ WRONG: boundary representation leaks into every decision
(defun invoice-overdue-p (payload today)
  (let ((status (plist-get payload :status))
        (due-at (plist-get payload :due_at)))
    (and (symbolp status)
         due-at
         (eq status 'unpaid)
         (time-less-p due-at today))))
```

The parser can support multiple external versions. The domain representation remains singular.

---

## Treat Structs as Mutable Records

A `cl-defstruct` value is a mutable record. Elisp does not provide persistent value semantics merely because updates happen through ordinary functions.

A functional-style update copies the outer record, changes the copy, and returns it:

```elisp
(defun invoice-mark-paid (invoice)
  "Return a paid copy of INVOICE."
  (let ((updated (copy-invoice invoice)))
    (setf (invoice-status updated) 'paid)
    updated))
```

This keeps the original status unchanged:

```elisp
(let* ((original (invoice-create "INV-204" 1250
                                 (encode-time 0 0 0 1 10 2026)))
       (paid (invoice-mark-paid original)))
  (list (invoice-status original)
        (invoice-status paid)))
;; => (unpaid paid)
```

### Generated copies are shallow

`copy-invoice` copies the struct, not the mutable objects held in its slots:

```elisp
(let* ((original (invoice-create "INV-204" 1250
                                 (encode-time 0 0 0 1 10 2026)
                                 '(priority)))
       (copy (copy-invoice original)))
  (setcar (invoice-tags copy) 'archived)
  (invoice-tags original))
;; => (archived)
```

Both records still point to the same list. When nested ownership must be independent, reconstruct or copy that slot deliberately:

```elisp
(defun invoice-copy-independent (invoice)
  "Return a copy of INVOICE with an independent tags list."
  (let ((copy (copy-invoice invoice)))
    (setf (invoice-tags copy)
          (copy-sequence (invoice-tags invoice)))
    copy))
```

A list copy is enough when tags are immutable symbols. Nested vectors, hash tables, markers, overlays, or other structs need their own ownership policy. Do not write a generic deep-copy helper and assume it understands domain identity.

---

## Keep Mutation Local

Mutation can be the clearest implementation detail when it cannot escape before the result is complete:

```elisp
(defun invoice-add-tag (invoice tag)
  "Return a copy of INVOICE containing TAG."
  (if (memq tag (invoice-tags invoice))
      invoice
    (let ((updated (copy-invoice invoice)))
      (setf (invoice-tags updated)
            (cons tag (invoice-tags invoice)))
      updated)))
```

The function never mutates caller-owned list structure. Returning the original when nothing changes is safe only because the package treats domain values as immutable by convention.

Document that convention at the public API. Tests should assert that update functions leave their inputs observably unchanged.

---

## Model Variants Explicitly

Elisp has no closed algebraic data type declaration. Use distinct structs or a visible tag when variants carry different data:

```elisp
(cl-defstruct (invoice-issued (:constructor invoice-issued-create))
  invoice)

(cl-defstruct (invoice-rejected (:constructor invoice-rejected-create))
  reason
  payload)

(defun invoice-import (payload)
  "Return an issued or rejected invoice result for PAYLOAD."
  (condition-case condition
      (invoice-issued-create :invoice (invoice-parse payload))
    (invoice-invalid
     (invoice-rejected-create :reason (cadr condition)
                              :payload payload))))
```

Callers can dispatch with predicates or `pcase` `cl-struct` patterns. The set is conventional rather than compiler-enforced, so retain a fallback branch at external boundaries.

For a small internal protocol, a tagged list can be sufficient:

```elisp
(list 'accepted invoice)
(list 'rejected reason)
```

Choose one representation per bounded context. Do not mix tagged lists, structs, and plists for the same concept without an adapter.

---

## Choose Structs, EIEIO, or Maps by Semantics

| Need | Default |
|------|---------|
| Named data with generated accessors | `cl-defstruct` |
| Open dynamic dispatch and inheritance | EIEIO |
| External or sparse key/value payload | plist, alist, or hash table at the boundary |
| Tiny private tuple with obvious positions | list or vector |

Use EIEIO when dynamic dispatch is part of the domain. Do not introduce classes merely to group related functions; a prefixed module already supplies a namespace.

---

## Domain-Driven Design in Elisp

- Ubiquitous language: package-prefixed structs and functions name domain concepts.
- Value objects: construction and update functions preserve invariants by convention.
- Aggregates: one module owns mutation of a connected group of records.
- Repositories: adapters translate files, SQLite rows, buffer text, or process output into domain values.
- Services: ordinary functions coordinate domain operations without reading Emacs state implicitly.

Elisp cannot make every illegal state unrepresentable. It can make the valid path obvious, centralize construction, and keep malformed external data out of the core.

---

## Summary

- Use named structs for stable domain concepts
- Keep raw constructors private and validate in public constructors
- Parse external plists, alists, text, and JSON at adapters
- Treat slot type metadata as documentation, not enforcement
- Treat structs and nested objects as mutable
- Remember that generated struct copies are shallow
- Copy or reconstruct nested state according to domain ownership
- Keep mutation inside update functions and fresh local values
- Use EIEIO only when open dynamic dispatch is genuinely required
- Test invariants and non-mutation as observable contracts

---

## Related

- [fundamentals.md](fundamentals.md) - Mutability, equality, and `nil`
- [composition.md](composition.md) - Domain/adaptor boundaries
- [control-flow.md](control-flow.md) - Matching explicit variants
- [errors.md](errors.md) - Conditions versus result variants
- [test.md](test.md) - Constructor and copy-semantics tests

## References

- [GNU Emacs Lisp Manual: Records](https://www.gnu.org/software/emacs/manual/html_node/elisp/Records.html) - Records and `cl-defstruct`
- [GNU Common Lisp Extensions Manual: Structures](https://www.gnu.org/software/emacs/manual/html_node/cl/Structures.html) - Generated accessors, predicates, and copiers
- [GNU Emacs Lisp Manual: Sequence Functions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Sequence-Functions.html) - Copy behavior for sequences
- [Parse, Don't Validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) - Boundary parsing principle
