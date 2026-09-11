---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp Composition

Functional core, imperative shell, explicit dependencies, and the boundary between functions and macros.

## Build a Functional Core Inside the Runtime

Emacs is intentionally stateful. The design goal is not purity everywhere; it is to know where state enters and where effects happen.

Use this flow:

1. read Emacs or external state in an adapter;
2. parse it into domain values;
3. run ordinary transformations on explicit inputs;
4. return a decision or effect description;
5. let the adapter apply the effect.

```elisp
(defun invoice-reminder-decision (invoice today)
  "Return the reminder decision for INVOICE at TODAY."
  (cond
   ((eq (invoice-status invoice) 'paid)
    '(skip already-paid))
   ((time-less-p (invoice-due-at invoice) today)
    (list 'send (invoice-id invoice)))
   (t
    '(skip not-due))))
```

This function does not read time, point, buffers, files, or global configuration. Its result is testable data.

The shell owns those effects:

```elisp
(defun invoice-send-reminder-at-point ()
  "Send a reminder for the invoice at point when one is due."
  (interactive)
  (let* ((invoice (invoice-ui--invoice-at-point))
         (decision (invoice-reminder-decision invoice (current-time))))
    (pcase decision
      (`(send ,id)
       (invoice-repository-record-reminder id)
       (message "Sent reminder for %s" id))
      (`(skip ,reason)
       (message "Skipped reminder: %s" reason)))))
```

The command reads current buffer state, obtains the clock, persists, and reports to the user. Those are legitimate shell responsibilities.

---

## Define Purity Pragmatically

A pure-ish Elisp function:

- depends only on explicit arguments;
- does not mutate Emacs, external systems, or caller-owned objects;
- returns its decision as a value;
- produces the same observable result for the same inputs.

Allocation, local mutation of a fresh value, and signaling a documented condition can still fit in a deterministic core. Name the contract rather than claiming mathematical purity.

```elisp
(defun invoice-normalize-tags (tags)
  "Return normalized TAGS without changing the input list."
  (sort (delete-dups (copy-sequence tags)) #'string-lessp))
```

Here `sort` and `delete-dups` may destructively rearrange their input, so the function copies before using them. The mutation cannot affect the caller.

```elisp
;; ✘ WRONG: mutates caller-owned list structure
(defun invoice-normalize-tags (tags)
  (sort (delete-dups tags) #'string-lessp))
```

---

## Pass Dependencies as Arguments

Free variables and current editor state behave like invisible parameters. Make ordinary dependencies visible:

```elisp
;; ✓ CORRECT
(defun invoice-late-fee (invoice policy today)
  "Return the late fee for INVOICE under POLICY at TODAY."
  (if (invoice-overdue-p invoice today)
      (funcall policy invoice)
    0))

;; ✘ WRONG: hidden clock and policy
(defun invoice-late-fee (invoice)
  (if (invoice-overdue-p invoice (current-time))
      (funcall invoice-late-fee-policy invoice)
    0))
```

Passing a function is often enough for a repository or policy boundary:

```elisp
(require 'seq)

(defun invoice-find-overdue (ids load-invoice today)
  "Return overdue invoices among IDS loaded by LOAD-INVOICE."
  (seq-filter
   (lambda (invoice) (invoice-overdue-p invoice today))
   (delq nil (mapcar load-invoice ids))))
```

The shell can pass `#'invoice-repository-load`; tests can pass an in-memory function.

Do not build a dependency-injection framework around this. Ordinary arguments, closures, and small records cover most cases.

---

## Keep Interactive Commands Thin

The `interactive` form belongs on commands. Reusable logic remains callable without simulating a command loop:

```elisp
(defun invoice-format-summary (invoice)
  "Return a one-line summary of INVOICE."
  (format "%s  %s  %s"
          (invoice-id invoice)
          (invoice-amount invoice)
          (invoice-status invoice)))

;;;###autoload
(defun invoice-show-summary (invoice-id)
  "Show a summary for INVOICE-ID."
  (interactive (list (read-string "Invoice ID: ")))
  (let ((invoice (invoice-repository-load invoice-id)))
    (unless invoice
      (user-error "No invoice named %s" invoice-id))
    (message "%s" (invoice-format-summary invoice))))
```

The command parses user input and presents output. Formatting is an ordinary function.

Avoid functions that change behavior through `called-interactively-p` deep in the core. If programmatic and interactive contracts differ, use a command wrapper.

---

## Return Effects as Data When Coordination Grows

A workflow can return a small plan instead of executing every effect inline:

```elisp
(defun invoice-close-plan (invoice)
  "Return the effects needed to close INVOICE."
  (if (eq (invoice-status invoice) 'paid)
      (list (list 'archive (invoice-id invoice))
            (list 'notify (invoice-id invoice)))
    (list (list 'reject (invoice-id invoice) 'unpaid))))

(defun invoice-apply-effect (effect)
  "Apply one invoice EFFECT."
  (pcase effect
    (`(archive ,id) (invoice-repository-archive id))
    (`(notify ,id) (invoice-ui-notify-closed id))
    (`(reject ,id ,reason)
     (user-error "Cannot close %s: %s" id reason))))
