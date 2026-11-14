(in-package "ACL2S")

(cw "~%=== TEST 1: REGISTER-TYPE :PROGRAM ENUMERATOR CRASHES GUARD-VERIFIED CALL ===~%")
(defun evil-enum (n)
  (declare (xargs :mode :program :guard (natp n)))
  (car n))
(register-type evil-t :predicate natp :enumerator evil-enum)
(defun verified-caller (n)
  (declare (xargs :guard (natp n) :verify-guards t))
  (nth-evil-t n))
(verified-caller 3)

(cw "~%=== TEST 2: DEFDATA-ATTACH UNVERIFIED ENUMERATOR CRASHES NTH-NAT ===~%")
(defun evil-nat-enum (n)
  (declare (xargs :guard (natp n) :verify-guards nil))
  (car n))
(defdata-attach nat :enumerator evil-nat-enum)
(defun verified-nat-caller (n)
  (declare (xargs :guard (natp n) :verify-guards t))
  (nth-nat n))
(verified-nat-caller 3)

(cw "~%=== TEST 3: DEFINEC DUPLICATE FORMAL + BAD MBE ===~%")
(definec bad-mbe-guard-bypass (x :nat y :nat x :string) :nat
  (mbe :logic (+ x y) :exec (car x)))
:pe bad-mbe-guard-bypass
(verify-guards bad-mbe-guard-bypass)
(bad-mbe-guard-bypass 1 2)
