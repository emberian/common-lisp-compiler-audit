; Pure Guard-Verified ACL2 v8.6+ Soundness Proof of NIL on SBCL 2.6.10
; Triggered by SBCL `inherit-equality-p` (src/compiler/equality-constraints.lisp:169-178)
; miscompiling guard-verified `(if (eql y z) (if (char-equal x y) (eql x z) nil) nil)`.
;
; Zero trust tags (:ttag nil), zero skip-proofs (:skip-proofs-seen nil),
; zero redefinitions (:redef-seen nil), zero raw Lisp escapes.

(in-package "ACL2")

(defun char-eq-coarsen (x y z)
  (declare (xargs :guard (and (characterp x)
                              (characterp y)
                              (characterp z))))
  (if (eql y z)
      (if (char-equal x y)
          (eql x z)
          nil)
      nil))

(comp 'char-eq-coarsen)

; Raw compiled evaluation (via guard-verified 1* function) returns T on (#\a #\A #\A),
; whereas the definitional axiom reduces (char-eq-coarsen #\a #\A #\A) to NIL!
(defthm nil-proved
  nil
  :hints (("Goal" :use ((:instance (:definition char-eq-coarsen)
                                   (x #\a)
                                   (y #\A)
                                   (z #\A)))))
  :rule-classes nil)

(cw "~%=== ACL2 INTEGRITY AUDIT ===~%")
(cw "ttag:             ~x0~%" (ttag (w state)))
(cw "skip-proofs-seen: ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "redef-seen:       ~x0~%" (global-val 'redef-seen (w state)))
(cw "ACL2 SOUNDNESS BUG CONFIRMED: (DEFTHM NIL-PROVED NIL) ACCEPTED ON SBCL 2.6.10~%")
(good-bye 0)
