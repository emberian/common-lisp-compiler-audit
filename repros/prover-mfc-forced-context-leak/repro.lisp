(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; `meta-extract-contextual-fact` (boot-strap-pass-2-a.lisp:1290-1333) is erased
; from `:meta` rule hypotheses by `remove-meta-extract-contextual-hyps`
; (defthm.lisp:4433-4462) on the premise that calling `mfc-ts`, `mfc-rw`,
; `mfc-rw+`, `mfc-relieve-hyp`, and `mfc-ap` with `:forcep nil :ttreep nil`
; produces facts unconditionally true in `mfc`.
;
; However, `:forcep nil` only suppresses *new* `force-assumption` calls during
; the `mfc-*` query. `rewrite-with-lemma` (rewrite.lisp:19077-19091) passes the
; active `:type-alist` and `:simplify-clause-pot-lst` verbatim into `mfc`,
; including entries/polynomials whose per-entry `ttree`s ALREADY carry forced
; `'assumption` tags (from `:forward-chaining`, `:linear`, or `assume-true-false`
; on `IF` tests). `mfc-ts-fn`, `mfc-rw-fn`, `mfc-rw+-fn`, and `mfc-relieve-hyp-fn`
; (interface-raw.lisp:8355-8387) execute `(declare (ignore ttree))`, and
; `mfc-ap-raw` (ld.lisp:4817, 4851, 4896) drops `linearize`'s `ttree` and
; ignores `(access poly contradictionp :ttree)`.
;
; Below we demonstrate three affected `meta-extract-contextual-fact` operators
; (`:typeset`, `:rw`, and `:ap` over both `type-alist` and `simplify-clause-pot-lst`),
; each proving a false lemma with ZERO forcing rounds and deriving `nil-proved`.

(defun h1 (x)
  (declare (xargs :guard t))
  (equal x 99))

(defun trig (x)
  (declare (xargs :guard t))
  (integerp x))

(defun aux (x)
  (declare (xargs :guard t))
  (not (h1 x)))

(defun aux-t (x)
  (declare (xargs :guard t))
  (h1 x))

(defun val (x)
  (declare (xargs :guard t))
  (if (h1 x) -1 10))

(defun target-ts (x)
  (declare (xargs :guard t))
  (aux x))

(defun target-rw (x)
  (declare (xargs :guard t))
  (aux-t x))

(defun target-ap (x)
  (declare (xargs :guard t))
  (not (< (val x) 0)))

; 1a. Valid :forward-chaining rule placing forced `(not (aux x))` onto `type-alist`
(defthm aux-false-fc-when-forced
  (implies (and (trig x)
                (force (h1 x)))
           (not (aux x)))
  :rule-classes ((:forward-chaining :trigger-terms ((trig x)))))

; 1b. Valid :forward-chaining rule placing forced `(equal (aux-t x) t)` onto `type-alist`
(defthm aux-t-true-fc-when-forced
  (implies (and (trig x)
                (force (h1 x)))
           (equal (aux-t x) t))
  :rule-classes ((:forward-chaining :trigger-terms ((trig x)))))

; 2. Valid :linear rule placing forced `(< (val x) 0)` into `simplify-clause-pot-lst`
(defthm val-neg-linear-when-forced
  (implies (and (< 0 x)
                (force (h1 x)))
           (< (val x) 0))
  :rule-classes ((:linear :trigger-terms ((val x)))))

(in-theory (disable h1 trig aux aux-t val
                    (:executable-counterpart h1)
                    (:executable-counterpart trig)
                    (:executable-counterpart aux)
                    (:executable-counterpart aux-t)
                    (:executable-counterpart val)
                    (:type-prescription h1)
                    (:type-prescription trig)
                    (:type-prescription aux)
                    (:type-prescription aux-t)
                    (:type-prescription val)))

(defevaluator evm evm-lst
  ((target-ts x) (target-rw x) (target-ap x) (aux x) (aux-t x) (val x)
   (< x y) (not x) (typespec-check ts x) (equal x y) (iff x y) (if x y z))
  :namedp t)

; Variant A (:typeset / mfc-ts): reads forced type-alist entry and drops ttree
(defun meta-ts-fn (term mfc state)
  (declare (xargs :stobjs state :guard t))
  (if (and (consp term)
           (eq (car term) 'target-ts)
           (consp (cdr term))
           (null (cddr term))
           (equal (mfc-ts (list 'aux (cadr term)) mfc state :forcep nil :ttreep nil)
                  *ts-nil*))
      ''nil
    term))

(defthm meta-ts-correct
  (implies (evm (meta-extract-contextual-fact
                 (list ':typeset (list 'aux (cadr term)))
                 mfc state)
                a)
           (equal (evm term a)
                  (evm (meta-ts-fn term mfc state) a)))
  :hints (("Goal" :in-theory (enable typespec-check)))
  :rule-classes ((:meta :trigger-fns (target-ts))))

; Variant B (:rw+ / mfc-rw+): rewrites via forced type-alist entry and drops ttree
(defun meta-rw-fn (term mfc state)
  (declare (xargs :stobjs state :guard t))
  (if (and (consp term)
           (eq (car term) 'target-rw)
           (consp (cdr term))
           (null (cddr term))
           (equal (mfc-rw+ '(aux-t z)
                           (list (cons 'z (cadr term)))
                           '? nil mfc state :forcep nil :ttreep nil)
                  ''t))
      ''t
    term))

(defthm meta-rw-correct
  (implies (evm (meta-extract-contextual-fact
                 (list ':rw+ '(aux-t z) (list (cons 'z (cadr term))) '? nil)
                 mfc state)
                a)
           (equal (evm term a)
                  (evm (meta-rw-fn term mfc state) a)))
  :rule-classes ((:meta :trigger-fns (target-rw))))

; Variant C (:ap / mfc-ap): derives linear contradiction from forced poly in pot-lst
(defun meta-ap-fn (term mfc state)
  (declare (xargs :stobjs state :guard t))
  (if (and (consp term)
           (eq (car term) 'target-ap)
           (consp (cdr term))
           (null (cddr term))
           (mfc-ap (list 'not (list '< (list 'val (cadr term)) ''0))
                   mfc state :forcep nil))
      ''nil
    term))

(defthm meta-ap-correct
  (implies (evm (meta-extract-contextual-fact
                 (list ':ap (list 'not (list '< (list 'val (cadr term)) ''0)))
                 mfc state)
                a)
           (equal (evm term a)
                  (evm (meta-ap-fn term mfc state) a)))
  :rule-classes ((:meta :trigger-fns (target-ap))))

(in-theory (disable target-ts target-rw target-ap
                    (:executable-counterpart target-ts)
                    (:executable-counterpart target-rw)
                    (:executable-counterpart target-ap)
                    (:type-prescription target-ts)
                    (:type-prescription target-rw)
                    (:type-prescription target-ap)))

; All three false lemmas succeed with 0 forcing rounds!
(defthm unsound-mfc-ts-lemma
  (implies (trig x)
           (not (target-ts x)))
  :rule-classes nil)

(defthm unsound-mfc-rw-lemma
  (implies (trig x)
           (target-rw x))
  :rule-classes nil)

(defthm unsound-mfc-ap-lemma
  (implies (and (< 0 x)
                (< (val x) 100))
           (not (target-ap x)))
  :rule-classes nil)

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance unsound-mfc-ts-lemma (x 0)))
                  :in-theory (enable h1 trig aux target-ts
                                     (:executable-counterpart h1)
                                     (:executable-counterpart trig)
                                     (:executable-counterpart aux)
                                     (:executable-counterpart target-ts)))))

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
