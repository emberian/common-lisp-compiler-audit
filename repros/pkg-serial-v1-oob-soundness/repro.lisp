; Reproducer: Out-of-bounds (svref arr -1) at (safety 0) in ser-decode-from-stream
; (serialize-raw.lisp:1535-1539, 1575) without trust tags (:ttags nil).
;
; V1 header (#xAC #x12 #x0B #xC7) with size/idx = 0 sets:
;   arr-size  = 0
;   final-obj = (- arr-size 1) = -1
;   free      = 0 (after 7 empty atom/cons sections)
; Passing (= free arr-size) (0 = 0), line 1575 executes (svref arr -1) at (safety 0)
; on a 0-element stack-allocated simple-vector.
;
; On CCL arm64, (svref arr -1) reads the raw vector header word and returns
; #<BOGUS object @ #xBE> into pure :logic-mode ACL2:
;   - All five ACL2 type predicates (consp, acl2-numberp, symbolp, characterp, stringp)
;     evaluate to NIL (falsifying ACL2's universe partition).
;   - Calling guard-verified :logic-mode (lexorder val val) (:guard t, theorem (lexorder x x))
;     aborts with a raw Lisp error in SYMBOL-NAME.

(in-package "ACL2")

(defun write-byte-list (bs ch state)
  (declare (xargs :mode :program :stobjs state))
  (if (endp bs)
      state
    (let ((state (write-byte$ (car bs) ch state)))
      (write-byte-list (cdr bs) ch state))))

; 1. Write 13-byte V1 size=0 payload at top level (zero trust tags):
(mv-let (ch state)
  (open-output-channel "v1-zero.sao" :byte state)
  (let* ((bytes '(#xAC #x12 #x0B #xC7
                  0
                  0 0 0 0 0 0 0
                  #xAC #x12 #x0B #xC7))
         (state (write-byte-list bytes ch state)))
    (close-output-channel ch state)))

; 2. Read back in pure :logic mode via serialize-read (zero trust tags) and inspect predicates
;    + call guard-verified :logic-mode (lexorder val val):
(mv-let (val state)
  (serialize-read "v1-zero.sao")
  (let ((in-universe (or (consp val)
                         (acl2-numberp val)
                         (symbolp val)
                         (characterp val)
                         (stringp val))))
    (prog2$
     (cw "@V1-SINGLE-HOST host=~x0 in-acl2-universe=~x1 consp=~x2 nump=~x3 symp=~x4 charp=~x5 strp=~x6 ttags=~x7~%"
         (@ host-lisp)
         in-universe
         (consp val)
         (acl2-numberp val)
         (symbolp val)
         (characterp val)
         (stringp val)
         (global-val 'ttags-seen (w state)))
     (prog2$
      (cw "@V1-CALLING-LEXORDER~%")
      (prog2$
       (lexorder val val)
       (prog2$
        (cw "@V1-LEXORDER-SURVIVED host=~x0~%" (@ host-lisp))
        state))))))
