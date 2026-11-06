---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Collections

Container choice, standard collection libraries, visible mutation, and allocation-aware transformations.

## Choose a Container by Access Pattern

| Container | Prefer when |
|-----------|-------------|
| List | Sequential traversal, stack/queue building, recursive shape |
| Vector | Fixed-size indexed data and random access |
| String | Text treated as characters rather than buffer content |
| Alist | Small ordered key/value data, easy literals, duplicate-key semantics |
| Plist | Small symbol-keyed metadata and Emacs APIs that already use plists |
| Hash table | Larger mutable lookup tables and explicit key equality |
| Struct | Stable named domain fields with generated accessors |

Do not default every domain value to a plist because Emacs APIs use them. Boundary formats and domain representations have different jobs.

### Lists are linked structures

`car`, `cdr`, `push`, and front removal are cheap. Repeated `nth` access is not:

```elisp
;; ✘ WRONG: repeated traversal by index
(dotimes (index (length invoices))
  (invoice-process (nth index invoices)))

;; ✓ CORRECT: one sequential traversal
(dolist (invoice invoices)
  (invoice-process invoice))
```

Use a vector when indexed access is the real operation:

```elisp
(dotimes (index (length invoice-table))
  (invoice-process (aref invoice-table index)))
```

---

## Require the Library That Owns the Vocabulary

```elisp
(require 'cl-lib)  ; cl-loop, cl-labels, cl-defstruct
(require 'map)     ; map-elt, map-insert, map-keys, map-values
(require 'seq)     ; seq-map, seq-filter, seq-reduce, seq-find
(require 'subr-x)  ; thread-first, thread-last, string-trim
```

Do not rely on interactive startup or another package to load these first. A library should compile and load correctly under `emacs -Q` with only its declared dependencies.

`pcase` is autoloaded at the guide's baseline. Require it explicitly only when doing so makes a substantial protocol dependency clearer.

---

## Use the Narrowest Clear API

### Built-in list functions

Use `mapcar`, `memq`, `member`, `assq`, `assoc`, and `dolist` when the operation is specifically about lists. Primitive searches are often clearer and faster than a generic abstraction.

```elisp
(defun invoice-find-by-id (invoices invoice-id)
  "Return the invoice named INVOICE-ID from INVOICES."
  (seq-find
   (lambda (invoice)
     (string= (invoice-id invoice) invoice-id))
   invoices))
```

`seq-find` is appropriate here because the predicate is domain-specific. For an alist lookup, use `assoc` directly.

### Generic sequence functions

Use `seq` when the same operation should work across sequence types:

```elisp
(defun invoice-valid-amounts (amounts)
  "Return finite non-negative numbers from AMOUNTS."
  (seq-filter
   (lambda (amount)
     (and (numberp amount)
          (>= amount 0)
          (not (and (floatp amount)
                    (= amount 1.0e+INF)))))
   amounts))

(seq-some (lambda (invoice)
            (invoice-overdue-p invoice today))
          invoices)
(seq-every-p #'invoice-valid-p invoices)
(seq-reduce #'+ amounts 0)
```

`seq-*` functions use generic dispatch. That cost is usually irrelevant in application logic; it can matter in a measured hot loop.

### Generic map functions

Use `map` when callers may supply different map types:

```elisp
(require 'map)

(defun invoice-currency (metadata)
  "Return the currency in METADATA, defaulting to EUR."
  (map-elt metadata :currency "EUR"))
```

Do not pass the deprecated comparison argument to `map-elt`. Equality belongs to the container:

- plist keys use identity semantics;
- alist keys use structural equality through the map API;
- hash tables use the test chosen at construction.

When key presence differs from a stored `nil`, use `map-contains-key` rather than inspecting only `map-elt`.

---

## Distinguish Persistent-Looking and Destructive Updates

Return a new map with `map-insert`:

```elisp
(defun invoice-with-currency (metadata currency)
  "Return METADATA associated with CURRENCY."
  (map-insert metadata :currency currency))
```

Mutate a map in place with `map-put!` when ownership permits it:

```elisp
(defun invoice-cache-store (cache invoice)
  "Store INVOICE in owned CACHE and return INVOICE."
  (map-put! cache (invoice-id invoice) invoice)
  invoice)
```

A generalized variable can also be updated through `setf`:

```elisp
(setf (map-elt metadata :currency) "EUR")
```

The old `map-put` API is obsolete in Emacs 31. Choose `map-insert`, `map-put!`, or `setf` so mutation intent is visible.

### Know destructive list operations

These can reuse or alter list structure:

- `sort`;
- `delete` and `delete-dups`;
- `nreverse`;
- `nconc`;
- `mapcan` through concatenation of returned lists;
- `setcar` and `setcdr`.

Copy caller-owned input before using a destructive operation:

