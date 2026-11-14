;; Reproducer for SULFA redundancy-removal raw-Lisp vs :logic mismatch proving NIL
;; Source: books/clause-processors/SULFA/books/bv-smt-solver/redundancy-removal.lisp:17-51
(in-package "ACL2")

(encapsulate
 ()
 (defttag acl2::SMT)

 (defun eriks-ht-reset ()
   nil)

 (defun eriks-ht-lookup (key table)
   (assoc-equal key table))

 (defun eriks-ht-set (key val table)
   (cons (cons key val) table))

 (progn!
  (set-raw-mode t)
  (defparameter eriks-hash-table (make-hash-table :test #'equal))

  (defun eriks-ht-lookup (key table)
    (declare (ignore table))
    (multiple-value-bind
     (val foundp)
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

(defthmd sulfa-lemma-exec
  (equal (eriks-ht-set 'a 1 nil) 'eriks-fake-alist)
  :hints (("Goal" :in-theory (executable-counterpart-theory :here))))

(defthmd sulfa-lemma-logic
  (equal (eriks-ht-set 'a 1 nil) '((a . 1)))
  :hints (("Goal" :in-theory (e/d (eriks-ht-set) ((:e eriks-ht-set))))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance sulfa-lemma-exec)
                        (:instance sulfa-lemma-logic)))))
