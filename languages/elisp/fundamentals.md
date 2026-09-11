---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Fundamentals

Evaluation, lexical scope, symbols, equality, and mutability for programmers coming from functional languages.

## Start with Lexical Scope

Every library begins with a first-line cookie:

```elisp
;;; invoice-domain.el --- Invoice domain logic  -*- lexical-binding: t; -*-
```

Lexical scope makes a local binding visible according to program structure. A closure retains bindings from the environment where it was created:

```elisp
(defun invoice-discount-by (percentage)
  "Return a function that discounts an amount by PERCENTAGE."
  (lambda (amount)
    (- amount (* amount percentage))))

(let ((discount (invoice-discount-by 0.15)))
  (funcall discount 200.0))
;; => 170.0
```

Without lexical binding, this closure does not capture `percentage` as intended.

### Special variables remain dynamic

A variable declared with `defvar` or `defcustom` is special. A `let` binding of that symbol is dynamically visible to calls made within the binding:

```elisp
(defvar invoice-render-locale 'en
  "Locale used while rendering invoices.")

(defun invoice-render-date (time)
  "Render TIME using the active invoice locale."
  (pcase invoice-render-locale
    ('en (format-time-string "%Y-%m-%d" time))
    ('de (format-time-string "%d.%m.%Y" time))))

(let ((invoice-render-locale 'de))
  (invoice-render-date (encode-time 0 0 0 4 7 2026)))
;; => "04.07.2026"
```

Use dynamic rebinding for established Emacs protocols and deliberately scoped configuration. Prefer an explicit parameter for ordinary domain dependencies:

```elisp
;; ✓ CORRECT: dependency is visible in the signature
(defun invoice-render-date-for (time locale)
  "Render TIME for LOCALE."
  (pcase locale
    ('en (format-time-string "%Y-%m-%d" time))
    ('de (format-time-string "%d.%m.%Y" time))))

;; ✘ WRONG: undeclared free variable hides a dependency
(defun invoice-render-date (time)
  (pcase locale
    ('en (format-time-string "%Y-%m-%d" time))
    ('de (format-time-string "%d.%m.%Y" time))))
```

The byte compiler reports undeclared free variables. Fix the dependency instead of suppressing the warning.

---

## Understand Evaluation and Quoting

A list in expression position is normally a function or special-form call:

```elisp
(+ 2 3)
;; => 5
```

Quote data that must not be evaluated:

```elisp
'(draft sent paid)
;; => (draft sent paid)
```

Use function quoting for named functions passed as values:

```elisp
(mapcar #'invoice-total invoices)
```

`#'invoice-total` lets the byte compiler check the function reference. Never hard-quote a lambda:

```elisp
;; ✓ CORRECT
(lambda (invoice) (invoice-total invoice))

;; ✘ WRONG: obstructs compilation
'(lambda (invoice) (invoice-total invoice))
```

Avoid quoting values that can be built directly. Keywords evaluate to themselves and work well as boundary tags:

```elisp
(list :status 'paid :amount 1250)
```

Core domain code should generally parse such external representations into named values rather than keep passing raw property lists.

---

## Treat Symbols as Data with Global Slots

A symbol can carry a name, a value binding, a function binding, and properties. Function and variable bindings occupy separate namespaces:

```elisp
(defun invoice-status (invoice)
  "Return the status of INVOICE."
  (invoice--status invoice))

(defvar invoice-status 'enabled)
```

This is legal but confusing. Use distinct names unless the pairing follows an established Emacs convention.

All top-level function and variable names are global. Prefix them with the library name:

```elisp
(defun invoice-total (invoice) ...)
(defun invoice--parse-line (line) ...)
(defcustom invoice-default-currency "EUR" ...)
```

A double hyphen marks implementation details; it does not enforce privacy.

---

## Choose Equality Deliberately

| Function | Use for |
|----------|---------|
| `eq` | Symbol identity, canonical sentinels, same object |
| `eql` | `eq` semantics plus numeric values of the same type |
| `equal` | Recursive structural equality for lists, vectors, strings, records |
| `string=` | String content when both inputs are strings |
| `=` | Numeric equality |

