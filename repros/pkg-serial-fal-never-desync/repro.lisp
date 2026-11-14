; Reproducer: Fast-alist deserialization bugs in serialize-raw.lisp and hons-raw.lisp
; (:ttags nil, both SBCL and CCL):
;
; Bug A (serialize-raw.lisp:1406-1414):
;   Under :hons-mode :never (and #Y reader macro), ser-decode-and-restore-fals skips
;   reading `count`, leaving the next loop iteration's `(setq index (ser-decode-nat stream))`
;   to consume `count` as `index`. Any VALID fast alist with 0 pairs in its backing hash
;   table — e.g. `(make-fast-alist '(only-atom-1 only-atom-2))` — writes `count = 0`,
;   prematurely terminating the FAL loop so the real `0` terminator desynchronizes the
;   trailer magic check: `Invalid serialized object, magic number incorrect: 0 AC 12 B`.
;
; Bug B (hons-raw.lisp:3236-3239):
;   Any VALID fast alist whose spine is normed — e.g. `(make-fast-alist (hons-copy '((a . 1))))`
;   (or any fast alist read twice under `:hons-mode :always`) — reconstructs the identical EQ
;   normed cons spine and triggers `(hl-alist-stolen-warning 'hl-hspace-restore-fal-for-serialize)`,
;   entering the raw Common Lisp debugger (`BREAK$-RAW`) under default `slow-alist-action`!
;
; Bug C (hons-raw.lisp:3197-3240):
;   `ser-decode-and-restore-fals` only checks `0 < index < max` without checking `(consp alist)`
;   or `(typep count 'fixnum)`, allowing untrusted `.sao` files (:ttags nil) to bind atoms (`T`, `42`)
;   in `faltable` or set `(hl-falslot-key slot) = NIL` with non-nil `val = #<HASH-TABLE>`.

(in-package "ACL2")

; Bug A1: Valid (make-fast-alist '(only-atom-1 only-atom-2)) via serialize-write + :hons-mode :never
(make-event
 (let* ((fal (make-fast-alist '(only-atom-1 only-atom-2)))
        (state (serialize-write "atom_fal.sao" fal)))
   (mv-let (val-smart state)
     (serialize-read "atom_fal.sao" :hons-mode :smart)
     (prog2$
      (cw "@FAL-SMART-OK host=~x0 val=~x1~%" (@ host-lisp) val-smart)
      (value '(defun fal-smart-witness () t))))))

; Now read the exact same valid .sao file with :hons-mode :never -> raw Lisp error!
(serialize-read "atom_fal.sao" :hons-mode :never)
