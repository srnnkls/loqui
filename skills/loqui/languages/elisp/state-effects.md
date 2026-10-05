---
paths: "**/*.el, **/Cask, **/Eask"
---

# Emacs Lisp State and Effects

Buffers, point, dynamic editor state, hooks, timers, processes, and explicit cleanup boundaries.

## Treat the Editor as Infrastructure

These values are ambient inputs or observable effects:

- current buffer, point, mark, narrowing, and selected window;
- match data from searches and regular expressions;
- buffer-local, window-local, frame-local, and global variables;
- buffer text, text properties, overlays, and markers;
- hooks, advice, modes, keymaps, and customization state;
- minibuffer input, echo-area messages, windows, and faces;
- files, subprocesses, network requests, timers, and sentinels.

Domain functions should not read these implicitly. Adapters obtain explicit values, call the domain, then apply returned decisions.

```elisp
(defun invoice-line-status (line today)
  "Return the status encoded by LINE at TODAY."
  (let ((invoice (invoice-parse-line line)))
    (if (invoice-overdue-p invoice today)
        'overdue
      'current)))

(defun invoice-status-at-point ()
  "Return the invoice status for the current line."
  (invoice-line-status
   (buffer-substring-no-properties
    (line-beginning-position)
    (line-end-position))
   (current-time)))
```

The parser and predicate are reusable. Only the adapter depends on point, current buffer, text properties, and the clock.

---

## Bind the Buffer Explicitly

A function that works on a buffer should accept the buffer or make current-buffer dependence part of a narrow private contract.

```elisp
(defun invoice-buffer-ids (buffer)
  "Return invoice IDs parsed from BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (save-match-data
        (goto-char (point-min))
        (let (ids)
          (while (re-search-forward invoice-id-regexp nil t)
            (push (match-string-no-properties 1) ids))
          (nreverse ids))))))
```

`with-current-buffer` restores the caller's current buffer, `save-excursion` restores point, and `save-match-data` preserves the caller's regexp state.

```elisp
;; ✘ WRONG: hidden current-buffer input
(defun invoice-buffer-ids ()
  (goto-char (point-min))
  ...)
```

An interactive command can pass `(current-buffer)` deliberately.

### Temporary buffers have bounded lifetimes

```elisp
(defun invoice-parse-response (text)
  "Parse invoice response TEXT."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (invoice-parser-read-current-buffer)))
```

Do not return the temporary buffer, a marker into it, or an overlay owned by it. Return parsed data.

---

## Scope Point, Narrowing, and Match Data Separately

Each save form protects a different ambient state.

### Preserve point with `save-excursion`

```elisp
(save-excursion
  (goto-char (point-min))
  (invoice-scan-current-buffer))
```

This does not undo inserted or deleted text.

### Preserve narrowing with `save-restriction`

```elisp
(save-restriction
  (widen)
  (narrow-to-region start end)
  (invoice-process-visible-region))
```

Narrowing is buffer state. A helper should not accidentally leave its caller narrowed or widened.

### Preserve regular-expression match data

Many search and string functions overwrite global match data:

```elisp
(defun invoice-normalize-id (text)
  "Return the first normalized invoice ID in TEXT."
  (save-match-data
    (when (string-match invoice-id-regexp text)
      (upcase (match-string 1 text)))))
```

Use `save-match-data` when a function's contract does not expose match state. Do not rely on match data surviving unrelated calls.

### Use markers when positions must track edits

An integer position does not move as text changes. A marker does:

```elisp
(let ((end-marker (copy-marker end)))
  (unwind-protect
      (invoice-rewrite-region start end-marker)
    (set-marker end-marker nil)))
```

Detach temporary markers in cleanup so they stop tracking buffer changes.

---

## Make Buffer Transactions Explicit

`atomic-change-group` rolls back buffer text changes in its group if the body exits abnormally:

```elisp
(defun invoice-rewrite-current-buffer (invoices)
  "Replace the current buffer with rendered INVOICES atomically."
  (atomic-change-group
    (erase-buffer)
    (insert (invoice-render-all invoices))
    (invoice-validate-current-buffer)))
```

