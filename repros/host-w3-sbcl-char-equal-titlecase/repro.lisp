;;;; Repro: SBCL 2.6.10 char-equal / string-equal Unicode titlecase asymmetry & transform mismatch
;;;; Confirmed zero-UB on both ARM64 and X86-64 SBCL 2.6.10 at (safety 3) and default optimize.
;;;; Root causes:
;;;;   1. srctran.lisp:6664-6676 (transform-constant-char-equal) assumes every both-case-p char
;;;;      has a single opposite-case partner via (if (upper-case-p c) (char-downcase c) (char-upcase c)),
;;;;      omitting the third member of Unicode digraph titlecase triples (452/453/454, 455/456/457,
;;;;      458/459/460, 497/498/499), causing 12 compiler-vs-runtime mismatches.
;;;;   2. src/code/target-char.lisp:441-445 (two-arg-char-equal-inline) checks only c1's lower
;;;;      and upper entries against (char-code c2), making char-equal & string-equal non-symmetric
;;;;      across 16 pairs (e.g. (char-equal #\U01C5 #\U01C4) => T, (char-equal #\U01C4 #\U01C5) => NIL).

(declaim (optimize (speed 1) (safety 3)))

(defun char-equal-const-452 (x)
  (declare (type character x))
  (char-equal x #.(code-char 452)))

(defun char-equal-const-453 (x)
  (declare (type character x))
  (char-equal x #.(code-char 453)))

(defun char-equal-ni (x y)
  (declare (type character x y) (notinline char-equal))
  (char-equal x y))

(let* ((u (code-char 452))
       (ti (code-char 453))
       (c-452-ti (char-equal-const-452 ti))
       (r-452-ti (char-equal-ni ti u))
       (c-453-u (char-equal-const-453 u))
       (r-453-u (char-equal-ni u ti))
       (s-ti-u (string-equal (string ti) (string u)))
       (s-u-ti (string-equal (string u) (string ti))))
  (format t "Arch: ~A ~A (~A)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))
  (format t "compiled (char-equal ti 452)=~S vs notinline=~S (match=~S)~%" c-452-ti r-452-ti (eq c-452-ti r-452-ti))
  (format t "compiled (char-equal u  453)=~S vs notinline=~S (match=~S)~%" c-453-u r-453-u (eq c-453-u r-453-u))
  (format t "string-equal 453vs452=~S vs 452vs453=~S (symmetric=~S)~%" s-ti-u s-u-ti (eq s-ti-u s-u-ti)))
#+ccl (ccl:quit 0)
