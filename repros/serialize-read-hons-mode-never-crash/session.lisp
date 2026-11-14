; SCR-R1: serialize-read with :hons-mode :never aborts from raw Lisp on a
; valid .sao file produced by serialize-write because ser-decode-and-restore-fals
; (serialize-raw.lisp:1403-1414) places (ser-decode-nat stream) for COUNT inside
; (unless (eq hons-mode :never) ...), desynchronizing the (INDEX, COUNT) stream
; and terminating early whenever COUNT = 0 (e.g., (make-fast-alist '(nil))).

(serialize-write "sample.sao" (make-fast-alist '(nil)))
(mv-let (obj state)
  (serialize-read "sample.sao" :hons-mode :smart)
  (prog2$ (cw "@SMART-READ ~x0~%" obj)
          state))
(mv-let (obj state)
  (serialize-read "sample.sao" :hons-mode :never)
  (prog2$ (cw "@NEVER-READ ~x0~%" obj)
          state))
(cw "@END~%")
:q
