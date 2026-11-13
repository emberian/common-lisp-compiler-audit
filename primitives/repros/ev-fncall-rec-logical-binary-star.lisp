; saved_acl2 < ev-fncall-rec-logical-binary-star.lisp
; ev-fncall-rec-logical's BINARY-* case tests only (acl2-numberp y) before
; calling the host's *.  With a non-number x and a number y it signals a host
; type error, with guard checking off (logical value: 0) and with it on (should
; be a guard violation).  Swapped arguments behave correctly.  This is the
; logical evaluator itself (normally bypassed by *ev-shortcut-okp*), not
; binary-*: the *1* function returns 0.
(set-guard-checking :none)
(binary-* #\a 0)                                             ; 0, correct
:q
(defun show (tag args gc-off)
  (format t "~&@R ~a ~s~%" tag
          (multiple-value-list
           (ignore-errors (ev-fncall-rec-logical 'binary-* args nil (w *the-live-state*)
                                                 nil 1000 nil gc-off nil nil nil nil)))))
(show "x=#\\a y=0 gc-off" (list #\a 0) t)                    ; host TYPE-ERROR, want (NIL 0 NIL)
(show "x=0 y=#\\a gc-off" (list 0 #\a) t)                    ; (NIL 0 NIL), correct
(f-put-global 'guard-checking-on t *the-live-state*)
(show "x=#\\a y=0 gc-on " (list #\a 0) nil)                  ; host TYPE-ERROR, want guard violation
