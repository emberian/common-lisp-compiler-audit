(in-package "ACL2")

(cw "~%=== H1R TAKE ORIGINAL, CORRECTED ===~%")
(defthmd take-1-nil-logic-h1r
  (equal (take 1 nil) '(nil))
  :hints (("Goal" :in-theory (disable (take)))))
(thm nil :hints (("Goal" :use take-1-nil-logic-h1r)))

(cw "~%=== H4B MBE SAFE EVALUATION, VALUE-TRIPLE/LIST ===~%")
(value-triple (list (mbe :logic nil :exec t)))
(defmacro mbe-list-mac-h4b () '(list (mbe :logic nil :exec t)))
(defconst *mbe-list-mac-h4b* (mbe-list-mac-h4b))
(value-triple (mbe-list-mac-h4b))

(cw "~%=== H9 RETURN-LAST/EC-CALL MBE VARIANTS ===~%")
(defmacro raw-mbe-mac-h9 () '(return-last 'mbe1-raw nil t))
(defconst *raw-mbe-mac-h9* (raw-mbe-mac-h9))
(defconst *ec-mbe-h9* (ec-call (mbe :logic nil :exec t)))
(defconst *ec-mbe-list-h9* (list (ec-call (mbe :logic nil :exec t))))

(cw "~%=== H10 LOOP$/LAMBDA$ MBE SAFE-MODE VARIANTS ===~%")
(defconst *loop-mbe-h10*
  (loop$ for x in '(nil) collect (mbe :logic nil :exec t)))
(value-triple (loop$ for x in '(nil) collect (mbe :logic nil :exec t)))
(defconst *lambda-mbe-h10*
  (ec-call (apply$-lambda '(lambda$ (x) (mbe :logic nil :exec t)) '(nil))))

(cw "~%=== H11 NONEXEC THROUGH DEFUN-INLINE AND DEFUN-NX ===~%")
(defun-inline f-inline-h11 ()
  (declare (xargs :guard t :non-executable t))
  (mv-let (a b c) (mv 3 4) (declare (ignore a b)) c))
(defun-nx f-nx-h11 () 3)
(defthm f-nx-logical-h11 (equal (f-nx-h11) 3) :rule-classes nil)
(defconst *call-nx-h11* (f-nx-h11))
(memoize 'f-nx-h11)

(cw "~%=== H12 MV OWN GUARD THROUGH DEFUN-INLINE ===~%")
(defun-inline foo-inline-h12 (x)
  (declare (xargs :guard (or (consp x)
                             (atom (foo-inline-h12 '(a . b))))))
  (mv (car x) (mbe :logic (consp x) :exec t)))

(cw "~%=== H13 PATTERNED CONGRUENCE SAME-VAR SIBLING ===~%")
(defun e-h13 (x y) (equal (fix x) (fix y)))
(defequiv e-h13)
(defun f-h13 (x) (if (consp x) 1 0))
(defthm e-implies-equal-f-same-var-h13
  (implies (e-h13 x x)
           (equal (f-h13 x) (f-h13 x)))
  :rule-classes :congruence)
(defthm f-when-e-0-h13
  (implies (e-h13 x 0) (equal (f-h13 x) 0))
  :hints (("Goal" :in-theory (disable e-h13)))
  :rule-classes nil)
(defthm contradiction-h13
  nil
  :hints (("Goal" :use (:instance f-when-e-0-h13 (x '(1 . 2)))))
  :rule-classes nil)

(cw "~%=== H14 PATTERNED CONGRUENCE LAMBDA$ SIBLING ===~%")
(defthm e-implies-equal-lambda-same-var-h14
  (implies (e-h13 x x)
           (equal ((lambda$ (u) (f-h13 u)) x)
                  ((lambda$ (u) (f-h13 u)) x)))
  :rule-classes :congruence)

(quit)
