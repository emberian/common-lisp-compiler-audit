(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; Proof-builder `:apply-linear` (`:al`, proof-builder-b.lisp:3204-3349) builds
; `assumptions` by unioning top-level `hyps` with `(governors conc current-addr)`
; (line 3226) and relieves the `:linear` rule's hypotheses against those
; branch-local governors (lines 3244, 3284, 3322). However, instead of
; restricting the derived linear conclusion to `current-addr`, lines 3326-3332
; append `(sublis-var unify-subst lemma-concl)` directly to the top-level goal
; `:hyps`!
;
; Diving into the unreachable THEN branch of `(if (< (trig) 0) (equal (trig) 0) nil)`
; where `(trig) = 0` promotes the false branch governor `(< (trig) 0)` into a
; top-level hypothesis, discharging the false theorem by contradiction in `:hyps`
; and proving `nil-proved`.

(defun trig ()
  (declare (xargs :guard t))
  0)

(defthm trig-lin
  (implies (< (trig) 0)
           (< (trig) 0))
  :rule-classes ((:linear :trigger-terms ((trig)))))

(in-theory (disable trig
                    (:executable-counterpart trig)
                    (:type-prescription trig)))

(defthm false-thm
  (if (< (trig) 0) (equal (trig) 0) nil)
  :rule-classes nil
  :instructions ((:dv 2)
                 (:dv 1)
                 (:apply-linear trig-lin)
                 :top
                 (:in-theory (enable (:executable-counterpart trig)))
                 :s))

(in-theory (enable (:executable-counterpart trig)))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use false-thm)))

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