```

This pattern improves testability when decisions and effects are meaningfully separate. Do not encode every trivial function call as command data.

External effects are not transactional merely because they are represented first. Buffer rollback cannot unsend a process request or undo a file write.

---

## Prefer Functions to Macros

Use a function when arguments can be evaluated normally and a return value is enough.

```elisp
;; ✓ CORRECT
(defun invoice-double (amount)
  "Return twice AMOUNT."
  (* amount 2))

;; ✘ WRONG: no control over evaluation is needed
(defmacro invoice-double (amount)
  `(* ,amount 2))
```

A macro is justified when it must:

- receive unevaluated forms;
- introduce a binding construct;
- control whether or how often forms are evaluated;
- define another top-level construct in a tool-visible way.

Keep necessary macros thin:

```elisp
(defmacro invoice-with-timing (&rest body)
  "Run BODY and record its duration."
  (declare (indent 0) (debug t))
  (let ((started (make-symbol "started")))
    `(let ((,started (current-time)))
       (unwind-protect
           (progn ,@body)
         (invoice-record-duration
          (float-time (time-subtract (current-time) ,started)))))))
```

This macro introduces control flow and evaluates each body form once. Recording policy remains in the ordinary `invoice-record-duration` function.

For every nontrivial macro:

- generate private bindings with `make-symbol` or another hygienic technique;
- evaluate caller forms exactly as documented;
- declare indentation and Edebug behavior;
- move parsing, validation, and business logic into functions;
- test both expansion shape and runtime behavior.

Never construct public definition names invisibly inside a macro. Tools should be able to locate definitions from the call site.

---

## Compose Without Pipeline Theater

Higher-order functions and threading macros can make data flow clear:

```elisp
(require 'seq)
(require 'subr-x)

(defun invoice-visible-tags (tags)
  "Return normalized public TAGS."
  (thread-last tags
               (seq-filter #'stringp)
               (seq-map #'string-trim)
               (seq-remove #'string-empty-p)
               delete-dups))
```

Use this style when the intermediate data remains easy to name and each stage is meaningful. A local `let*` is better when stages need explanation or several values travel together.

```elisp
(defun invoice-visible-tags (tags)
  "Return normalized public TAGS."
  (let* ((strings (seq-filter #'stringp tags))
         (trimmed (seq-map #'string-trim strings))
         (nonempty (seq-remove #'string-empty-p trimmed)))
    (delete-dups nonempty)))
```

Do not force all Elisp into point-free or closure-heavy style. Allocation and generic dispatch matter in hot paths; [quality.md](quality.md) owns measurement guidance.

---

## Organize Dependencies Toward the Domain

```text
invoice-domain.el       structs, predicates, transformations, invariants
invoice-repository.el   files, SQLite, process or network conversion
invoice-service.el      application workflows and effect plans
invoice-ui.el           commands, buffers, completion, keymaps
invoice.el              package facade, options, mode setup
```

The domain does not require repository or UI modules. Adapters depend inward on domain contracts. The facade wires them together.

File and feature details are in [modules.md](modules.md). Buffer, hook, timer, and process boundaries are in [state-effects.md](state-effects.md).

---

## Summary

- Read and apply effects at adapters
- Pass clocks, policies, repositories, and data explicitly
- Return decisions as values before applying complex effects
- Keep interactive commands thin
- Mutate only fresh local values inside the core
- Use functions unless evaluation control requires a macro
- Keep macros hygienic, declared, and thin
- Choose pipelines or `let*` for clarity, not ideology
- Use ordinary arguments and closures before dependency frameworks
- Let dependencies point toward domain modules

---

## Related

- [domain-types.md](domain-types.md) - Canonical values at boundaries
- [state-effects.md](state-effects.md) - Effect-scoping primitives
- [modules.md](modules.md) - Feature-oriented package layout
- [test.md](test.md) - Testing cores and shells
- [quality.md](quality.md) - Benchmarking transformations and loops

## References

- [Emacs Lisp Elements: Side effect and return value](https://protesilaos.com/emacs/emacs-lisp-elements#h:side-effect-and-return-value) - Effects in the Emacs runtime
- [Emacs Lisp Style Guide: Macros](https://github.com/bbatsov/emacs-lisp-style-guide#macros) - Functions before macros
- [GNU Emacs Lisp Manual: Defining Functions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Defining-Functions.html) - Function definitions and argument contracts
- [Functional Core, Imperative Shell](https://www.destroyallsoftware.com/screencasts/catalog/functional-core-imperative-shell) - Architectural pattern
