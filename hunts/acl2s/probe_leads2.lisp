;; Probe batch 2 for ACL2s audit leads
(in-package "ACL2S")

(cw "~%=== A: DEFINEC DUPLICATE FORMALS & CAPTURES ===~%")
:trans1 (definec bad-dup (x :nat x :pos) :nat (+ x 1))
(definec bad-dup (x :nat x :pos) :nat (+ x 1))
:pe bad-dup
(bad-dup 0 1)
(bad-dup 1 0)
(definec bad-dup-disjoint (x :nat x :string) :nat 42)
:pe bad-dup-disjoint
(bad-dup-disjoint 0 "hi")
(definec bad-dup-3 (x :nat y :pos x :string) :nat (+ x y))
:pe bad-dup-3

(cw "~%=== B: RECURSIVE EMPTY / NON-WELL-FOUNDED DEFDATA ===~%")
(defdata inf-tree (cons nat inf-tree))
:pe inf-treep
:pe nth-inf-tree-builtin
(defdata inf-oneof (oneof (cons nat inf-oneof)))
(defdata (mut-e1 (cons nat mut-e2)) (mut-e2 (cons pos mut-e1)))
(defdata r-with-d (record (d . nat)))
(defdata mut-map-rec (record (m . my-m)) (my-m (map mut-map-key nat)) (mut-map-key (oneof 1 2)))
(defdata (m-key (oneof 1 2)) (m-rec (map m-key nat)))

(cw "~%=== C: DEFDATA REGISTER-TYPE & DEFDATA-ATTACH ===~%")
(defun always-false (x) (declare (ignore x) (xargs :guard t)) nil)
(defun fake-enum (n) (declare (ignore n) (xargs :guard (natp n))) 0)
(defthm bogus-check-fail (always-false (fake-enum n))) ; should fail
(register-type empty-reg :predicate always-false :enumerator fake-enum)
(defdata-attach empty-reg :predicate always-false :override-ok t)
(register-type empty-reg2 :predicate always-false :enumerator fake-enum :skip-checks t)

(cw "~%=== D: CCG LOOP$-RECURSION & HINTS & ASSUMPTIONS ===~%")
(acl2::set-termination-method :ccg)
(defun ccg-loop-flag (n)
  (declare (xargs :mode :logic :loop$-recursion t))
  (if (zp n)
      0
    (loop$ for i in (list (1- n)) sum (ccg-loop-flag i))))
(defun ccg-loop-qm (n)
  (declare (xargs :mode :logic :loop$-recursion t :measure (:? n)))
  (if (zp n)
      0
    (loop$ for i in (list (1- n)) sum (ccg-loop-qm i))))
(defun ccg-loop-nonterm2 (n)
  (declare (xargs :mode :logic :loop$-recursion t :measure (:? n)))
  (loop$ for i in (list n) sum (+ 1 (ccg-loop-nonterm2 i))))
(defun ccg-ruler-nil (n)
  (declare (xargs :mode :logic :ruler-extenders nil))
  (if (zp n) 0 (ccg-ruler-nil (1- n))))

(cw "~%=== E: PROPERTY IMPLIEZ & DEFINE-C EDGE CASES ===~%")
:trans1 (property (x :nat) (let ((implies 1)) (+ x implies)))
(property (x :nat) (let ((implies 1)) (natp (+ x implies))))
(property (x :nat) (equal 'implies 'impliez))
(property (x :nat) (natp (impliez t x)))
(definec stobj-test (x :nat state) :mv (nat state) (mv (+ x 1) state))
:pe stobj-test
