(in-package "ACL2")
; Partial memoization table entry carrying a bogus raw definition.
(defun f-limit (x limit)
  (declare (type (integer 0 *) limit) (xargs :measure (nfix limit)))
  (if (zp limit) 0
    (let ((limit (1- limit)))
      (if (atom x) 7 (f-limit (cdr x) limit)))))
(defthm f-limit-is-0-or-7
  (or (equal (f-limit x limit) 0) (equal (f-limit x limit) 7))
  :rule-classes nil)
(defchoose f-limit-change (large) (x limit)
  (and (natp large) (<= limit large)
       (not (equal (f-limit x limit) (f-limit x large)))))
(defchoose f-limit-stable (limit) (x)
  (and (natp limit)
       (equal (f-limit x limit) (f-limit x (f-limit-change x limit)))))
(defun f (x)
  (declare (xargs :guard t))
  (f-limit x (nfix (non-exec (f-limit-stable x)))))
(defthm f-is-0-or-7
  (or (equal (f x) 0) (equal (f x) 7))
  :hints (("Goal" :use (:instance f-limit-is-0-or-7
                                  (limit (nfix (f-limit-stable x))))))
  :rule-classes nil)
(encapsulate ()
  (table partial-functions-table 'f-limit
         '((f f-limit f-limit-change f-limit-stable
              (defun f (x) (declare (ignore x)) 99))))
  (memoize 'f :total 'f-limit)
  (defthm nil-proved nil
    :hints (("Goal" :use (:instance f-is-0-or-7 (x '(a b c)))))
    :rule-classes nil))
; Genuine generated entry remains accepted and computes the honest value.
(memoize-partial f)
(assert-event (equal (f '(a b c)) 7))
(quit)
