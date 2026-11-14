;;;; Targeted Anti-Masking & Consumer-Context Differential Fuzzer for SBCL 2.6.10
;;;; Implements RESEARCH.md Recommendations #7 (no fit-int masking; fixnum/word/s128/bignum seams)
;;;; and #9 (consumer contexts: modular logand/ldb, logbitp, comparisons, multiple values,
;;;; specialized arrays, and 8..20-variable register pressure + loop-back targeting).

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(defparameter *rng* (sb-ext:seed-random-state 20261113))
(defparameter *num-trials*
  (let ((arg (second sb-ext:*posix-argv*)))
    (if arg (parse-integer arg) 1500)))

(defun rint (n) (random n *rng*))
(defun rchoice (seq) (elt seq (rint (length seq))))
(defun rbool (&optional (num 1) (den 2)) (< (rint den) num))

(defparameter *seam-integers*
  (coerce
   (remove-duplicates
    (append
     '(0 1 -1 2 -2 3 -3 7 -7 15 -15 31 -31 32 -32 63 -63 64 -64 65 -65 127 -127 128 -128)
     ;; 32-bit seams
     (loop for k in '(30 31 32 33)
           append (loop for d in '(-2 -1 0 1 2)
                        collect (+ (ash 1 k) d)
                        collect (- (+ (ash 1 k) d))))
     ;; Fixnum (2^61, 2^62), word (2^63, 2^64), bignum (2^65), and s128 (2^126..2^128) seams
     (loop for k in '(60 61 62 63 64 65 95 96 125 126 127 128)
           append (loop for d in '(-3 -2 -1 0 1 2 3)
                        collect (+ (ash 1 k) d)
                        collect (- (+ (ash 1 k) d))))
     '(#x5555555555555555 #xAAAAAAAAAAAAAAAA
       #x8000000000000001 #x7FFFFFFFFFFFFFFE
       #xFFFFFFFFFFFFFFFF #x10000000000000001)))
   'vector))

(defparameter *type-specs*
  '((fixnum             . :fixnum)
    ((unsigned-byte 64) . :u64)
    ((signed-byte 64)   . :s64)
    ((unsigned-byte 32) . :u32)
    ((signed-byte 128)  . :s128)
    ((integer -100000000000000000000 100000000000000000000) . :big)))

(defun sample-for-type (tspec)
  (loop
    (let ((cand (if (rbool 4 5)
                    (rchoice *seam-integers*)
                    (- (rint (ash 1 66)) (ash 1 65)))))
      (when (typep cand tspec)
        (return cand))
      ;; Fallback direct construction if cand wasn't in tspec
      (let ((alt (cond ((eq tspec 'fixnum)
                        (let ((c (rchoice #(-4611686018427387904 -4611686018427387903
                                            -2305843009213693952 -1 0 1
                                            2305843009213693951 4611686018427387902
                                            4611686018427387903))))
                          c))
                       ((equal tspec '(unsigned-byte 64))
                        (ldb (byte 64 0) cand))
                       ((equal tspec '(signed-byte 64))
                        (let ((u (ldb (byte 64 0) cand)))
                          (if (logbitp 63 u) (- u (ash 1 64)) u)))
                       ((equal tspec '(unsigned-byte 32))
                        (ldb (byte 32 0) cand))
                       ((equal tspec '(signed-byte 128))
                        (let ((u (ldb (byte 128 0) cand)))
                          (if (logbitp 127 u) (- u (ash 1 128)) u)))
                       (t (rem cand 100000000000000000000)))))
        (when (typep alt tspec)
          (return alt))))))

(defun safe-shift-expr (val-expr vars)
  (if (rbool 1 2)
      ;; Constant shift across fixnum/word/s128 boundaries
      (let ((sh (- (rint 136) 68)))
        `(ash ,val-expr ,sh))
      ;; Variable shift bounded to [-68, 68] so we don't blow up heap with multi-gigabyte bignums
      ;; while STILL crossing 32, 61, 62, 63, 64, 65, 127, 128 bit boundaries AND using RCX!
      (let ((sv (rchoice vars))
            (lo (- (rint 69)))
            (span (+ 1 (rint 130))))
        `(ash ,val-expr (- (mod (abs ,sv) ,span) ,(- lo))))))

(defun gen-int-expr (vars)
  (let ((a (rchoice vars))
        (b (rchoice vars))
        (c (rchoice vars)))
    (case (rint 20)
      (0 `(+ ,a ,b))
      (1 `(- ,a ,b))
      (2 `(- ,a))
      (3 ;; Bounded product so s128/word*word paths trigger without million-bit bignum blowup
       `(* (logand ,a #xFFFFFFFFFFFFFFFF)
           (- (logand ,b #x1FFFFFFFFFFFFFFFF) #xFFFFFFFFFFFFFFFF)))
      (4 `(logand ,a ,b))
      (5 `(logior ,a ,b))
      (6 `(logxor ,a ,b))
      (7 `(,(rchoice '(logandc1 logandc2 logorc1 logorc2 logeqv lognor)) ,a ,b))
      (8 (safe-shift-expr a vars))
      ;; Consumer contexts (Rec #9): modular 64-bit / 32-bit / fixnum / s128
      (9 `(logand ,(safe-shift-expr `(+ ,a ,b) vars) #xFFFFFFFFFFFFFFFF))
      (10 `(ldb (byte 64 0) (,(rchoice '(+ - logxor logior))
                             ,(safe-shift-expr a vars) ,b)))
      (11 `(logand (* (ldb (byte 64 0) ,a) (ldb (byte 64 0) ,b))
                   #xFFFFFFFFFFFFFFFF))
      ;; Bitfield ops: ldb, dpb, mask-field, deposit-field
      (12 (let ((sz (1+ (rint 65)))
                (pos (rint 66)))
            `(,(rchoice '(ldb mask-field)) (byte ,sz ,pos) ,a)))
      (13 (let ((sz (1+ (rint 65)))
                (pos (rint 66)))
            `(,(rchoice '(dpb deposit-field)) ,a (byte ,sz ,pos) ,b)))
      ;; Dynamic byte specifier!
      (14 `(ldb (byte (1+ (mod (abs ,b) 64)) (mod (abs ,c) 65)) ,a))
      ;; Consumer contexts: logbitp / comparisons / logtest / logcount / integer-length
      (15 `(if (logbitp (mod (abs ,b) 129) ,(safe-shift-expr a vars))
               (logxor ,a -1)
               (logcount (logand ,c #xFFFFFFFFFFFFFFFF))))
      (16 `(if (,(rchoice '(< <= = >= > logtest))
                ,(safe-shift-expr a vars)
                ,b)
               (integer-length ,a)
               (abs ,b)))
      ;; Multiple-value division (floor / ceiling / truncate / round) with safe non-zero divisor!
      (17 (let ((div-op (rchoice '(floor ceiling truncate round))))
            `(multiple-value-bind (q r)
                 (,div-op ,a (let ((d (rem ,b #x100000003)))
                               (if (zerop d) -3 d)))
               (logxor q (* r 3)))))
      ;; ash-inverted / two-word rotate idiom
      (18 `(logior (logand (ash (ldb (byte 64 0) ,a) (mod (abs ,b) 64)) #xFFFFFFFFFFFFFFFF)
                   (ash (ldb (byte 64 0) ,c) (- (mod (abs ,b) 64) 64))))
      ;; Multiple-value catch/throw & multiple-value-call
      (19 `(multiple-value-bind (m0 m1 m2)
               (catch 'mv-tag
                 (if (oddp ,b)
                     (throw 'mv-tag (values ,a (logxor ,b ,c) (- ,c)))
                     (values (logior ,a ,b) ,c (+ ,a 1))))
             (+ m0 (logxor m1 m2)))))))

(defun gen-test-forms ()
  "Returns (values fast-lambda safe-lambda arg-types)."
  (let* ((nargs (+ 4 (rint 5)))        ; 4..8 typed parameters
         (nlive (+ 8 (rint 11)))       ; 8..18 let* bindings -> high register pressure!
         (arg-syms (loop for i below nargs collect (intern (format nil "A~D" i))))
         (arg-types (loop for i below nargs collect (car (rchoice *type-specs*))))
         (let-syms (loop for i below nlive collect (intern (format nil "V~D" i))))
         (avail (copy-list arg-syms))
         (bindings nil))
    (dolist (v let-syms)
      (push `(,v ,(gen-int-expr avail)) bindings)
      (push v avail))
    (setf bindings (nreverse bindings))
    ;; Optional specialized-array + loop-back register-targeting block
    (let* ((use-arrays (rbool 1 2))
           (use-loop (rbool 1 2))
           (v-last1 (first (last let-syms)))
           (v-last2 (or (second ( reverse let-syms)) v-last1))
           (body-core
             `(let* ,bindings
                (declare (ignorable ,@let-syms))
                ,@(when use-loop
                    ;; 2-iteration loop-back mutation targeting same registers!
                    `((dotimes (it 2)
                        (multiple-value-setq (,v-last1 ,v-last2)
                          (truncate (+ ,v-last1 (ash (logand ,v-last2 63) 1))
                                    (if (zerop (logand ,v-last2 7)) -3 5))))))
                ,(if use-arrays
                     `(let ((au64 (make-array 4 :element-type '(unsigned-byte 64) :initial-element 0))
                            (as64 (make-array 4 :element-type '(signed-byte 64) :initial-element 0))
                            (au32 (make-array 4 :element-type '(unsigned-byte 32) :initial-element 0))
                            (abv  (make-array 64 :element-type 'bit :initial-element 0))
                            (adf  (make-array 2 :element-type 'double-float :initial-element 0.0d0)))
                        (setf (aref au64 (mod (abs ,(first arg-syms)) 4))
                              (ldb (byte 64 0) ,v-last1))
                        (setf (aref as64 (mod (abs ,(second arg-syms)) 4))
                              (- (ldb (byte 64 0) ,v-last2)
                                 (if (logbitp 63 ,v-last2) ,(ash 1 64) 0)))
                        (setf (aref au32 (mod (abs ,(third arg-syms)) 4))
                              (ldb (byte 32 0) (+ ,v-last1 ,v-last2)))
                        (setf (sbit abv (mod (abs ,v-last1) 64))
                              (if (logbitp (mod (abs ,v-last2) 64) ,v-last1) 1 0))
                        (setf (aref adf 0)
                              (coerce (ldb (byte 32 0) ,v-last1) 'double-float))
                        ;; Return ALL intermediate bindings (anti-masking Rec #7!) + array contents!
                        (list (list ,@let-syms)
                              (aref au64 0) (aref au64 1) (aref au64 2) (aref au64 3)
                              (aref as64 0) (aref as64 1) (aref as64 2) (aref as64 3)
                              (aref au32 0) (aref au32 1) (aref au32 2) (aref au32 3)
                              (bit abv (mod (abs ,v-last1) 64))
                              (aref adf 0)))
                     `(list ,@let-syms))))
           (fast-lambda
             `(lambda ,arg-syms
                (declare (optimize (speed 3) (safety 0) (debug 0) (compilation-speed 0))
                         ,@(mapcar (lambda (s ty) `(type ,ty ,s)) arg-syms arg-types)
                         (ignorable ,@arg-syms))
                ,body-core))
           (safe-lambda
             `(lambda ,arg-syms
                (declare (optimize (speed 0) (safety 3) (debug 3) (space 0))
                         (ignorable ,@arg-syms))
                ,body-core)))
      (values fast-lambda safe-lambda arg-types))))

(defun same-val-p (x y)
  (cond ((and (integerp x) (integerp y)) (= x y))
        ((and (floatp x) (floatp y))
         (and (eq (type-of x) (type-of y))
              (or (and (sb-ext:float-nan-p x) (sb-ext:float-nan-p y))
                  (eql (sb-kernel:double-float-bits (coerce x 'double-float))
                       (sb-kernel:double-float-bits (coerce y 'double-float))))))
        ((and (consp x) (consp y))
         (and (same-val-p (car x) (car y))
              (same-val-p (cdr x) (cdr y))))
        (t (equal x y))))

(let ((start-internal (get-internal-real-time))
      (total-calls 0)
      (mismatches 0)
      (compile-errors 0))
  (format t "Starting SBCL ~A (~A) anti-masking differential fuzzer for ~D functions...~%"
          (lisp-implementation-version) (machine-type) *num-trials*)
  (finish-output)
  (dotimes (trial *num-trials*)
    (multiple-value-bind (fast-form safe-form arg-types) (gen-test-forms)
      (let ((fn-fast nil)
            (fn-safe nil))
        (handler-case
            (progn
              (setf fn-fast (compile nil fast-form))
              (setf fn-safe (compile nil safe-form)))
          (error (e)
            (incf compile-errors)
            (format t "~%[COMPILE-ERROR trial=~D] ~A~%Form:~%~S~%" trial e fast-form)
            (finish-output)))
        (when (and fn-fast fn-safe)
          ;; Run 6 seam-heavy input vectors per compiled function pair
          (dotimes (iv 6)
            (let ((args (mapcar #'sample-for-type arg-types)))
              ;; Strict UB guard: verify every argument satisfies its declared type!
              (loop for a in args for ty in arg-types
                    do (assert (typep a ty)))
              (incf total-calls)
              (let ((r-fast :uninit)
                    (r-safe :uninit)
                    (err-fast nil)
                    (err-safe nil))
                (handler-case (setf r-fast (apply fn-fast args))
                  (error (e) (setf err-fast e)))
                (handler-case (setf r-safe (apply fn-safe args))
                  (error (e) (setf err-safe e)))
                (cond
                  ((and err-fast (not err-safe))
                   (incf mismatches)
                   (format t "~%[FAST-ERROR-ONLY trial=~D iv=~D] ~A~%Args: ~S~%Types: ~S~%Form:~%~S~%"
                           trial iv err-fast args arg-types fast-form)
                   (finish-output))
                  ((and (not err-fast) (not err-safe) (not (same-val-p r-fast r-safe)))
                   (incf mismatches)
                   (format t "~%[SILENT-MISMATCH! trial=~D iv=~D]~%Args:  ~S~%Types: ~S~%Fast:  ~S~%Safe:  ~S~%Form:~%~S~%"
                           trial iv args arg-types r-fast r-safe fast-form)
                   (finish-output)
                   (return)))))))))
    (when (zerop (mod (1+ trial) 500))
      (format t "  progress: ~D/~D functions (~D calls, ~D mismatches, ~D compile-errors)~%"
              (1+ trial) *num-trials* total-calls mismatches compile-errors)
      (finish-output)))
  (let ((elapsed (/ (- (get-internal-real-time) start-internal)
                    (float internal-time-units-per-second))))
    (format t "DONE on ~A: ~D functions, ~D differential calls in ~,2Fs (~,1F fns/s): mismatches=~D compile-errors=~D~%"
            (machine-type) *num-trials* total-calls elapsed (/ *num-trials* (max elapsed 0.001))
            mismatches compile-errors)))
