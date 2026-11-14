;;;; Differential Soundness Fuzzer for Clozure CL 1.14 (ARM64)
;;;; Targets: acode-rewrite.lisp, nx0/nx1.lisp, compiler/ARM64/arm642.lisp, arm64-vinsns.lisp
;;;; Compares: OPT (speed 3, safety 0) vs DEFAULT (speed 1, safety 1)
;;;;           vs SAFE (speed 0, safety 3) vs SAFE-FAST (speed 3, safety 3, space 0)
;;;;           vs NOTINLINE oracle, and exports test vectors for SBCL 2.6.10 cross-check.

(defpackage #:ccl-codegen-fuzz
  (:use #:cl))

(in-package #:ccl-codegen-fuzz)

(defparameter *mismatches* nil)
(defparameter *total-checks* 0)
(defparameter *sbcl-cases* nil)

(defun norm-val (v)
  "Normalize result values including signed zero distinction and condition class."
  (cond
    ((floatp v)
     (cond ((/= v v) (list :nan (type-of v)))
           ((= v 0) (list :zero (type-of v) (if (< (float-sign v) 0) -1 +1)))
           ((> (abs v) most-positive-double-float)
            (list :inf (type-of v) (if (> v 0) +1 -1)))
           (t v)))
    ((complexp v)
     (list :complex (norm-val (realpart v)) (norm-val (imagpart v))))
    ((consp v)
     (cons (norm-val (car v)) (norm-val (cdr v))))
    ((and (vectorp v) (not (stringp v)))
     (map 'list #'norm-val v))
    (t v)))

(defun safe-call (fn &rest args)
  (handler-case
      (cons :ok (mapcar #'norm-val (multiple-value-list (apply fn args))))
    (error (c)
      (list :err (type-of c)))))

(defun record-mismatch (suite desc details)
  (push (list :suite suite :desc desc :details details) *mismatches*)
  (format t "~%[MISMATCH] [~A] ~A~%  ~S~%" suite desc details)
  (finish-output))

(defparameter *all-notinline-syms*
  '(+ - * / 1+ 1- = /= < > <= >= max min abs signum zerop plusp minusp oddp evenp
    ash logand logior logxor logeqv lognand lognor logandc1 logandc2 logorc1 logorc2
    lognot logtest logbitp logcount integer-length boole
    byte byte-size byte-position ldb ldb-test dpb mask-field deposit-field
    truncate floor ceiling round mod rem gcd lcm isqrt expt
    aref svref sbit bit char schar elt length nth-value values))

(defun compile-variant (params decls body mode)
  (let ((opt-decl
          (ecase mode
            (:opt       '(optimize (speed 3) (safety 0) (space 0) (debug 0)))
            (:default   '(optimize (speed 1) (safety 1) (space 1) (debug 1)))
            (:safe      '(optimize (speed 0) (safety 3) (space 1) (debug 3)))
            (:safe-fast '(optimize (speed 3) (safety 3) (space 0) (debug 1)))
            (:notinline `(optimize (speed 1) (safety 3)))))
        (extra-decls
          (if (eq mode :notinline)
              `((notinline ,@*all-notinline-syms*))
              nil)))
    (handler-case
        (values
         (compile nil
                  `(lambda ,params
                     (declare ,opt-decl ,@extra-decls ,@decls)
                     ,body))
         nil)
      (error (c)
        (values nil (princ-to-string c))))))

(defun diff-test (suite desc params decls body arg-tuples &key allow-opt-err-diff export-sbcl)
  (multiple-value-bind (fn-ref err-ref) (compile-variant params decls body :notinline)
    (multiple-value-bind (fn-safe err-safe) (compile-variant params decls body :safe)
      (multiple-value-bind (fn-def err-def) (compile-variant params decls body :default)
        (multiple-value-bind (fn-sf err-sf) (compile-variant params decls body :safe-fast)
          (multiple-value-bind (fn-opt err-opt) (compile-variant params decls body :opt)
            (when (or err-ref err-safe err-def err-sf err-opt)
              (record-mismatch suite (format nil "COMPILE-ERROR: ~A" desc)
                               (list :ref err-ref :safe err-safe :def err-def :sf err-sf :opt err-opt))
              (return-from diff-test nil))
            (when export-sbcl
              (push (list :desc desc :params params :decls decls :body body
                          :cases (loop for args in arg-tuples
                                       collect (list args (apply #'safe-call fn-ref args))))
                    *sbcl-cases*))
            (dolist (args arg-tuples)
              (incf *total-checks*)
              (let ((r-ref  (apply #'safe-call fn-ref args))
                    (r-safe (apply #'safe-call fn-safe args))
                    (r-def  (apply #'safe-call fn-def args))
                    (r-sf   (apply #'safe-call fn-sf args))
                    (r-opt  (apply #'safe-call fn-opt args)))
                ;; If reference succeeded (:ok ...), ALL modes MUST match exactly!
                (cond
                  ((eq (car r-ref) :ok)
                   (unless (and (equal r-ref r-safe)
                                (equal r-ref r-def)
                                (equal r-ref r-sf)
                                (equal r-ref r-opt))
                     (record-mismatch suite desc
                                      (list :args args
                                            :notinline r-ref
                                            :safe r-safe
                                            :default r-def
                                            :safe-fast r-sf
                                            :opt r-opt))
                     (return-from diff-test nil)))
                  ;; If reference errored (:err ...), safe & safe-fast must also error
                  (t
                   (unless (and (eq (car r-safe) :err)
                                (eq (car r-sf) :err)
                                (or allow-opt-err-diff (eq (car r-opt) :err)))
                     (record-mismatch suite (format nil "ERROR-MISMATCH: ~A" desc)
                                      (list :args args
                                            :notinline r-ref
                                            :safe r-safe
                                            :default r-def
                                            :safe-fast r-sf
                                            :opt r-opt))
                     (return-from diff-test nil))))))))))))

;;; =====================================================================
;;; SUITE A: Bitfields, Shifts, Boole, Division & Seam Integers
;;; =====================================================================

(defparameter *seam-ints*
  (list 0 1 -1 2 -2 3 -3 7 -8 15 -16 31 -32 63 -64 255 -256
        #x7fff #x-8000 #xffff #x-10000
        #x7fffffff #x-80000000 #xffffffff #x-100000000
        (1- (ash 1 59)) (- (ash 1 59)) (ash 1 59)
        (1- most-positive-fixnum) most-positive-fixnum (1+ most-positive-fixnum)
        (1+ most-negative-fixnum) most-negative-fixnum (1- most-negative-fixnum)
        (1- (ash 1 62)) (ash 1 62) (- (ash 1 62))
        (1- (ash 1 63)) (- (ash 1 63)) (ash 1 63) (- (1+ (ash 1 63)))
        (1- (ash 1 64)) (ash 1 64) (- (ash 1 64))
        (1- (ash 1 96)) (- (ash 1 96))
        (1- (ash 1 128)) (- (ash 1 128))))

(defparameter *fixnum-seams*
  (remove-if-not (lambda (x) (typep x 'fixnum)) *seam-ints*))

(defparameter *u64-seams*
  (remove-if-not (lambda (x) (typep x '(unsigned-byte 64))) *seam-ints*))

(defparameter *s64-seams*
  (remove-if-not (lambda (x) (typep x '(signed-byte 64))) *seam-ints*))

(defun run-suite-a ()
  (format t "~%=== Running Suite A: Bitfields, Shifts, Boole & Integer Seams ===~%")
  (finish-output)
  ;; 1. Constant (byte sz pos) across ldb, ldb-test, mask-field, dpb, deposit-field
  (dolist (sz '(0 1 2 7 8 16 31 32 59 60 61 63 64 65 128))
    (dolist (pos '(0 1 7 8 31 32 59 60 61 63 64 65))
      (let ((int-args (mapcar #'list *seam-ints*))
            (fix-args (mapcar #'list *fixnum-seams*))
            (u64-args (mapcar #'list *u64-seams*))
            (s64-args (mapcar #'list *s64-seams*)))
        ;; Untyped ldb / mask-field / ldb-test
        (diff-test :suite-a (format nil "ldb const (~D ~D) untyped" sz pos)
                   '(x) '() `(ldb (byte ,sz ,pos) x) int-args :export-sbcl (member sz '(0 1 60 64)))
        (diff-test :suite-a (format nil "mask-field const (~D ~D) untyped" sz pos)
                   '(x) '() `(mask-field (byte ,sz ,pos) x) int-args)
        (diff-test :suite-a (format nil "ldb-test const (~D ~D) untyped" sz pos)
                   '(x) '() `(ldb-test (byte ,sz ,pos) x) int-args)
        ;; Typed fixnum / u64 / s64 ldb
        (diff-test :suite-a (format nil "ldb const (~D ~D) fixnum" sz pos)
                   '(x) '((type fixnum x)) `(ldb (byte ,sz ,pos) x) fix-args)
        (diff-test :suite-a (format nil "ldb const (~D ~D) u64" sz pos)
                   '(x) '((type (unsigned-byte 64) x)) `(ldb (byte ,sz ,pos) x) u64-args)
        (diff-test :suite-a (format nil "ldb const (~D ~D) s64" sz pos)
                   '(x) '((type (signed-byte 64) x)) `(ldb (byte ,sz ,pos) x) s64-args)
        ;; dpb and deposit-field (subset of pairs for speed)
        (when (and (member sz '(0 1 8 32 60 63 64 65))
                   (member pos '(0 1 31 59 60 63 64)))
          (let ((pairs (loop for x in '(-1 0 1 #x5555aaaa5555aaaa -9223372036854775808
                                        1152921504606846975 -1152921504606846976)
                             nconc (loop for v in '(-1 0 1 #xffffffffffffffff -42)
                                         collect (list v x)))))
            (diff-test :suite-a (format nil "dpb const (~D ~D)" sz pos)
                       '(v x) '() `(dpb v (byte ,sz ,pos) x) pairs :export-sbcl t)
            (diff-test :suite-a (format nil "deposit-field const (~D ~D)" sz pos)
                       '(v x) '() `(deposit-field v (byte ,sz ,pos) x) pairs :export-sbcl t))))))

  ;; 2. Variable (byte sz pos) across ldb, dpb, mask-field, deposit-field
  (let ((triples (loop for sz in '(0 1 8 32 60 63 64 65)
                       nconc (loop for pos in '(0 1 31 59 60 63 64)
                                   nconc (loop for x in (list 0 1 -1 most-positive-fixnum
                                                              most-negative-fixnum
                                                              (1- (ash 1 64)) (- (ash 1 64)))
                                               collect (list sz pos x))))))
    (diff-test :suite-a "ldb variable byte" '(sz pos x) '() '(ldb (byte sz pos) x) triples :export-sbcl t)
    (diff-test :suite-a "mask-field variable byte" '(sz pos x) '() '(mask-field (byte sz pos) x) triples)
    (diff-test :suite-a "dpb variable byte" '(sz pos x) '() '(dpb -1 (byte sz pos) x) triples)
    (diff-test :suite-a "deposit-field variable byte" '(sz pos x) '() '(deposit-field -1 (byte sz pos) x) triples))

  ;; 3. ASH at seam shift counts (constant & variable, typed & untyped)
  (dolist (cnt '(-129 -128 -65 -64 -63 -61 -60 -59 -32 -31 -1 0 1 2 31 32 58 59 60 61 63 64 65 128))
    (diff-test :suite-a (format nil "ash const ~D untyped" cnt)
               '(x) '() `(ash x ,cnt) (mapcar #'list *seam-ints*)
               :export-sbcl (member cnt '(-64 -60 -1 0 1 59 60 63 64)))
    (diff-test :suite-a (format nil "ash const ~D fixnum" cnt)
               '(x) '((type fixnum x)) `(ash x ,cnt) (mapcar #'list *fixnum-seams*))
    (diff-test :suite-a (format nil "ash const ~D s64" cnt)
               '(x) '((type (signed-byte 64) x)) `(ash x ,cnt) (mapcar #'list *s64-seams*))
    (diff-test :suite-a (format nil "ash const ~D u64" cnt)
               '(x) '((type (unsigned-byte 64) x)) `(ash x ,cnt) (mapcar #'list *u64-seams*)))

  ;; Variable shift count including negative bignums!
  (let ((ash-pairs (loop for x in (list 0 1 -1 42 -42 most-positive-fixnum most-negative-fixnum
                                        (ash 1 64) (- (ash 1 64)))
                         nconc (loop for k in (list -128 -65 -64 -63 -60 -59 -1 0 1 31 32 59 60 63 64
                                                    most-negative-fixnum (1- most-negative-fixnum)
                                                    (- (ash 1 70)))
                                     collect (list x k)))))
    (diff-test :suite-a "ash variable shift (incl neg bignum)" '(x k) '() '(ash x k) ash-pairs :export-sbcl t))

  ;; Strength-reduced shift+mask combinations (acode-rewrite-ash / acode-rewrite-logand2)
  (dolist (k '(-64 -63 -60 -32 -1 0 1 3 31 32 59 60 63 64))
    (dolist (m (list 0 1 -1 7 255 #xffffffff #x7fffffffffffffff -8 (- (ash 1 60))))
      (diff-test :suite-a (format nil "(logand (ash x ~D) ~D) fixnum" k m)
                 '(x) '((type fixnum x)) `(logand (ash x ,k) ,m)
                 (mapcar #'list *fixnum-seams*))
      (diff-test :suite-a (format nil "(ash (logand x ~D) ~D) fixnum" m k)
                 '(x) '((type fixnum x)) `(ash (logand x ,m) ,k)
                 (mapcar #'list *fixnum-seams*))))

  ;; 4. LOGBITP, LOGTEST, LOGCOUNT, INTEGER-LENGTH, ISQRT
  (dolist (bit '(0 1 2 31 32 58 59 60 61 62 63 64 65 127 128))
    (diff-test :suite-a (format nil "logbitp const ~D untyped" bit)
               '(x) '() `(logbitp ,bit x) (mapcar #'list *seam-ints*) :export-sbcl (member bit '(0 59 60 63 64)))
    (diff-test :suite-a (format nil "logbitp const ~D fixnum" bit)
               '(x) '((type fixnum x)) `(logbitp ,bit x) (mapcar #'list *fixnum-seams*))
    (diff-test :suite-a (format nil "logbitp const ~D s64" bit)
               '(x) '((type (signed-byte 64) x)) `(logbitp ,bit x) (mapcar #'list *s64-seams*))
    (diff-test :suite-a (format nil "logbitp const ~D u64" bit)
               '(x) '((type (unsigned-byte 64) x)) `(logbitp ,bit x) (mapcar #'list *u64-seams*)))

  (let ((bit-pairs (loop for b in (list 0 1 31 59 60 61 63 64 128 most-positive-fixnum (ash 1 70))
                         nconc (loop for x in *seam-ints* collect (list b x)))))
    (diff-test :suite-a "logbitp variable bit" '(b x) '() '(logbitp b x) bit-pairs :export-sbcl t))

  (diff-test :suite-a "logcount untyped" '(x) '() '(logcount x) (mapcar #'list *seam-ints*) :export-sbcl t)
  (diff-test :suite-a "logcount fixnum" '(x) '((type fixnum x)) '(logcount x) (mapcar #'list *fixnum-seams*))
  (diff-test :suite-a "logcount u64" '(x) '((type (unsigned-byte 64) x)) '(logcount x) (mapcar #'list *u64-seams*))
  (diff-test :suite-a "logcount s64" '(x) '((type (signed-byte 64) x)) '(logcount x) (mapcar #'list *s64-seams*))

  (diff-test :suite-a "integer-length untyped" '(x) '() '(integer-length x) (mapcar #'list *seam-ints*) :export-sbcl t)
  (diff-test :suite-a "integer-length fixnum" '(x) '((type fixnum x)) '(integer-length x) (mapcar #'list *fixnum-seams*))
  (diff-test :suite-a "integer-length u64" '(x) '((type (unsigned-byte 64) x)) '(integer-length x) (mapcar #'list *u64-seams*))
  (diff-test :suite-a "integer-length s64" '(x) '((type (signed-byte 64) x)) '(integer-length x) (mapcar #'list *s64-seams*))

  (let ((nonneg (mapcar #'list (remove-if #'minusp *seam-ints*))))
    (diff-test :suite-a "isqrt nonneg" '(x) '() '(isqrt x) nonneg :export-sbcl t))

  ;; 5. All 16 BOOLE operations + bitwise complement ops
  (let ((int-Sample (list 0 1 -1 42 -42 #x5555555555555555 most-positive-fixnum
                          most-negative-fixnum (ash 1 63) (- (ash 1 63)) (1- (ash 1 65))))
        (fix-Sample (list 0 1 -1 42 -42 most-positive-fixnum most-negative-fixnum)))
    (let ((pairs (loop for a in int-Sample nconc (loop for b in int-Sample collect (list a b))))
          (fpairs (loop for a in fix-Sample nconc (loop for b in fix-Sample collect (list a b)))))
      (dolist (bop (list boole-clr boole-set boole-1 boole-2 boole-c1 boole-c2
                         boole-and boole-ior boole-xor boole-eqv boole-nand boole-nor
                         boole-andc1 boole-andc2 boole-orc1 boole-orc2))
        (diff-test :suite-a (format nil "boole const ~D untyped" bop)
                   '(a b) '() `(boole ,bop a b) pairs :export-sbcl t)
        (diff-test :suite-a (format nil "boole const ~D fixnum" bop)
                   '(a b) '((type fixnum a b)) `(boole ,bop a b) fpairs)
        (diff-test :suite-a (format nil "boole var ~D" bop)
                   '(op a b) '() '(boole op a b)
                   (mapcar (lambda (p) (cons bop p)) fpairs)))
      (dolist (op '(logand logior logxor logeqv lognand lognor logandc1 logandc2 logorc1 logorc2 logtest gcd lcm))
        (diff-test :suite-a (format nil "~A untyped" op) '(a b) '() `(,op a b) pairs :export-sbcl t)
        (diff-test :suite-a (format nil "~A fixnum" op) '(a b) '((type fixnum a b)) `(,op a b) fpairs))))

  ;; 6. Division / Remainder / Power-of-2 constant divisors & variables
  (let ((div-nums (list 0 1 -1 2 -2 7 -7 8 -8 15 -15 16 -16
                        most-positive-fixnum most-negative-fixnum
                        (1+ most-positive-fixnum) (1- most-negative-fixnum)
                        (ash 1 63) (- (ash 1 63)) (1- (ash 1 64))))
        (divisors (list 1 -1 2 -2 3 -3 4 -4 8 -8 16 -16 (ash 1 32) (- (ash 1 32))
                        most-positive-fixnum most-negative-fixnum (ash 1 60) (- (ash 1 60)))))
    (dolist (d '(1 -1 2 -2 4 -4 8 -8 3 -3 7 -7))
      (dolist (op '(truncate floor ceiling round mod rem))
        (diff-test :suite-a (format nil "~A const div ~D untyped" op d)
                   '(x) '() `(,op x ,d) (mapcar #'list div-nums) :export-sbcl t)
        (diff-test :suite-a (format nil "~A const div ~D fixnum" op d)
                   '(x) '((type fixnum x)) `(,op x ,d)
                   (mapcar #'list (remove-if-not (lambda (n) (typep n 'fixnum)) div-nums)))))
    (let ((dpairs (loop for n in div-nums nconc (loop for d in divisors collect (list n d)))))
      (dolist (op '(truncate floor ceiling round mod rem))
        (diff-test :suite-a (format nil "~A variable div" op) '(x d) '() `(,op x d) dpairs :export-sbcl t))))

  ;; 7. EXPT seams
  (let ((epairs (loop for b in '(-3 -2 -1 0 1 2 3 10)
                      nconc (loop for e in '(0 1 2 3 7 8 15 16 31 32 59 60 61 63 64 65)
                                  collect (list b e)))))
    (diff-test :suite-a "expt variable" '(b e) '() '(expt b e) epairs :export-sbcl t)
    (dolist (e '(0 1 2 3 4 8 16 60 63 64))
      (diff-test :suite-a (format nil "expt const exp ~D" e) '(b) '() `(expt b ,e)
                 '((-3) (-2) (-1) (0) (1) (2) (3) (10))))))

;;; =====================================================================
;;; SUITE B: Side-Effecting Expressions Inside Algebraic Identities
;;; =====================================================================

(defun run-suite-b ()
  (format t "~%=== Running Suite B: Side Effects in Algebraic Identities ===~%")
  (finish-output)
  (let ((forms
          '(("(* (incf s x) 0)"           (* (incf s x) 0))
            ("(* 0 (incf s x))"           (* 0 (incf s x)))
            ("(* (the fixnum (incf s x)) 0)" (* (the fixnum (incf s x)) 0))
            ("(* (incf s x) 1)"           (* (incf s x) 1))
            ("(+ (incf s x) 0)"           (+ (incf s x) 0))
            ("(- (incf s x) 0)"           (- (incf s x) 0))
            ("(- (incf s x) (incf s 100))" (- (incf s x) (incf s 100)))
            ("(logand (incf s x) 0)"      (logand (incf s x) 0))
            ("(logand 0 (incf s x))"      (logand 0 (incf s x)))
            ("(logand (the fixnum (incf s x)) 0)" (logand (the fixnum (incf s x)) 0))
            ("(logior (incf s x) -1)"     (logior (incf s x) -1))
            ("(logior -1 (incf s x))"     (logior -1 (incf s x)))
            ("(logandc1 -1 (incf s x))"   (logandc1 -1 (incf s x)))
            ("(logandc2 (incf s x) -1)"   (logandc2 (incf s x) -1))
            ("(logorc1 0 (incf s x))"     (logorc1 0 (incf s x)))
            ("(logorc2 (incf s x) 0)"     (logorc2 (incf s x) 0))
            ("(boole boole-clr (incf s x) (incf s 100))" (boole boole-clr (incf s x) (incf s 100)))
            ("(boole boole-set (incf s x) (incf s 100))" (boole boole-set (incf s x) (incf s 100)))
            ("(boole boole-1 (incf s x) (incf s 100))"   (boole boole-1 (incf s x) (incf s 100)))
            ("(boole boole-2 (incf s x) (incf s 100))"   (boole boole-2 (incf s x) (incf s 100)))
            ("(boole boole-c1 (incf s x) (incf s 100))"  (boole boole-c1 (incf s x) (incf s 100)))
            ("(boole boole-c2 (incf s x) (incf s 100))"  (boole boole-c2 (incf s x) (incf s 100)))
            ("(ash 0 (incf s x))"         (ash 0 (incf s x)))
            ("(ash (incf s x) 0)"         (ash (incf s x) 0))
            ("(ldb (byte 0 0) (incf s x))" (ldb (byte 0 0) (incf s x)))
            ("(ldb (byte 0 5) (incf s x))" (ldb (byte 0 5) (incf s x)))
            ("(ldb-test (byte 0 5) (incf s x))" (ldb-test (byte 0 5) (incf s x)))
            ("(mask-field (byte 0 5) (incf s x))" (mask-field (byte 0 5) (incf s x)))
            ("(dpb (incf s x) (byte 0 5) (incf s 100))" (dpb (incf s x) (byte 0 5) (incf s 100)))
            ("(deposit-field (incf s x) (byte 0 5) (incf s 100))" (deposit-field (incf s x) (byte 0 5) (incf s 100)))
            ("(expt (incf s x) 0)"        (expt (incf s x) 0))
            ("(expt 1 (incf s x))"        (expt 1 (incf s x)))
            ("(setf aref dead value)"     (let ((v (vector 10 20)))
                                            (list (progn (setf (svref v 0) (incf s x)) 0)
                                                  (svref v 0))))
            ;; Also test type errors on folded forms at safe modes!
            ("(* bad 0) typecheck"        (* x 0))
            ("(logand bad 0) typecheck"   (logand x 0))
            ("(logior bad -1) typecheck"  (logior x -1))
            ("(ash 0 bad) typecheck"      (ash 0 x))
            ("(ldb (byte 0 3) bad) typecheck" (ldb (byte 0 3) x))
            ("(dpb bad (byte 0 3) 0) typecheck" (dpb x (byte 0 3) 0)))))
    (dolist (entry forms)
      (destructuring-bind (name expr) entry
        (if (search "typecheck" name)
            (diff-test :suite-b name '(x) '() expr
                       '((0) (42) (-7) (:not-a-number) ("bad") (3.5d0))
                       :allow-opt-err-diff t)
            (diff-test :suite-b name '(x) '((type fixnum x))
                       `(let ((s 10))
                          (declare (type fixnum s))
                          (let ((res ,expr))
                            (list res s)))
                       '((0) (1) (-5) (42))
                       :export-sbcl t))))))

;;; =====================================================================
;;; SUITE C: Multiple-Value Contexts & Algebraic Rewrites
;;; =====================================================================

(defun run-suite-c ()
  (format t "~%=== Running Suite C: Multiple-Value Contexts ===~%")
  (finish-output)
  ;; Note: Avoid the 13 known CCL-3 require-type operators on statically typed args at safety 0
  ;; and unary truncate/floor/round/ceiling. Test OTHER operators & contexts!
  (let ((mv-forms
          '(("ldb byte 0 on (values x y)"
             (ldb (byte 0 3) (values x y)))
            ("ldb byte 8 on (values x y)"
             (ldb (byte 8 0) (values x y)))
            ("mask-field byte 0 on (values x y)"
             (mask-field (byte 0 3) (values x y)))
            ("dpb byte 0 on (values x y)"
             (dpb (values x y) (byte 0 3) 7))
            ("dpb byte 0 target (values x y)"
             (dpb 1 (byte 0 3) (values x y)))
            ("deposit-field byte 0 target (values x y)"
             (deposit-field 1 (byte 0 3) (values x y)))
            ("boole-1 on (values x y)"
             (boole boole-1 (values x y) 99))
            ("boole-2 on (values x y)"
             (boole boole-2 99 (values x y)))
            ("boole-clr on (values x y)"
             (boole boole-clr (values x y) 99))
            ("(/ (* 3 (values x y)) 3)"
             (/ (* 3 (values x y)) 3))
            ("(/ (* 6 (values x y)) 3)"
             (/ (* 6 (values x y)) 3))
            ("(expt (values x y) 1)"
             (expt (values x y) 1))
            ("(expt (values x y) 0)"
             (expt (values x y) 0))
            ("(gcd (values x y) 0)"
             (gcd (values x y) 0))
            ("(lcm (values x y) 1)"
             (lcm (values x y) 1))
            ("nth-value const 0"
             (nth-value 0 (truncate x y)))
            ("nth-value const 1"
             (nth-value 1 (truncate x y)))
            ("nth-value const 2"
             (nth-value 2 (truncate x y)))
            ("nth-value var n"
             (list (nth-value 0 (values x y))
                   (nth-value 1 (values x y))
                   (nth-value 2 (values x y))))
            ("mv-prog1 around gc/call"
             (multiple-value-prog1 (values x y (+ x y)) (identity (* x y))))
            ("mv-call with two mv producers"
             (multiple-value-call #'list (truncate x y) (values) (floor x y)))
            ("if tail mv"
             (if (> x 0) (truncate x y) (floor x y)))
            ("or non-last vs last mv"
             (list (multiple-value-list (or (values nil x) (values y x)))
                   (multiple-value-list (or (values x y) (values y x)))))
            ("prog1 primary value only"
             (prog1 (values x y) (+ x 1)))
            ("catch/throw mv"
             (catch 'tag (if (< x 0) (throw 'tag (values y x 99)) (values x y)))))))
    (dolist (entry mv-forms)
      (destructuring-bind (name expr) entry
        (diff-test :suite-c (concatenate 'string "Untyped MV: " name)
                   '(x y) '() `(multiple-value-list ,expr)
                   '((10 3) (-10 3) (0 5) (7 -2))
                   :export-sbcl t)
        (diff-test :suite-c (concatenate 'string "Typed fixnum MV: " name)
                   '(x y) '((type fixnum x y)) `(multiple-value-list ,expr)
                   '((10 3) (-10 3) (0 5) (7 -2)))))))

;;; =====================================================================
;;; SUITE D: Specialized Arrays (1D/2D/3D), Register Pressure, Floats & Strings
;;; =====================================================================

(defun run-suite-d ()
  (format t "~%=== Running Suite D: Specialized Arrays (1D/2D/3D), Floats & Strings ===~%")
  (finish-output)
  ;; 1. 1D specialized vectors: read & write roundtrips
  (dolist (spec '((t                  (a :b 99 -1))
                  (bit                (0 1 1 0))
                  ((unsigned-byte 8)  (0 1 127 255))
                  ((signed-byte 8)    (-128 -1 0 127))
                  ((unsigned-byte 16) (0 1 #x7fff #xffff))
                  ((signed-byte 16)   (#x-8000 -1 0 #x7fff))
                  ((unsigned-byte 32) (0 1 #x7fffffff #xffffffff))
                  ((signed-byte 32)   (#x-80000000 -1 0 #x7fffffff))
                  ((unsigned-byte 64) (0 1 #x7fffffffffffffff #xffffffffffffffff))
                  ((signed-byte 64)   (#x-8000000000000000 -1 0 #x7fffffffffffffff))
                  (fixnum             (-1152921504606846976 -1 0 1152921504606846975))
                  (single-float       (0.0f0 -0.0f0 1.5f0 -3.25f0))
                  (double-float       (0.0d0 -0.0d0 1.5d0 -3.25d0))
                  ((complex single-float) (#c(1.0f0 -2.0f0) #c(0.0f0 -0.0f0) #c(-3.5f0 4.0f0) #c(0.0f0 0.0f0)))
                  ((complex double-float) (#c(1.0d0 -2.0d0) #c(0.0d0 -0.0d0) #c(-3.5d0 4.0d0) #c(0.0d0 0.0d0)))
                  (character          (#\a #\Z #\0 #\λ))))
    (destructuring-bind (etype vals) spec
      (diff-test :suite-d (format nil "1D simple-array ~S setf/aref" etype)
                 '(i v) `((type fixnum i))
                 `(let ((a (make-array 4 :element-type ',etype
                                         :initial-element ',(first vals))))
                    (declare (type (simple-array ,etype (4)) a))
                    (let ((ret (setf (aref a i) v)))
                      (list ret (aref a 0) (aref a 1) (aref a 2) (aref a 3))))
                 (loop for idx from 0 below 4
                       for val in vals
                       collect (list idx val)))
      ;; Displaced non-simple array!
      (diff-test :suite-d (format nil "1D displaced array ~S setf/aref" etype)
                 '(i v) `((type fixnum i))
                 `(let* ((base (make-array 8 :element-type ',etype
                                             :initial-element ',(first vals)))
                         (a (make-array 4 :element-type ',etype
                                          :displaced-to base
                                          :displaced-index-offset 2)))
                    (declare (type (array ,etype (4)) a))
                    (let ((ret (setf (aref a i) v)))
                      (list ret (aref a i) (aref base (+ i 2)))))
                 (loop for idx from 0 below 4
                       for val in vals
                       collect (list idx val)))))

  ;; 2. 2D and 3D arrays with register-pressured subexpressions!
  (dolist (etype '(t fixnum (unsigned-byte 8) (signed-byte 32) (unsigned-byte 64) double-float bit))
    (let ((zero (cond ((eq etype 'double-float) 0.0d0)
                      (t 0)))
          (one  (cond ((eq etype 'double-float) 1.0d0)
                      (t 1))))
      ;; 2D setf aref with arr & side passed as args (triggers arm642-four-untargeted-reg-forms!)
      (diff-test :suite-d (format nil "2D simple-array ~S setf reg-pressure" etype)
                 '(fn i j val) `((type fixnum i j))
                 `(flet ((do-set (arr side fn i j val)
                           (declare (type (simple-array ,etype (2 3)) arr))
                           (setf (aref arr (funcall fn i) j)
                                 (setf (svref side j) val))))
                    (declare (notinline do-set))
                    (let ((arr (make-array '(2 3) :element-type ',etype :initial-element ,zero))
                          (side (vector ,zero ,zero ,zero)))
                      (do-set arr side fn i j val)
                      (list (aref arr 0 0) (aref arr 0 1) (aref arr 0 2)
                            (aref arr 1 0) (aref arr 1 1) (aref arr 1 2)
                            (svref side j))))
                 (list (list #'identity 0 1 one)
                       (list #'identity 0 2 one)
                       (list #'identity 1 0 one)
                       (list #'identity 1 2 one)))
      ;; 3D aref read with register-pressured subexpressions!
      (diff-test :suite-d (format nil "3D simple-array ~S aref reg-pressure" etype)
                 '(fn i j) `((type fixnum i j))
                 `(flet ((do-get (arr side2 fn i j)
                           (declare (type (simple-array ,etype (2 2 2)) arr)
                                    (type (simple-array fixnum (2 2)) side2))
                           (aref arr (funcall fn i) j (aref side2 j 0))))
                    (declare (notinline do-get))
                    (let ((arr (make-array '(2 2 2) :element-type ',etype :initial-element ,zero))
                          (side2 (make-array '(2 2) :element-type 'fixnum :initial-contents '((0 0) (1 1)))))
                      (setf (aref arr 0 1 1) ,one)
                      (do-get arr side2 fn i j)))
                 (list (list #'identity 0 1)
                       (list #'identity 0 0)))))

  ;; 3. Float algebraic rewrites & IEEE-754 edge cases
  (let ((dvals (list 0.0d0 -0.0d0 1.0d0 -1.0d0 0.5d0 -0.5d0
                     most-positive-double-float most-negative-double-float
                     least-positive-double-float least-negative-double-float)))
    (diff-test :suite-d "float (/ (* 3 x) 3)" '(x) '()
               '(/ (* 3 x) 3) (mapcar #'list dvals) :export-sbcl t)
    (diff-test :suite-d "float (/ (* 0 x) -3)" '(x) '()
               '(/ (* 0 x) -3) (mapcar #'list dvals) :export-sbcl t)
    (diff-test :suite-d "float (* x 1.0d0) signed zero" '(x) '((type double-float x))
               '(* x 1.0d0) (mapcar #'list dvals) :export-sbcl t)
    (diff-test :suite-d "float (+ x 0.0d0) signed zero" '(x) '((type double-float x))
               '(+ x 0.0d0) (mapcar #'list dvals) :export-sbcl t)
    (diff-test :suite-d "float (- x) signed zero" '(x) '((type double-float x))
               '(- x) (mapcar #'list dvals) :export-sbcl t))

  ;; 4. User INLINE functions at (safety 3) (space 0)!
  (let ((helper-sym (gensym "INLINE-HELPER-")))
    (proclaim `(inline ,helper-sym))
    (setf (symbol-function helper-sym)
          (compile nil `(lambda (v idx)
                          (declare (optimize (safety 3)))
                          (svref v idx))))
    ;; Also define via eval so compiler records inline expansion!
    (eval `(progn
             (declaim (inline ,helper-sym))
             (defun ,helper-sym (v idx)
               (svref v idx))))
    (diff-test :suite-d "user defun inline bounds check at safety 3"
               '(v idx) '()
               `(,helper-sym v idx)
               (list (list (vector :a :b) 0)
                     (list (vector :a :b) 5)
                     (list :not-a-vec 0)))
    ;; Local flet inline!
    (diff-test :suite-d "flet inline type/bounds check at safety 3"
               '(v idx) '()
               '(flet ((h (a i) (svref a i)))
                  (declare (inline h))
                  (h v idx))
               (list (list (vector :a :b) 0)
                     (list (vector :a :b) 5)
                     (list :not-a-vec 0)))))

;;; =====================================================================
;;; SUITE E: Random Expression Tree Differential Fuzzing (300 functions)
;;; =====================================================================

(defvar *rng-state* 123456789)
(defun rng (n)
  (setf *rng-state* (ldb (byte 60 0) (+ (* *rng-state* 6364136223846793005) 1442695040888963407)))
  (mod *rng-state* n))

(defun rng-elt (seq)
  (elt seq (rng (length seq))))

(defun gen-rand-int-expr (depth vars)
  (if (<= depth 0)
      (if (= (rng 2) 0)
          (rng-elt vars)
          (rng-elt (list 0 1 -1 2 -2 7 -8 31 32 59 60 63 64 255 -256
                         most-positive-fixnum most-negative-fixnum
                         (ash 1 63) (- (ash 1 63)))))
      (case (rng 18)
        (0 `(+ ,(gen-rand-int-expr (1- depth) vars) ,(gen-rand-int-expr (1- depth) vars)))
        (1 `(- ,(gen-rand-int-expr (1- depth) vars) ,(gen-rand-int-expr (1- depth) vars)))
        (2 `(* ,(gen-rand-int-expr (1- depth) vars) ,(rng-elt '(-3 -2 -1 0 1 2 3 4 8))))
        (3 `(logand ,(gen-rand-int-expr (1- depth) vars) ,(gen-rand-int-expr (1- depth) vars)))
        (4 `(logior ,(gen-rand-int-expr (1- depth) vars) ,(gen-rand-int-expr (1- depth) vars)))
        (5 `(logxor ,(gen-rand-int-expr (1- depth) vars) ,(gen-rand-int-expr (1- depth) vars)))
        (6 `(lognot ,(gen-rand-int-expr (1- depth) vars)))
        (7 `(,(rng-elt '(logeqv lognand lognor logandc1 logandc2 logorc1 logorc2))
             ,(gen-rand-int-expr (1- depth) vars)
             ,(gen-rand-int-expr (1- depth) vars)))
        (8 `(ash ,(gen-rand-int-expr (1- depth) vars)
                 ,(rng-elt '(-65 -64 -63 -60 -32 -1 0 1 2 7 31 32 59 60 63 64))))
        (9 `(ldb (byte ,(rng-elt '(0 1 4 8 16 32 59 60 63 64 65))
                       ,(rng-elt '(0 1 7 16 31 32 59 60 63 64)))
                 ,(gen-rand-int-expr (1- depth) vars)))
        (10 `(dpb ,(gen-rand-int-expr (1- depth) vars)
                  (byte ,(rng-elt '(0 1 4 8 32 60 64))
                        ,(rng-elt '(0 1 8 31 59 60 63)))
                  ,(gen-rand-int-expr (1- depth) vars)))
        (11 `(mask-field (byte ,(rng-elt '(0 1 8 32 60 64))
                               ,(rng-elt '(0 1 16 59 60 63)))
                         ,(gen-rand-int-expr (1- depth) vars)))
        (12 `(deposit-field ,(gen-rand-int-expr (1- depth) vars)
                            (byte ,(rng-elt '(0 1 8 32 60 64))
                                  ,(rng-elt '(0 1 16 59 60 63)))
                            ,(gen-rand-int-expr (1- depth) vars)))
        (13 `(boole ,(rng-elt (list boole-clr boole-set boole-1 boole-2 boole-c1 boole-c2
                                    boole-and boole-ior boole-xor boole-eqv boole-nand boole-nor
                                    boole-andc1 boole-andc2 boole-orc1 boole-orc2))
                    ,(gen-rand-int-expr (1- depth) vars)
                    ,(gen-rand-int-expr (1- depth) vars)))
        (14 `(,(rng-elt '(logcount integer-length abs))
              ,(gen-rand-int-expr (1- depth) vars)))
        (15 `(if (logbitp ,(rng-elt '(0 1 31 59 60 63 64)) ,(gen-rand-int-expr (1- depth) vars))
                 ,(gen-rand-int-expr (1- depth) vars)
                 ,(gen-rand-int-expr (1- depth) vars)))
        (16 `(,(rng-elt '(mod rem truncate floor ceiling round))
              ,(gen-rand-int-expr (1- depth) vars)
              ,(rng-elt '(-8 -7 -4 -3 -2 -1 1 2 3 4 7 8 64 -64))))
        (17 `(let ((t1 ,(gen-rand-int-expr (1- depth) vars)))
               (,(rng-elt '(+ - logxor logand))
                t1
                ,(gen-rand-int-expr (1- depth) (cons 't1 vars))))))))

(defun run-suite-e (&optional (n-funcs 300))
  (format t "~%=== Running Suite E: ~D Random Expression Trees ===~%" n-funcs)
  (finish-output)
  (let ((input-tuples
          (list (list 0 1 -1)
                (list 42 -99 7)
                (list most-positive-fixnum most-negative-fixnum 0)
                (list (1- (ash 1 63)) (- (ash 1 63)) -1)
                (list (1- (ash 1 64)) (- (ash 1 64)) #x5555aaaa5555aaaa))))
    (dotimes (i n-funcs)
      (let ((expr (gen-rand-int-expr 3 '(a b c))))
        (diff-test :suite-e (format nil "rand-tree-~D: ~S" i expr)
                   '(a b c) '((ignorable a b c)) `(multiple-value-list ,expr)
                   input-tuples
                   :export-sbcl (< i 60))))))

(defun dump-sbcl-cases (path)
  (with-open-file (out path :direction :output :if-exists :supersede)
    (with-standard-io-syntax
      (let ((*print-readably* t)
            (*print-circle* nil))
        (prin1 (reverse *sbcl-cases*) out)
        (terpri out)))))

(defun run-all ()
  (setf *mismatches* nil
        *total-checks* 0
        *sbcl-cases* nil
        *rng-state* 123456789)
  (run-suite-a)
  (run-suite-b)
  (run-suite-c)
  (run-suite-d)
  (run-suite-e 300)
  (dump-sbcl-cases "/Users/ember/dev/compiler-audit/hunts/ccl-codegen/sbcl_vectors.sexp")
  (format t "~%========================================~%")
  (format t "Total differential checks run: ~D~%" *total-checks*)
  (format t "Total mismatches found:        ~D~%" (length *mismatches*))
  (format t "Exported SBCL vector suites:   ~D~%" (length *sbcl-cases*))
  (format t "========================================~%")
  (dolist (m (reverse *mismatches*))
    (format t "  * [~A] ~A~%" (getf m :suite) (getf m :desc)))
  (finish-output))

(run-all)
