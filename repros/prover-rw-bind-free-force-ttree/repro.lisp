(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; relieve-hyps1-unify-subst-lst (rewrite.lisp:18395) passes
; `:ttree (accumulate-rw-cache t ttree1 ttree0)` instead of
; `:ttree (accumulate-rw-cache t ttree1 ttree)` when the first binding alist
; returned by `bind-free` fails a subsequent hypothesis and backtracks to
; `(cdr unify-subst-lst)` (out of sync with relieve-hyps1-free-1 at
; rewrite.lisp:18678).
;
; Consequently, every forced `'assumption` (or `case-split`) from hypotheses
; preceding `bind-free` in a `:rewrite`, `:linear`, or `:meta` rule is wiped
; from `ttree`, proving false theorems with zero forcing rounds.

(defun h1 (x)
  (declare (xargs :guard t))
  (equal x 99))

(defun foo (x)
  (declare (xargs :guard t))
  (not (h1 x)))

; Valid theorem: when (h1 x) holds (x = 99), (foo x) = NIL.
(defthm foo-rw-false-via-bind-free
  (implies (and (force (h1 x))
                (bind-free '(((y . '1)) ((y . '2))) (y))
                (equal y 2))
           (equal (foo x) nil)))

(in-theory (disable h1 foo
                    (:executable-counterpart h1)
                    (:executable-counterpart foo)
                    (:type-prescription h1)
                    (:type-prescription foo)))

; Candidate alist #1 ((y . '1)) fails (equal y 2); relieve-hyps1-unify-subst-lst
; recurses on (((y . '2))) with ttree0 = NIL, losing the forced (h1 x) assumption!
(defthm unsound-bind-free-lemma
  (equal (foo x) nil)
  :rule-classes nil)

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance unsound-bind-free-lemma (x 0)))
                  :in-theory (enable h1 foo
                                     (:executable-counterpart h1)
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
