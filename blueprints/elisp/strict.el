;;; strict.el --- Loqui strictness for Eask packages  -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded from a package's Eask file:
;;
;;   (load (expand-file-name ".loqui/elisp/strict.el"
;;                           (file-name-directory load-file-name))
;;         nil t)
;;
;; Byte-compiler warnings fail the build, and `loqui-eask-command' builds
;; script commands over Eask file specs.

;;; Code:

(add-hook 'eask-before-compile-hook
          (lambda ()
            (setq byte-compile-error-on-warn t)))

;; The experimental verb check reads every verb in a docstring rather than
;; the first word the imperative-mood convention covers; Emacs 31 disables it.
(setq checkdoc-verb-check-experimental-flag nil)

(defun loqui-eask-command (command specs)
  "Return COMMAND followed by the shell-quoted files matching SPECS.
Signal an error when SPECS match no file."
  (let* ((default-directory (file-name-directory load-file-name))
         (files (eask-expand-file-specs specs)))
    (unless files
      (error "No file matches %S under %s" specs default-directory))
    (mapconcat #'identity
               (cons command (mapcar #'shell-quote-argument files))
               " ")))

;;; strict.el ends here
