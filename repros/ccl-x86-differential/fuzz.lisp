;;;; Portable differential fuzzer for CL compilers (CCL vs SBCL, safe vs fast).
;;;; Generates deterministic random typed CL functions, compiles each under
;;;; (speed 3)(safety 0) and (speed 0)(safety 3), evaluates on fixed input rows,
;;;; and prints  seed <TAB> safe-serialization <TAB> fast-serialization.
;;;; Determinism: own 64-bit LCG (NOT cl:random), so CCL and SBCL produce the
;;;; byte-identical form/input stream for a given seed => outputs are line-comparable.

(declaim (optimize (speed 1) (safety 3)))

;;; Disable float traps in BOTH impls so overflow/invalid yield IEEE inf/nan
;;; (comparable) instead of one impl trapping and the other not -- that trap-policy
;;; difference is not a soundness bug. Value equality rule: floats compared by exact
;;; IEEE bits via integer-decode-float; inf/nan by tag.
#+ccl (ignore-errors (ccl:set-fpu-mode :overflow nil :underflow nil
                                       :division-by-zero nil :invalid nil :inexact nil))
#+sbcl (ignore-errors (sb-int:set-floating-point-modes :traps nil))

;;; ---- deterministic PRNG (identical across impls; pure integer arithmetic) ----
(defvar *st* 0)
(defun seed! (s)
  (setf *st* (logand (+ (* (+ s 1) 2862933555777941757) 3037000493) #xffffffffffffffff))
  (dotimes (i 4) (nxt)))
(defun nxt ()
  (setf *st* (logand (+ (* *st* 6364136223846793005) 1442695040888963407)
                     #xffffffffffffffff))
  (ldb (byte 30 20) *st*))
(defun rnd (n) (mod (nxt) n))
(defun pick (list) (nth (rnd (length list)) list))

;;; ---- input variables and their declared types ----
;;; fixnum vars kept within CCL's smaller fixnum range (+-(2^60-1)) so an honest
;;; (type fixnum ..) declaration holds in BOTH impls (SBCL fixnum is 2^62-1).
(defparameter *fix-vars*   '(xi yi))
(defparameter *int-vars*   '(bi ci))      ; general integer (may be bignum)
(defparameter *dbl-vars*   '(di ei))
(defparameter *sgl-vars*   '(fi))
(defparameter *chr-vars*   '(ch))

(defparameter *ccl-fixmax* 1152921504606846975) ; 2^60-1

(defun gen-fix-value ()
  (case (rnd 10)
    ((0 1 2 3) (- (rnd 2001) 1000))
    ((4 5) (- (rnd 2000000) 1000000))
    (6 (- (ash 1 59)))           ; near-boundary (still fixnum in both)
    (7 (ash 1 59))
    (8 (- *ccl-fixmax* (rnd 4)))
    (9 (+ (- *ccl-fixmax*) (rnd 4)))))

(defun gen-int-value ()
  (case (rnd 10)
    ((0 1 2) (- (rnd 2001) 1000))
    ((3 4) (- (ash 1 (+ 61 (rnd 8))) (rnd 7)))    ; just above fixnum / bignum
    ((5 6) (* (if (zerop (rnd 2)) 1 -1) (ash 1 (+ 62 (rnd 140)))))  ; big bignum
    (7 (- (rnd 20) 10))
    (8 (+ (ash 1 63) (rnd 1000)))
    (9 (- (ash 1 100) (rnd 1000)))))

(defun gen-dbl-value ()
  (let ((n (- (rnd 2000001) 1000000)))
    (case (rnd 6)
      ((0 1 2) (coerce n 'double-float))
      (3 (/ (coerce n 'double-float) 1024d0))
      (4 (coerce (- (rnd 21) 10) 'double-float))
      (5 (* (coerce n 'double-float) 1d-3)))))

(defun gen-sgl-value ()
  (let ((n (- (rnd 20001) 10000)))
    (case (rnd 4)
      ((0 1) (coerce n 'single-float))
      (2 (/ (coerce n 'single-float) 64f0))
      (3 (coerce (- (rnd 21) 10) 'single-float)))))

(defun gen-chr-value () (code-char (rnd 128)))

;;; ---- expression generators (typed) ----
(defun byte-spec ()
  (let ((size (rnd 32)) (pos (rnd 40))) `(byte ,size ,pos)))

(defun gen-nonzero-int (d)
  (let ((e (if (zerop (rnd 2))
               (let ((k (- (rnd 34) 17))) (if (zerop k) 3 k))
               (gen-int d))))
    `(if (zerop ,e) 1 ,e)))

(defun gen-int (d)
  (if (or (<= d 0) (zerop (rnd 3)))
      (case (rnd 8)
        (0 (pick *fix-vars*)) (1 (pick *fix-vars*))
        (2 (pick *int-vars*)) (3 (pick *int-vars*))
        (4 (- (rnd 41) 20))
        (5 (pick (list 0 1 -1 2 255 256 (ash 1 30) (- (ash 1 30)) *ccl-fixmax*)))
        (6 `(char-code ,(gen-chr d)))
        (7 (- (rnd 2001) 1000)))
      (case (rnd 28)
        (0 `(+ ,(gen-int (1- d)) ,(gen-int (1- d))))
        (1 `(- ,(gen-int (1- d)) ,(gen-int (1- d))))
        (2 `(* ,(gen-int (1- d)) ,(gen-int (1- d))))
        (3 `(- ,(gen-int (1- d))))
        (4 `(1+ ,(gen-int (1- d))))
        (5 `(1- ,(gen-int (1- d))))
        (6 `(abs ,(gen-int (1- d))))
        (7 `(min ,(gen-int (1- d)) ,(gen-int (1- d))))
        (8 `(max ,(gen-int (1- d)) ,(gen-int (1- d))))
        (9 `(logand ,(gen-int (1- d)) ,(gen-int (1- d))))
        (10 `(logior ,(gen-int (1- d)) ,(gen-int (1- d))))
        (11 `(logxor ,(gen-int (1- d)) ,(gen-int (1- d))))
        (12 `(lognot ,(gen-int (1- d))))
        (13 `(ash ,(gen-int (1- d)) ,(- (rnd 97) 48)))
        (14 `(ash ,(gen-int (1- d)) (- (logand ,(gen-int (1- d)) 63) 32)))
        (15 `(ldb ,(byte-spec) ,(gen-int (1- d))))
        (16 `(dpb ,(gen-int (1- d)) ,(byte-spec) ,(gen-int (1- d))))
        (17 `(mask-field ,(byte-spec) ,(gen-int (1- d))))
        (18 `(logcount ,(gen-int (1- d))))
        (19 `(integer-length ,(gen-int (1- d))))
        (20 `(truncate ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (21 `(floor ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (22 `(ceiling ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (23 `(round ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (24 `(mod ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (25 `(rem ,(gen-int (1- d)) ,(gen-nonzero-int (1- d))))
        (26 `(if ,(gen-bool (1- d)) ,(gen-int (1- d)) ,(gen-int (1- d))))
        (27 (let ((v (gensym)) (q (gensym)) (r (gensym)))
              (declare (ignore v))
              `(multiple-value-bind (,q ,r)
                   (,(pick '(truncate floor ceiling round))
                     ,(gen-int (1- d)) ,(gen-nonzero-int (1- d)))
                 (+ (* ,q 2) ,r)))))))

(defun gen-flt (d ftype)
  (let ((one (coerce 1 ftype)))
    (if (or (<= d 0) (zerop (rnd 3)))
        (case (rnd 5)
          (0 (pick (if (eq ftype 'double-float) *dbl-vars* *sgl-vars*)))
          (1 (pick (if (eq ftype 'double-float) *dbl-vars* *sgl-vars*)))
          (2 (coerce (- (rnd 21) 10) ftype))
          (3 `(float ,(gen-int (1- d)) ,one))
          (4 (coerce (/ (- (rnd 201) 100) 10) ftype)))
        (case (rnd 8)
          (0 `(+ ,(gen-flt (1- d) ftype) ,(gen-flt (1- d) ftype)))
          (1 `(- ,(gen-flt (1- d) ftype) ,(gen-flt (1- d) ftype)))
          (2 `(* ,(gen-flt (1- d) ftype) ,(gen-flt (1- d) ftype)))
          (3 `(- ,(gen-flt (1- d) ftype)))
          (4 `(abs ,(gen-flt (1- d) ftype)))
          (5 `(min ,(gen-flt (1- d) ftype) ,(gen-flt (1- d) ftype)))
          (6 `(max ,(gen-flt (1- d) ftype) ,(gen-flt (1- d) ftype)))
          (7 (let ((den (gen-flt (1- d) ftype)))
               `(/ ,(gen-flt (1- d) ftype) (if (zerop ,den) ,one ,den))))))))

(defun gen-bool (d)
  (case (rnd 10)
    ((0 1 2) `(,(pick '(< <= > >= = /=)) ,(gen-int (1- d)) ,(gen-int (1- d))))
    ((3 4) `(,(pick '(< <= > >= =)) ,(gen-flt (1- d) 'double-float)
                                    ,(gen-flt (1- d) 'double-float)))
    (5 `(zerop ,(gen-int (1- d))))
    (6 `(,(pick '(plusp minusp evenp oddp)) ,(gen-int (1- d))))
    (7 `(,(pick '(char< char> char= char<= char>=)) ,(gen-chr d) ,(gen-chr d)))
    (8 `(,(pick '(and or)) ,(gen-bool (1- d)) ,(gen-bool (1- d))))
    (9 `(not ,(gen-bool (1- d))))))

(defun gen-chr (d)
  (case (rnd 5)
    ((0 1) (pick *chr-vars*))
    (2 `(code-char (logand ,(gen-int (max 0 (1- d))) 127)))
    (3 `(char-upcase ,(pick *chr-vars*)))
    (4 `(char-downcase ,(pick *chr-vars*)))))

;;; occasional array variant wrapping an int body
(defun gen-array-int (d)
  (let ((etype (pick '((unsigned-byte 8) (unsigned-byte 32) (unsigned-byte 64)
                       (signed-byte 8) fixnum)))
        (idx (gen-int (1- d))))
    `(let ((arr (make-array 5 :element-type ',etype
                              :initial-contents (list ,@(loop repeat 5
                                                              collect (if (eq etype 'fixnum)
                                                                          `(logand ,(gen-int 1) 1023)
                                                                          `(logand ,(gen-int 1) 7)))))))
       (declare (type (simple-array ,etype (5)) arr))
       (aref arr (mod (abs ,idx) 5)))))

(defun gen-body ()
  (case (rnd 12)
    ((0 1 2 3 4 5) (gen-int 4))       ; integer arithmetic/bitops (main yield)
    ((6 7) (gen-flt 3 'double-float))
    (8 (gen-flt 3 'single-float))
    (9 `(if ,(gen-bool 3) ,(gen-int 3) ,(gen-int 3)))
    (10 (gen-array-int 4))
    (11 `(the ,(pick (list 'integer 'fixnum 't
                           (list 'integer (- *ccl-fixmax*) *ccl-fixmax*)))
              ,(pick *fix-vars*)))))  ; correct, boundary-tight `the`

(defparameter *arglist* '(xi yi bi ci di ei fi ch))
(defparameter *decls*
  '(declare (type fixnum xi yi) (type integer bi ci)
            (type double-float di ei) (type single-float fi) (type character ch)))

(defun gen-row ()
  (list (gen-fix-value) (gen-fix-value) (gen-int-value) (gen-int-value)
        (gen-dbl-value) (gen-dbl-value) (gen-sgl-value) (gen-chr-value)))

;;; ---- result serialization (portable, exact, line-comparable) ----
(defun ser1 (v)
  (typecase v
    (integer (format nil "~d" v))
    (ratio (format nil "R~d/~d" (numerator v) (denominator v)))
    (double-float (ser-float v #\D))
    (single-float (ser-float v #\S))
    (character (format nil "C~d" (char-code v)))
    (string (format nil "T~d:~a" (length v) v))
    (null "N!")
    (symbol (if (eq v t) "T!" (format nil "Y:~a" v)))
    (complex (format nil "X(~a)(~a)" (ser1 (realpart v)) (ser1 (imagpart v))))
    (t (format nil "?~a" (type-of v)))))

(defun ser-float (v tag)
  (cond ((/= v v) (format nil "~cNAN" tag))          ; NaN
        ((and (> (abs v) 0) (or (> v most-positive-double-float)
                                (< v most-negative-double-float))) ; crude inf
         (format nil "~cINF~a" tag (if (plusp v) "+" "-")))
        ((zerop v) (format nil "~cZ~a" tag (if (minusp (float-sign v)) "-" "+"))) ; +/-0.0
        (t (handler-case
               (multiple-value-bind (m e s) (integer-decode-float v)
                 (if (zerop m)
                     (format nil "~cZ~d" tag s)
                     (format nil "~c~d.~d.~d" tag s m e)))
             (error () (format nil "~cNONFIN" tag))))))

(defun serialize (vals)
  (if (= (length vals) 1)
      (ser1 (first vals))
      (format nil "~{~a~^,~}" (mapcar #'ser1 vals))))

(defun err-cat (e)
  (typecase e
    (division-by-zero "E:DIV0")
    (floating-point-overflow "E:FPOVER")
    (floating-point-underflow "E:FPUNDER")
    (type-error "E:TYPE")
    (arithmetic-error "E:ARITH")
    (storage-condition "E:STORAGE")
    (error (format nil "E:~a" (type-of e)))
    (t (format nil "E?:~a" (type-of e)))))

(defun build-lambda (body policy)
  `(lambda ,*arglist*
     ,*decls*
     (declare (optimize ,@policy))
     ,body))

(defun run-one (fn rows)
  "Return serialization of fn applied across rows, or an error category."
  (handler-case
      (format nil "~{~a~^|~}"
              (loop for row in rows
                    collect (handler-case
                                (serialize (multiple-value-list (apply fn row)))
                              (error (e) (err-cat e))
                              (storage-condition (e) (err-cat e)))))
    (error (e) (format nil "OUTER~a" (err-cat e)))))

(defun compile-quiet (form)
  (handler-bind ((warning #'muffle-warning))
    (compile nil form)))

(defun emit (start end)
  (loop for seed from start below end do
    (seed! seed)
    (let* ((body (gen-body))
           (rows (loop repeat 6 collect (gen-row)))
           (safe-src (build-lambda body '((speed 0) (safety 3) (debug 0))))
           (fast-src (build-lambda body '((speed 3) (safety 0) (debug 0))))
           (safe-fn (handler-case (compile-quiet safe-src) (error (e) (err-cat e))))
           (fast-fn (handler-case (compile-quiet fast-src) (error (e) (err-cat e))))
           (safe-res (if (functionp safe-fn) (run-one safe-fn rows) (format nil "CERR~a" safe-fn)))
           (fast-res (if (functionp fast-fn) (run-one fast-fn rows) (format nil "CERR~a" fast-fn))))
      (format t "~d~c~a~c~a~%" seed #\Tab safe-res #\Tab fast-res)
      (force-output))))

(defun getenv* (k)
  (or #+ccl (ccl:getenv k) #+sbcl (sb-ext:posix-getenv k) nil))

;;; entry: read START END from env, or SHOW=<seed> to dump the generated form.
(let ((show (getenv* "SHOW")))
  (if show
      (let ((seed (parse-integer show)))
        (seed! seed)
        (let ((body (gen-body))
              (rows (loop repeat 6 collect (gen-row))))
          (format t "SEED ~d~%BODY ~s~%" seed body)
          (dolist (r rows) (format t "ROW ~s~%" r))
          (format t "SAFE ~a~%" (run-one (compile-quiet (build-lambda body '((speed 0)(safety 3)))) rows))
          (format t "FAST ~a~%" (run-one (compile-quiet (build-lambda body '((speed 3)(safety 0)))) rows))))
      (emit (parse-integer (or (getenv* "START") "0"))
            (parse-integer (or (getenv* "END") "1000"))))
  #+ccl (ccl:quit 0)
  #+sbcl (sb-ext:exit :code 0))
