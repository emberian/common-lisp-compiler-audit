;;;; Differential fuzzer for SBCL 2.6.10 srctran, modarith, constraint, constraint-back, float-tran
;;;; Usage: sbcl --script fuzz_sbcl_ir.lisp [num-progs] [seed]

(defvar *num-progs* (or (ignore-errors (parse-integer (second *posix-argv*))) 800))
(defvar *seed* (or (ignore-errors (parse-integer (third *posix-argv*))) 20261113))

(defparameter *rng-state* (make-random-state t))

;;; Simple deterministic PRNG (xorshift64*) so runs are reproducible
(defvar *prng* *seed*)
(defun rnd-u64 ()
  (let ((x (logand *prng* #xFFFFFFFFFFFFFFFF)))
    (setf x (logxor x (ash x -12)))
    (setf x (logxor x (logand (ash x 25) #xFFFFFFFFFFFFFFFF)))
    (setf x (logxor x (ash x -27)))
    (setf *prng* x)
    (logand (* x #x2545F4914F6CDD1D) #xFFFFFFFFFFFFFFFF)))

(defun rnd (n)
  (mod (rnd-u64) n))

(defun pick (seq)
  (elt seq (rnd (length seq))))

(defparameter *all-ops*
  '(+ - * / truncate floor ceiling round mod rem
    ash logand logior logxor lognot logandc1 logandc2 logior logeqv boole
    ldb dpb mask-field deposit-field logbitp logtest logcount integer-length
    gcd lcm isqrt expt abs signum
    complex realpart imagpart conjugate
    char-upcase char-downcase char-equal char= char< char> char-code code-char
    < <= > >= = /= eq eql equal equalp))

(defun deep-same-p (a b)
  (cond
    ((and (numberp a) (numberp b))
     (cond
       ((and (floatp a) (floatp b))
        (cond
          ((and (sb-ext:float-nan-p a) (sb-ext:float-nan-p b)) t)
          ((or (sb-ext:float-nan-p a) (sb-ext:float-nan-p b)) nil)
          (t (and (eql (type-of a) (type-of b))
                  (= a b)
                  (eql (float-sign a) (float-sign b))))))
       ((and (complexp a) (complexp b))
        (and (deep-same-p (realpart a) (realpart b))
             (deep-same-p (imagpart a) (imagpart b))))
       (t (eql a b))))
    ((and (consp a) (consp b))
     (and (deep-same-p (car a) (car b))
          (deep-same-p (cdr a) (cdr b))))
    ((and (vectorp a) (vectorp b) (not (stringp a)) (not (stringp b)))
     (and (= (length a) (length b))
          (loop for i below (length a)
                always (deep-same-p (aref a i) (aref b i)))))
    (t (equal a b))))

(defun eval-safe (fn args)
  (handler-case
      (cons :ok (multiple-value-list (apply fn args)))
    (arithmetic-error (e) (list :arith (type-of e)))
    (type-error (e) (list :type-err (type-of e)))
    (error (e) (list :err (type-of e)))))

(defun same-outcome-p (r1 r2)
  (cond
    ((and (eq (car r1) :ok) (eq (car r2) :ok))
     (deep-same-p (cdr r1) (cdr r2)))
    ((and (not (eq (car r1) :ok)) (not (eq (car r2) :ok)))
     ;; Both errored (exact error class may vary across optimizations only if UB,
     ;; wait: in safe mode, zero-UB shouldn't mismatch value vs error!)
     t)
    (t nil)))

;;; Value pools per type
(defun values-for-type (ty)
  (case ty
    (fixnum (list 0 1 -1 2 -2 7 -7 63 64 -64 most-positive-fixnum most-negative-fixnum
                  (1- most-positive-fixnum) (1+ most-negative-fixnum)
                  #x123456789abcdef0 (- #x123456789abcdef0)))
    (word (list 0 1 2 3 7 8 15 16 31 32 63 64 65 #xFF #xFFFF #xFFFFFFFF
                #x7FFFFFFFFFFFFFFF #x8000000000000000 #xFFFFFFFFFFFFFFFF
                (1- #xFFFFFFFFFFFFFFFF)))
    (signed-word (list 0 1 -1 2 -2 63 -63 64 -64 #x7FFFFFFFFFFFFFFF
                       (- #x8000000000000000) (- #x7FFFFFFFFFFFFFFF)))
    (integer (list 0 1 -1 2 -2 3 -3 5 -5 63 -63 64 -64 65 -65 127 -128
                   most-positive-fixnum most-negative-fixnum
                   #x8000000000000000 (- #x8000000000000000)
                   (expt 2 100) (- (expt 2 100)) (1+ (expt 2 64)) (1- (- (expt 2 64)))))
    (rational (list 0 1 -1 1/2 -1/2 3/2 -3/2 2/3 -2/3 100 -100 (1+ (expt 2 70))))
    (double-float (list 0.0d0 -0.0d0 1.0d0 -1.0d0 2.0d0 -2.0d0 0.5d0 -0.5d0
                        1.5d0 -1.5d0 most-positive-double-float most-negative-double-float
                        least-positive-double-float least-negative-double-float
                        sb-ext:double-float-positive-infinity
                        sb-ext:double-float-negative-infinity
                        (sb-kernel:make-double-float #x7ff80000 1)))
    (single-float (list 0.0f0 -0.0f0 1.0f0 -1.0f0 2.0f0 -2.0f0 0.5f0 -0.5f0
                        1.5f0 -1.5f0 most-positive-single-float most-negative-single-float
                        sb-ext:single-float-positive-infinity
                        sb-ext:single-float-negative-infinity
                        (sb-kernel:make-single-float #x7fc00001)))
    (real (append (values-for-type 'integer)
                  (list 1/2 -1/2 0.0d0 -0.0d0 1.0d0 -1.0d0 1.0f0 -1.0f0
                        1.0000000000000002d0)))
    (complex-double (list #C(0.0d0 0.0d0) #C(-0.0d0 -0.0d0) #C(1.0d0 0.0d0)
                          #C(0.0d0 1.0d0) #C(1.0d0 2.0d0) #C(-1.0d0 -2.0d0)))
    (complex-rat (list #C(0 1) #C(1 2) #C(-1 2) #C(1/2 -3/2)))
    (character (list #\a #\A #\z #\Z #\0 #\9 #\Space #\Newline
                     (code-char 0) (code-char 127) (code-char 223) (code-char 255)
                     (code-char 452) (code-char 453) (code-char 454) (code-char #x03A3)))
    (base-char (list #\a #\A #\z #\Z #\0 #\9 #\Space (code-char 0) (code-char 127)))
    ((integer 0 20) (list 0 1 2 5 10 19 20))
    ((integer -20 20) (list -20 -10 -1 0 1 10 20))
    (t (append (values-for-type 'integer)
               (list 1/2 -1/2 0.0d0 -0.0d0 1.0d0 1.0f0 #\a #\A #C(1 2) #C(1.0d0 0.0d0) nil t)))))

(defun decl-for-type (ty)
  (case ty
    (word '(unsigned-byte 64))
    (signed-word '(signed-byte 64))
    (complex-double '(complex double-float))
    (complex-rat '(complex rational))
    (t ty)))

;;; Sub-family 1: Bitfield / Modular / Shift / Arithmetic random ASTs
(defparameter *int-var-syms* '(x y z))

(defun gen-int-expr (depth)
  (if (or (<= depth 0) (zerop (rnd 3)))
      (pick (append *int-var-syms*
                    (list 0 1 -1 2 -2 3 7 8 15 16 31 32 63 64 65 -63 -64 -65
                          #xFF #xFFFF #xFFFFFFFF #x7FFFFFFFFFFFFFFF #xFFFFFFFFFFFFFFFF)))
      (ecase (rnd 16)
        (0 `(+ ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth))))
        (1 `(- ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth))))
        (2 `(* ,(gen-int-expr (1- depth)) ,(pick '(0 1 -1 2 -2 3 7 16 -16 #x10001))))
        (3 `(logand ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth))))
        (4 `(logior ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth))))
        (5 `(logxor ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth))))
        (6 `(lognot ,(gen-int-expr (1- depth))))
        (7 `(ash ,(gen-int-expr (1- depth)) ,(pick `(0 1 -1 8 -8 32 -32 63 -63 64 -64 (- ,(pick *int-var-syms*))
                                                      (mod ,(pick *int-var-syms*) 70)
                                                      (- (mod ,(pick *int-var-syms*) 70))))))
        (8 `(ldb (byte ,(pick '(0 1 4 8 16 32 63 64 65 (mod (abs x) 66)))
                       ,(pick '(0 1 4 8 32 63 64 (mod (abs y) 66))))
                 ,(gen-int-expr (1- depth))))
        (9 `(dpb ,(gen-int-expr (1- depth))
                 (byte ,(pick '(0 1 4 8 16 32 63 64))
                       ,(pick '(0 1 4 8 32 63 64)))
                 ,(gen-int-expr (1- depth))))
        (10 `(mask-field (byte ,(pick '(0 1 8 32 64)) ,(pick '(0 1 8 32 63 64)))
                         ,(gen-int-expr (1- depth))))
        (11 `(deposit-field ,(gen-int-expr (1- depth))
                            (byte ,(pick '(0 1 8 32 64)) ,(pick '(0 1 8 32 64)))
                            ,(gen-int-expr (1- depth))))
        (12 `(if (logbitp ,(pick '(0 1 31 62 63 64 100 (mod (abs y) 70))) ,(gen-int-expr (1- depth)))
                 ,(gen-int-expr (1- depth))
                 ,(gen-int-expr (1- depth))))
        (13 `(if (logtest ,(gen-int-expr (1- depth)) ,(gen-int-expr (1- depth)))
                 (logcount ,(gen-int-expr (1- depth)))
                 (integer-length ,(gen-int-expr (1- depth)))))
        (14 `(gcd ,(gen-int-expr (1- depth)) ,(pick '(0 1 -1 2 3 6 12 -15 x y))))
        (15 `(truncate ,(gen-int-expr (1- depth)) ,(pick '(1 -1 2 -2 3 -3 7 -7 10 -10 (if (zerop z) 1 z))))))))

;;; Sub-family 2: Constraint propagation / branching / loop / contagion ASTs
(defun gen-branch-cond (vars)
  (let ((v1 (pick vars))
        (v2 (pick (append vars (list 0 1 -1 2 0.0d0 -0.0d0 1.0d0 1.0f0 1/2 #\a #\A)))))
    (ecase (rnd 11)
      (0 `(< ,v1 ,v2))
      (1 `(<= ,v1 ,v2))
      (2 `(> ,v1 ,v2))
      (3 `(>= ,v1 ,v2))
      (4 `(= ,v1 ,v2))
      (5 `(eql ,v1 ,v2))
      (6 `(typep ,v1 ',(pick '(integer fixnum rational real float single-float double-float
                                complex (complex rational) (complex double-float)
                                character base-char (integer 0 10) (integer -5 5)
                                (double-float 0.0d0 10.0d0) (single-float -1.0f0 1.0f0)))))
      (7 `(zerop ,v1))
      (8 `(plusp ,v1))
      (9 `(minusp ,v1))
      (10 `(let ((q (nth-value 1 (truncate (if (integerp ,v1) ,v1 1) ,(pick '(2 3 -3 5))))))
             (,(pick '(eql > <)) q 0))))))

(defun gen-branch-body (vars depth)
  (if (<= depth 0)
      (let ((v1 (pick vars)) (v2 (pick vars)))
        (ecase (rnd 10)
          (0 `(list ,v1 ,v2 (eql ,v1 ,v2) (= ,v1 ,v2)))
          (1 `(list (typep ,v1 'integer) (typep ,v1 'rational) (typep ,v1 'real)
                    (typep ,v1 'float) (typep ,v1 'double-float) (typep ,v1 'single-float)
                    (typep ,v1 'complex)))
          (2 `(list (< ,v1 ,v2) (<= ,v1 ,v2) (> ,v1 ,v2) (>= ,v1 ,v2)))
          (3 `(+ ,v1 ,v2))
          (4 `(- ,v1 ,v2))
          (5 `(* ,v1 ,v2))
          (6 `(if (zerop ,v2) :z (/ ,v1 ,v2)))
          (7 `(if (and (realp ,v1) (realp ,v2))
                  (if (zerop ,v2) :z (multiple-value-list (truncate ,v1 ,v2)))
                  :nonreal))
          (8 `(list (char-equal (if (characterp ,v1) ,v1 #\a)
                                (if (characterp ,v2) ,v2 #\A))
                    (char= (if (characterp ,v1) ,v1 #\a)
                           (if (characterp ,v2) ,v2 #\A))))
          (9 `(list (expt (if (numberp ,v1) ,v1 1) ,(pick '(0 1 2 -1 -2 0.0d0 2.0d0)))
                    (if (and (integerp ,v1) (>= ,v1 0)) (isqrt ,v1) :neg)))))
      `(if (ignore-errors ,(gen-branch-cond vars))
           ,(gen-branch-body vars (1- depth))
           ,(gen-branch-body vars (1- depth)))))

(defun gen-loop-prog (init-type)
  (let* ((limit (pick '(-5 -1 0 1 2 5 10 20)))
         (step (pick '(-3 -2 -1 1 2 3)))
         (cmp (pick '(< <= > >= /= =)))
         (op (pick '(+ -))))
    `(lambda (n)
       (declare (type ,init-type n))
       (let ((i n) (acc 0) (steps 0))
         (loop
           (when (or (>= steps 30) (not (,cmp i ,limit)))
             (return (list i acc (typep i '(integer 0 *)) (< i 0) (= i ,limit) (eql i ,limit))))
           (incf steps)
           (setf acc (+ acc i))
           (setf i (,op i ,step)))))))

(defun wrap-notinline (form)
  `(locally (declare (notinline ,@*all-ops*))
     ,form))

(defun compile-pair (lambda-expr)
  (let* ((opt-expr `(lambda ,(second lambda-expr)
                      (declare (optimize (speed 3) (safety 3)))
                      ,@(cddr lambda-expr)))
         (opt0-expr `(lambda ,(second lambda-expr)
                       (declare (optimize (speed 3) (safety 0)))
                       ,@(cddr lambda-expr)))
         (ni-expr (let ((rest (cddr lambda-expr))
                        (decls nil))
                    (loop while (and rest (consp (car rest)) (eq (caar rest) 'declare))
                          do (push (pop rest) decls))
                    `(lambda ,(second lambda-expr)
                       (declare (optimize (speed 0) (safety 3))
                                (notinline ,@*all-ops*))
                       ,@(nreverse decls)
                       ,@rest))))
    (handler-bind ((warning #'muffle-warning))
      (values (compile nil opt-expr)
              (compile nil opt0-expr)
              (compile nil ni-expr)))))

(defun run-fuzzer ()
  (let ((diffs 0)
        (checks 0)
        (seen-bugs (make-hash-table :test #'equal)))
    (format t "Running SBCL IR differential fuzzer: ~D progs, seed=~D~%" *num-progs* *seed*)
    (loop for p from 1 to *num-progs* do
      (let* ((kind (mod p 4))
             (types (case kind
                      (0 (list (pick '(word signed-word fixnum integer))
                               (pick '(word signed-word fixnum integer))
                               (pick '(word signed-word fixnum integer))))
                      (1 (list (pick '(double-float single-float rational real complex-double complex-rat character base-char t))
                               (pick '(double-float single-float rational real complex-double complex-rat character base-char t))))
                      (2 (list (pick '(double-float single-float rational integer real t))
                               (pick '(double-float single-float rational integer real t))))
                      (3 (list (pick '(fixnum integer (integer -20 20) (integer 0 20)))))))
             (vars (subseq '(x y z) 0 (length types)))
             (lambda-expr
               (case kind
                 (0 `(lambda ,vars
                       (declare ,@(mapcar (lambda (v ty) `(type ,(decl-for-type ty) ,v)) vars types))
                       ,(let ((expr (gen-int-expr (+ 1 (rnd 3)))))
                          (if (zerop (rnd 2))
                              `(logand ,(pick '(#xFF #xFFFF #xFFFFFFFF #xFFFFFFFFFFFFFFFF)) ,expr)
                              expr))))
                 (1 `(lambda ,vars
                       (declare ,@(mapcar (lambda (v ty) `(type ,(decl-for-type ty) ,v)) vars types))
                       ,(gen-branch-body vars (+ 1 (rnd 3)))))
                 (2 `(lambda ,vars
                       (declare ,@(mapcar (lambda (v ty) `(type ,(decl-for-type ty) ,v)) vars types))
                       (let ((a ,(first vars)) (b ,(second vars)))
                         (if (and (numberp a) (numberp b))
                             (list (if (typep (+ a b) 'double-float)
                                       (list :df (typep a 'complex) (typep b 'complex))
                                       (list :not-df (typep a 'complex) (typep b 'complex)))
                                   (if (typep (* a b) 'integer)
                                       (list :int (typep a 'rational) (typep b 'rational))
                                       (list :not-int (typep a 'rational) (typep b 'rational)))
                                   (if (typep (- a b) 'single-float)
                                       (list :sf (typep a 'double-float) (typep b 'double-float))
                                       (list :not-sf (typep a 'double-float) (typep b 'double-float))))
                             :skip))))
                 (3 (gen-loop-prog (first types))))))
        (multiple-value-bind (fn-opt fn-opt0 fn-ni)
            (handler-case (compile-pair lambda-expr)
              (error (e) (declare (ignore e)) (values nil nil nil)))
          (when (and fn-opt fn-opt0 fn-ni)
            (let* ((decl-types (mapcar #'decl-for-type types))
                   (pools (mapcar (lambda (ty dty)
                                    (remove-if-not (lambda (v) (typep v dty))
                                                   (values-for-type ty)))
                                  types decl-types))
                   (n-trials (if (= kind 3) 10 12)))
              (when (every #'identity pools)
                (dotimes (i n-trials)
                  (let* ((args (mapcar #'pick pools))
                         (r-ni (eval-safe fn-ni args))
                         (r-opt (eval-safe fn-opt args))
                         (r-opt0 (eval-safe fn-opt0 args)))
                    (incf checks 2)
                    (unless (and (same-outcome-p r-opt r-ni)
                                 (same-outcome-p r-opt0 r-ni))
                      (incf diffs)
                      (let ((key (list kind (car r-opt) (car r-opt0) (car r-ni))))
                        (when (< (gethash key seen-bugs 0) 5)
                          (incf (gethash key seen-bugs 0))
                          (format t "~&[DIFF #~D prog=~D kind=~D]~%  lambda: ~S~%  args: ~S~%  opt(s3): ~S~%  opt(s0): ~S~%  ni:      ~S~%"
                                  diffs p kind lambda-expr args r-opt r-opt0 r-ni))))))))))))
    (format t "~&DONE: progs=~D checks=~D diffs=~D~%" *num-progs* checks diffs)))

(run-fuzzer)
