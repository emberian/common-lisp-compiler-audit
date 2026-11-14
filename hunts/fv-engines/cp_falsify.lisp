;; Prototype mechanical falsification harness for FV engines & clause processors.
;; Exercises:
;;   1) centaur/misc/fast-alist-pop.lisp (`fast-alist-pop*` invariant-risk omission -> NIL)
;;   2) clause-processors/SULFA/books/bv-smt-solver/redundancy-removal.lisp (`eriks-ht-*` -> NIL)
;;   3) clause-processors/{autohide,remove-hyp,null-fail-hints,bv-add} bad-hint resilience (:ttags nil)

(in-package "ACL2")

;; 1. Verify :ttags nil lightweight clause processors reject/survive malformed hints cleanly
(include-book "clause-processors/autohide" :dir :system :uncertified-okp t)
(include-book "clause-processors/remove-hyp" :dir :system :uncertified-okp t)
(include-book "clause-processors/null-fail-hints" :dir :system :uncertified-okp t)

(defthm fuzz-autohide-bad-hint (equal x x)
  :rule-classes nil
  :hints (("Goal" :clause-processor (autohide-cp clause '(a . b)))))

(defthm fuzz-remove-hyp-bad-hint (implies (consp x) (equal (len (cons y x)) (+ 1 (len x))))
  :rule-classes nil
  :hints ((and (equal id '((0)))
               '(:clause-processor (remove-first-hyp-cp clause)))))

(defthm fuzz-identity-cp (equal x x)
  :rule-classes nil
  :hints (("Goal" :clause-processor (identity-clause-processor clause))))

;; 2. Fast-alist-pop* invariant-risk bypass (centaur/misc/fast-alist-pop-raw.lsp)
(include-book "centaur/misc/fast-alist-pop" :dir :system :uncertified-okp t :ttags :all)

(defconst *fap-alist1* (hons-acons 'a 2 nil))
(defconst *fap-alist2* (hons-acons 'a 1 *fap-alist1*))
(defun fap-prog (x)
  (declare (xargs :mode :program))
  (fast-alist-pop* nil x))
(make-event
 (let ((ignored (fap-prog *fap-alist2*)))
   (declare (ignore ignored))
   '(value-triple :fap-corrupted)))
(defthmd fap-lemma1
  (equal (hons-get 'a *fap-alist1*) nil)
  :hints (("Goal" :in-theory (executable-counterpart-theory :here))))
(defthmd fap-lemma2
  (equal (hons-get 'a *fap-alist1*) '(a . 2))
  :hints (("Goal" :in-theory (e/d (hons-get hons-assoc-equal) ((:e hons-get))))))
(defthm nil-via-fast-alist-pop*
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance fap-lemma1) (:instance fap-lemma2)))))

;; 3. SULFA redundancy-removal.lisp:17-51 raw Lisp / logic mismatch -> NIL
(encapsulate ()
  (defttag acl2::SMT)
  (defun eriks-ht-reset () nil)
  (defun eriks-ht-lookup (key table) (assoc-equal key table))
  (defun eriks-ht-set (key val table) (cons (cons key val) table))
  (progn!
   (set-raw-mode t)
   (defparameter eriks-hash-table (make-hash-table :test #'equal))
   (defun eriks-ht-lookup (key table)
     (declare (ignore table))
     (multiple-value-bind (val foundp)
         (gethash key eriks-hash-table)
       (if foundp (cons key val) nil)))
   (defun eriks-ht-set (key val table)
     (declare (ignore table))
     (progn
       (setf (gethash key eriks-hash-table) val)
       'eriks-fake-alist))
   (defun eriks-ht-reset ()
     (progn
       (clrhash eriks-hash-table)
       'eriks-fake-alist))
   (set-raw-mode nil)))

(verify-guards eriks-ht-set)
(defthmd sulfa-lemma1
  (equal (eriks-ht-set 'a 1 nil) 'eriks-fake-alist)
  :hints (("Goal" :in-theory (executable-counterpart-theory :here))))
(defthmd sulfa-lemma2
  (equal (eriks-ht-set 'a 1 nil) '((a . 1)))
  :hints (("Goal" :in-theory (e/d (eriks-ht-set) ((:e eriks-ht-set))))))
(defthm nil-via-sulfa-eriks-ht
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance sulfa-lemma1) (:instance sulfa-lemma2)))))