```elisp
(defun invoice-sort-by-id (invoices)
  "Return INVOICES ordered by ID without changing the input list."
  (sort (copy-sequence invoices)
        (lambda (left right)
          (string-lessp (invoice-id left)
                        (invoice-id right)))))
```

`copy-sequence` is shallow. Sorting no longer rearranges the caller's outer list, but invoice objects inside remain shared.

---

## Use Threading Macros When Argument Position Fits

`thread-first` inserts the previous value as the first argument. `thread-last` inserts it as the last argument.

```elisp
(require 'subr-x)

(thread-first invoice
              invoice-id
              string-trim
              upcase)

(thread-last invoices
             (seq-filter #'invoice-unpaid-p)
             (seq-map #'invoice-id)
             (string-join ", "))
```

Choose based on the called functions' signatures. Do not reorder APIs merely to satisfy a pipeline.

A pipeline becomes harder to read when:

- intermediate values need names;
- several values evolve together;
- a stage has hidden mutation;
- error context belongs between stages;
- the threaded argument changes position repeatedly.

Use `let*` in those cases.

---

## Prefer One-Pass Local Builders in Hot or Effectful Code

A chain of `seq-filter` and `seq-map` allocates intermediate collections:

```elisp
(defun invoice-large-open-ids (invoices threshold)
  "Return IDs of open INVOICES above THRESHOLD."
  (seq-map
   #'invoice-id
   (seq-filter
    (lambda (invoice)
      (and (eq (invoice-status invoice) 'unpaid)
           (> (invoice-amount invoice) threshold)))
    invoices)))
```

That version is clear and often correct. If profiling identifies it as hot, fuse the traversal:

```elisp
(defun invoice-large-open-ids (invoices threshold)
  "Return IDs of open INVOICES above THRESHOLD."
  (let (ids)
    (dolist (invoice invoices (nreverse ids))
      (when (and (eq (invoice-status invoice) 'unpaid)
                 (> (invoice-amount invoice) threshold))
        (push (invoice-id invoice) ids)))))
```

`push` followed by one `nreverse` is the standard list-builder pattern. Do not append repeatedly to the end of a growing list.

For effects, use a loop even when a generic iterator exists:

```elisp
(dolist (file invoice-files)
  (invoice-import-file file))
```

The loop advertises that the return list is irrelevant.

---

## Keep Collection Ownership Explicit

Before mutating, answer:

- Did this function allocate the container?
- Can a caller retain another reference?
- Are nested values mutable and shared?
- Does the public API promise a fresh result?
- Is identity significant, as with buffers, markers, or overlays?

Hash tables are mutable reference objects. `copy-hash-table` copies the table but shares keys and values. A copied list of structs still shares the structs. A copied struct can still share nested lists.

Name domain-specific copy functions after the ownership they provide; avoid vague names such as `deep-copy` unless the domain truly defines every nested case.

---

## Avoid Dependency Reflexes

Contemporary core Emacs already supplies:

- mapping, filtering, reduction, searching, grouping, and predicates through `seq`;
- generic map lookup and updates through `map`;
- threading and string helpers through `subr-x`;
- destructuring and matching through `pcase`;
- richer loops, local functions, and structs through `cl-lib`.

Do not automatically add `dash.el`, `s.el`, `f.el`, or `ht.el`. A third-party dependency is justified when its API materially improves the package, is used broadly enough to repay its cost, and agrees with the supported Emacs versions.

---

## Summary

- Choose collections by access and ownership semantics
- Traverse lists sequentially instead of indexing repeatedly
- Require `seq`, `map`, `cl-lib`, and `subr-x` explicitly when used
- Prefer primitive list operations for specifically list-shaped work
- Use generic APIs when container independence matters
- Put equality semantics in the container, not `map-elt`
- Use `map-insert` for a new map and `map-put!` for owned mutation
- Copy caller-owned outer structure before destructive operations
- Remember every ordinary copy described here is shallow
- Use threading macros only when argument position stays natural
- Fuse pipelines only after profiling or when effects demand a loop
- Prefer built-ins before collection convenience packages

---

## Related

- [fundamentals.md](fundamentals.md) - Equality and mutability
- [domain-types.md](domain-types.md) - Struct and nested copy semantics
- [control-flow.md](control-flow.md) - Iteration selection
- [quality.md](quality.md) - Benchmarking and profiling

## References

- [GNU Emacs Lisp Manual: Sequences, Arrays, and Vectors](https://www.gnu.org/software/emacs/manual/html_node/elisp/Sequences-Arrays-Vectors.html) - Sequence types and operations
- [GNU Emacs Lisp Manual: Sequence Functions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Sequence-Functions.html) - Generic sequence API
- [GNU Emacs Lisp Manual: Generic Functions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Generic-Functions.html) - Generic dispatch model
- [GNU Emacs source: map.el](https://github.com/emacs-mirror/emacs/blob/emacs-31/lisp/emacs-lisp/map.el) - Current map API and deprecations