Its boundary is buffer changes. It does not roll back:

- file writes;
- messages or minibuffer interaction;
- process requests;
- hook side effects outside the change group;
- global variable mutation;
- changes in unrelated buffers.

Compute and validate as much as possible before entering the change group. Keep external effects outside it.

For edits that should not affect modification hooks, undo data, or buffer modified state, use the precise low-level tool only after understanding its contract. `with-silent-modifications` is not a generic performance wrapper.

---

## Restore Resources with `unwind-protect`

Use `unwind-protect` when cleanup must run after normal return, error, or quit:

```elisp
(defun invoice-with-lock (lock-file function)
  "Call FUNCTION while holding LOCK-FILE."
  (invoice-lock-acquire lock-file)
  (unwind-protect
      (funcall function)
    (invoice-lock-release lock-file)))
```

Acquire before entering the protected body and make cleanup tolerate partial state only when acquisition can partially succeed.

Do not suppress the original condition during cleanup. If cleanup can fail, decide which failure the API promises and preserve enough context to diagnose both.

Built-in save macros are preferable when they exactly model the resource. Use `save-excursion`, `save-restriction`, and `save-match-data` instead of open-coded restoration.

---

## Localize Hooks and Advice

Hooks are global extension protocols unless added buffer-locally:

```elisp
(defun invoice-ui-enable ()
  "Enable invoice behavior in the current buffer."
  (add-hook 'after-save-hook #'invoice-ui--after-save nil t))

(defun invoice-ui-disable ()
  "Disable invoice behavior in the current buffer."
  (remove-hook 'after-save-hook #'invoice-ui--after-save t))
```

The final `t` makes the hook buffer-local. Mode teardown must remove or naturally discard everything setup created.

Use named hook functions rather than anonymous lambdas when callers may need to remove, inspect, or customize them.

Avoid advising another package's functions as a default integration technique. Prefer, in order:

1. a documented function or variable;
2. a documented hook;
3. a package-specific extension point;
4. a narrowly scoped advice with a compatibility reason and removal path.

Advice changes behavior outside the advised file and can compose unpredictably with other packages. Test the exact integration and detect upstream API changes.

Simply loading a library should define behavior, not enable it. Activation belongs in a command, mode, or explicit setup function.

---

## Keep UI Effects at Commands

Minibuffer reads, keymaps, selected windows, and messages belong at user-facing boundaries:

```elisp
;;;###autoload
(defun invoice-open (invoice-id)
  "Open the invoice named INVOICE-ID."
  (interactive (list (read-string "Invoice ID: ")))
  (let ((invoice (invoice-repository-load invoice-id)))
    (unless invoice
      (user-error "No invoice named %s" invoice-id))
    (pop-to-buffer (invoice-ui-render-buffer invoice))))
```

The repository function should not call `message` on failure. The renderer can return a buffer without deciding where to display it. The command owns presentation.

Avoid changing the selected window merely to edit another buffer; use `with-current-buffer`. Use window selection only when selection is part of the feature.

---

## Design Timers and Callbacks for Lifetime

A timer runs later, after the creating function has returned. Capture explicit stable values and re-check live resources:

```elisp
(defun invoice-schedule-refresh (buffer delay)
  "Refresh BUFFER after DELAY seconds."
  (run-at-time
   delay nil
   (lambda (target)
     (when (buffer-live-p target)
       (with-current-buffer target
         (invoice-ui-refresh))))
   buffer))
```

Store repeating timers when they must be canceled:

```elisp
(defvar-local invoice-ui--refresh-timer nil)

(defun invoice-ui-stop-refresh ()
  "Cancel refresh work in the current buffer."
  (when (timerp invoice-ui--refresh-timer)
    (cancel-timer invoice-ui--refresh-timer)
    (setq invoice-ui--refresh-timer nil)))
```

A mode that starts a timer owns stopping it. Tests must not leave timers active.

Do not capture point as an integer and assume it still identifies the same text later. Capture a marker when tracking edits is required, then detach it when done.

