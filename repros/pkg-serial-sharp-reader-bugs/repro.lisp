; Reproducer: Sharp-macro reader bugs in sharp-u-read, sharp-f-read, and sharp-bang-read
; (acl2-fns.lisp:1440-1571) on both SBCL and CCL (:ttags nil).

(in-package "ACL2")

(defun read-str-case (str mode state)
  (declare (xargs :mode :program :stobjs state))
  (mv-let (och state)
    (open-output-channel "sharp_in.lsp" :character state)
    (let* ((state (princ$ str och state))
           (state (close-output-channel och state)))
      (mv-let (ich state)
        (open-input-channel "sharp_in.lsp" :object state)
        (mv-let (eof val state)
          (read-object-with-case ich mode state)
          (declare (ignore eof))
          (let ((state (close-input-channel ich state)))
            (mv val state)))))))

; 1. #u|42 NOT A NUMERAL| and #u|X10 NOT HEX| silently ignore trailing garbage:
(mv-let (v1 state) (read-str-case "#u|42 NOT A NUMERAL|" :upcase state)
  (mv-let (v2 state) (read-str-case "#u|X10 NOT HEX|" :upcase state)
    ; 2. (#f), (#f-), (#f.), (#fx) silently read as (0):
    (mv-let (vf state) (read-str-case "((#f) (#f-) (#f.) (#fx))" :upcase state)
      (prog2$
       (cw "@SHARP-SILENT host=~x0 u-dec-garbage=~x1 u-hex-garbage=~x2 empty-sharp-f=~x3~%"
           (@ host-lisp) v1 v2 vf)
       state))))
