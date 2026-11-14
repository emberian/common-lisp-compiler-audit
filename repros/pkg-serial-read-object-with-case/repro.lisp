; Reproducer: read-object-with-case completely ignores :downcase and :invert modes
; due to double hardcoding of :preserve in axioms.lisp:20609 and axioms.lisp:18846-18853.
;
; Per :DOC io (doc.lisp:63543-63552) and read-object-with-case's guard:
;   mode in (:upcase :downcase :preserve :invert) follows ANSI CL readtable-case:
;     - :downcase on "FOO bar" must produce (|foo| |bar|)
;     - :invert   on "FOO bar Mixed" must produce (|foo| BAR |Mixed|)
; Instead, axioms.lisp:20609 calls (set-acl2-readtable-case :preserve) regardless of mode,
; AND set-acl2-readtable-case (axioms.lisp:18846-18853) declares `(ignore mode)` and expands
; to `(setf (readtable-case *acl2-readtable*) :preserve)`.

(in-package "ACL2")

(defun test-read-case (mode state)
  (declare (xargs :mode :program :stobjs state))
  (mv-let (och state)
    (open-output-channel "case_input.lsp" :character state)
    (let* ((state (princ$ "(FOO bar Mixed)" och state))
           (state (close-output-channel och state)))
      (mv-let (ich state)
        (open-input-channel "case_input.lsp" :object state)
        (mv-let (eof val state)
          (read-object-with-case ich mode state)
          (declare (ignore eof))
          (let ((state (close-input-channel ich state)))
            (mv val state)))))))

(mv-let (v-up state) (test-read-case :upcase state)
  (mv-let (v-down state) (test-read-case :downcase state)
    (mv-let (v-pres state) (test-read-case :preserve state)
      (mv-let (v-inv state) (test-read-case :invert state)
        (prog2$
         (cw "@READ-CASE host=~x0~%  :upcase   got=~x1 expected=(FOO BAR MIXED)~%  :downcase got=~x2 expected=(|foo| |bar| |mixed|) [BUG: got :preserve!]~%  :preserve got=~x3 expected=(FOO |bar| |Mixed|)~%  :invert   got=~x4 expected=(|foo| BAR |Mixed|)   [BUG: got :preserve!]~%"
             (@ host-lisp) v-up v-down v-pres v-inv)
         state)))))
