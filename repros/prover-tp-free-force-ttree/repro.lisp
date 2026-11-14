(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; type-set-relieve-hyps (type-set-b.lisp:8654) and type-set-relieve-hyps-free
; (type-set-b.lisp:8428) overwrite the accumulated tag-tree `ttree` with
; `ttree0` (NIL) when a free-variable hypothesis match fails subsequent
; hypotheses and backtracks to a later free-variable match on `type-alist`.
;
; As a result, all forced `'assumption` records accumulated from hypotheses
; preceding the free-variable hypothesis are silently wiped from `ttree`,
; proving a false theorem with zero forcing rounds and immediately deriving NIL.

(defun h1 (x)
  (declare (xargs :guard t))
  (equal x 99))

(defun p (x y)
  (declare (xargs :guard t))
  (and (integerp x) (integerp y)))

(defun q (y)
  (declare (xargs :guard t))
  (equal y 2))

(defun foo (x)
  (declare (xargs :guard t))
  (not (h1 x)))

; Valid theorem: when (h1 x) holds (i.e. x = 99), (foo x) is NIL.
(defthm foo-tp-false-when-h1
  (implies (and (force (h1 x))
                (p x y)
                (q y))
           (not (foo x)))
  :rule-classes ((:type-prescription :typed-term (foo x))))

(in-theory (disable h1 p q foo
                    (:executable-counterpart h1)
                    (:executable-counterpart p)
                    (:executable-counterpart q)
                    (:executable-counterpart foo)
                    (:type-prescription h1)
                    (:type-prescription p)
                    (:type-prescription q)
                    (:type-prescription foo)))

; At x = 0: (p 0 2) = T, (p 0 1) = T, (not (q 1)) = T, (q 2) = T,
; while (foo 0) = (not (equal 0 99)) = T, so (not (foo 0)) is NIL!
; Because (p x 1) appears closer to the head of type-alist than (p x 2)
; (assumptions are consed in order), Match #1 (y -> 1) fails on (q 1) and
; returns ttree0 = NIL, clobbering the forced (h1 x) assumption in `ttree`
; before Match #2 (y -> 2) succeeds!
(defthm unsound-tp-free-force
  (implies (and (p x 2)
                (p x 1)
                (not (q 1))
                (q 2))
           (not (foo x)))
  :rule-classes nil)

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance unsound-tp-free-force (x 0)))
                  :in-theory (enable h1 p q foo
                                     (:executable-counterpart h1)
                                     (:executable-counterpart p)
                                     (:executable-counterpart q)
                                     (:executable-counterpart foo)))))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'ttags-seen (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (equal (formula 'nil-proved t (w state)) ''nil)))

(mv-let (erp val state)
  (ld '((cw "@SOUNDNESS nil=~x0 ttag=~x1 seen=~x2 skip=~x3 redef=~x4~%"
            (formula 'nil-proved t (w state))
            (ttag (w state))
            (global-val 'ttags-seen (w state))
            (global-val 'skip-proofs-seen (w state))
            (global-val 'redef-seen (w state)))))
  (declare (ignore erp val))
  state)
(quit)