---

## Treat Process Filters and Sentinels as Effectful Adapters

Processes deliver output in chunks. Filters cannot assume one callback equals one line or one complete message.

```elisp
(defun invoice-process-start (buffer command)
  "Start invoice COMMAND and stream its output to BUFFER."
  (make-process
   :name "invoice-sync"
   :buffer buffer
   :command command
   :noquery t
   :filter #'invoice-process--filter
   :sentinel #'invoice-process--sentinel))

(defun invoice-process--filter (process chunk)
  "Accept CHUNK from PROCESS."
  (when-let* ((buffer (process-buffer process))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (invoice-process--accept-chunk process chunk))))
```

Keep per-process framing state on the process or in a dedicated record. Parse complete messages into domain values before calling service logic.

Sentinels can run after a user killed the destination buffer or canceled the operation:

```elisp
(defun invoice-process--sentinel (process event)
  "Handle PROCESS transition described by EVENT."
  (when (memq (process-status process) '(exit signal))
    (let ((buffer (process-buffer process)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (invoice-process--finish process event))))))
```

Check current process status; sentinel event strings are presentation details, not a stable domain protocol.

Define cancellation and teardown:

- delete or interrupt a live process;
- cancel timers;
- detach markers;
- remove hooks and advice;
- invalidate callbacks from superseded requests;
- tolerate buffers disappearing.

Never block the command loop waiting for a process when asynchronous APIs can preserve responsiveness.

---

## Use Threads for the Problem They Actually Solve

Emacs Lisp threads are cooperative at the Lisp level, and only one thread executes Lisp at a time. They can help coordinate work around blocking operations that release the interpreter lock, but they do not turn editor state into freely parallel mutable data.

Prefer processes, asynchronous process filters, timers, and callbacks for typical package I/O. If using `make-thread`:

- pass immutable or explicitly owned data;
- do not assume buffer operations are race-free;
- define cancellation and result delivery;
- propagate conditions to an observable owner;
- test shutdown and package unload.

Do not move code to a thread merely to hide a blocking design.

---

## Summary

- Treat editor and external state as infrastructure
- Accept a buffer explicitly or confine current-buffer assumptions to adapters
- Scope point, narrowing, and match data with their dedicated forms
- Use markers only when positions must follow edits, then detach them
- Use `atomic-change-group` only for buffer-change rollback
- Guarantee cleanup with `unwind-protect`
- Add and remove hooks at the same ownership boundary
- Prefer package APIs and hooks over advice
- Keep minibuffer and window decisions in commands
- Store and cancel owned timers
- Parse process chunks incrementally and re-check live resources
- Define cancellation and teardown for every asynchronous workflow
- Do not block redisplay or assume Lisp threads provide parallel editor mutation

---

## Related

- [composition.md](composition.md) - Functional core and shell design
- [modules.md](modules.md) - Mode activation and load-time behavior
- [errors.md](errors.md) - Cleanup and condition propagation
- [test.md](test.md) - Isolating stateful behavior
- [quality.md](quality.md) - Profiling buffer and process work

## References

- [GNU Emacs Lisp Manual: Buffers](https://www.gnu.org/software/emacs/manual/html_node/elisp/Buffers.html) - Buffer state and operations
- [GNU Emacs Lisp Manual: Excursions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Excursions.html) - Point and current-buffer restoration
- [GNU Emacs Lisp Manual: Atomic Changes](https://www.gnu.org/software/emacs/manual/html_node/elisp/Atomic-Changes.html) - Buffer change groups
- [GNU Emacs Lisp Manual: Processes](https://www.gnu.org/software/emacs/manual/html_node/elisp/Processes.html) - Filters, sentinels, and process lifecycle
- [GNU Emacs Lisp Manual: Timers](https://www.gnu.org/software/emacs/manual/html_node/elisp/Timers.html) - Deferred callbacks
- [GNU Emacs Lisp Manual: Threads](https://www.gnu.org/software/emacs/manual/html_node/elisp/Threads.html) - Cooperative Lisp threads
