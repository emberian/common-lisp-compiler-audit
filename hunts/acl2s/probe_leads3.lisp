(in-package "ACL2S")

(cw "~%=== 1. MAP.LISP VALPRED/KEYBODY MUTUAL REC ===~%")
(defdata (m-key (oneof nil (cons m-rec m-key)))
         (m-rec (map m-key nat)))

(cw "~%=== 2. DEFDATA-CORE TYPE NAMED D ===~%")
(defdata d (listof nat))
(defdata (d (oneof nil (cons nat d))))

(cw "~%=== 3. DEFINEC DUPLICATE FORMALS ARG-SWAP & CONTRACT BUG ===~%")
(definec sub-dup (x :int y :int x :pos) :int
  (- x y))
(sub-dup 10 1) ; caller thinks x=10, y=1 => 9; actually y=10, x=1 => -9!
:pe sub-dup

(definec bad-mbe-guard-bypass (x :nat y :nat x :string) :nat
  (mbe :logic (+ x y) :exec (car x)))
:pe bad-mbe-guard-bypass

(cw "~%=== 4. CCG LOOP$-RECURSION WITH EXPLICIT MEASURE ===~%")
(acl2::set-termination-method :ccg)
(defun ccg-loop-explicit-m (n)
  (declare (xargs :mode :logic :loop$-recursion t :measure (nfix n)))
  (if (zp n)
      0
    (loop$ for i in (list (1- n)) sum (ccg-loop-explicit-m i))))

(cw "~%=== 5. DEFDATA-ATTACH / REGISTER-TYPE WITH :PROGRAM ENUMERATOR ===~%")
(defun prog-enum (n)
  (declare (xargs :mode :program))
  (if (zp n) 0 (prog-enum (1- n))))
(register-type prog-t :predicate natp :enumerator prog-enum)
(thm (equal (nth-prog-t 3) 0))
(value-triple (nth-prog-t 3))

(defun bad-guard-enum (n)
  (declare (xargs :guard (stringp n)))
  (length n))
(register-type badg-t :predicate natp :enumerator bad-guard-enum)
(value-triple (nth-badg-t 3))

(cw "~%=== 6. PROPERTY IMPLIEZ CAPTURE ===~%")
(defun impliez (a b) (declare (ignore a b) (xargs :guard t)) nil)
(property impliez-bug () (impliez nil nil))
(thm (not (impliez nil nil)))
(thm nil)