```elisp
(eq 'paid 'paid)                    ; => t
(equal '(paid 1250) '(paid 1250))  ; => t
(string= "EUR" (concat "E" "UR")) ; => t
(= 1 1.0)                          ; => t
(eql 1 1.0)                        ; => nil
```

Do not use `eq` for string or general numeric content:

```elisp
;; ✘ WRONG: object identity is not string equality
(eq currency "EUR")

;; ✓ CORRECT
(string= currency "EUR")
```

Choose hash-table tests at construction time so later lookups use the required semantics:

```elisp
(make-hash-table :test #'equal)
```

---

## Model `nil` Carefully

`nil` means false, the empty list, and the conventional absence value. This is idiomatic, but a domain may need to distinguish those meanings.

```elisp
;; Ambiguous: absent, explicitly false, or an empty collection?
(plist-get payload :approved)
```

Use `plist-member`, `map-contains-key`, a tagged value, or a named struct when presence matters:

```elisp
(if (plist-member payload :approved)
    (list 'present (plist-get payload :approved))
  '(missing))
```

Do not invent an option wrapper for every local conditional. Introduce an explicit variant when the distinction belongs to the domain contract.

---

## Lexical Binding Does Not Imply Immutability

Lists, vectors, hash tables, strings, buffers, and struct slots can all be mutated. Lexical scope changes name resolution, not value semantics.

```elisp
(let ((items (list 'draft 'sent)))
  (setcar items 'paid)
  items)
;; => (paid sent)
```

Prefer fresh values in the core:

```elisp
(defun invoice-add-tag (tags tag)
  "Return TAGS with TAG present, without changing TAGS."
  (if (member tag tags)
      tags
    (cons tag tags)))
```

When order matters and a loop builds a list, local mutation is clear and efficient:

```elisp
(defun invoice-positive-amounts (amounts)
  "Return positive values from AMOUNTS in their original order."
  (let (result)
    (dolist (amount amounts (nreverse result))
      (when (> amount 0)
        (push amount result)))))
```

The mutation is confined to a fresh local list. Callers cannot observe an intermediate state.

### Copy semantics are operation-specific

`copy-sequence` copies only the outer sequence. `copy-tree` recursively copies cons cells but still shares non-cons mutable objects. Hash tables, buffers, markers, overlays, and nested records require domain-specific ownership decisions.

Never call something immutable merely because the outer container was copied.

---

## Summary

- Use lexical binding in every file
- Declare intentional special variables with `defvar` or `defcustom`
- Pass ordinary domain dependencies explicitly
- Quote data and function names deliberately
- Prefix every top-level symbol
- Choose identity, numeric, string, or structural equality consciously
- Make absence explicit when `nil` would collapse domain states
- Treat all mutable objects as shared unless ownership says otherwise
- Keep mutation local to fresh values or explicit effect boundaries

---

## Related

- [domain-types.md](domain-types.md) - Named values and copy semantics
- [composition.md](composition.md) - Explicit dependencies and pure-ish cores
- [collections.md](collections.md) - Container choice and destructive operations
- [state-effects.md](state-effects.md) - Emacs state and dynamic context

## References

- [GNU Emacs Lisp Manual: Selecting Lisp Dialect](https://www.gnu.org/software/emacs/manual/html_node/elisp/Selecting-Lisp-Dialect.html) - Lexical and dynamic binding
- [GNU Emacs Lisp Manual: Symbols](https://www.gnu.org/software/emacs/manual/html_node/elisp/Symbols.html) - Symbol components and namespaces
- [GNU Emacs Lisp Manual: Equality Predicates](https://www.gnu.org/software/emacs/manual/html_node/elisp/Equality-Predicates.html) - Equality semantics
- [Emacs Lisp Elements: Side effect and return value](https://protesilaos.com/emacs/emacs-lisp-elements#h:side-effect-and-return-value) - Runtime mental model
