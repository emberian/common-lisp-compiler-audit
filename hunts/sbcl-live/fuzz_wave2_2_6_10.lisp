;;;; Wave 2 Differential Fuzzer for SBCL 2.6.10 (arm64 + x86-64):
;;;; Targets &rest source transforms (%rest-ref, %rest-elt, %rest-length, %rest-null,
;;;; %more-arg-values), reverse-values-list ((values-list (reverse ...))),
;;;; complex single/double float register pressure, and SIMD pack constructors.

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(defparameter *rng* (sb-ext:seed-random-state 99887766))
(defparameter *num-trials*
  (let ((arg (second sb-ext:*posix-argv*)))
    (if arg (parse-integer arg) 1000)))

(defun rint (n) (random n *rng*))
(defun rchoice (seq) (elt seq (rint (length seq))))

(declaim (notinline opaque-id))
(defun opaque-id (x) x)

(defun gen-wave2-forms ()
  (let* ((nprefix (+ 4 (rint 8))) ; 4..11 prefix fixnum args
         (nlive   (+ 4 (rint 9))) ; 4..12 live local bindings across &rest / MV / float ops
         (pvars   (loop for i below nprefix collect (intern (format nil "P~D" i))))
         (lvars   (loop for i below nlive collect (intern (format nil "L~D" i))))
         (flavor  (rint 3)))
    (ecase flavor
      ;; Flavor 0: &rest transforms (%rest-ref, %rest-length, %rest-null, %more-arg-values) + reverse-values-list
      (0
       (let* ((idx (rint 4))
              (body
                `(let* ,(loop for v in lvars for i from 0
                              collect `(,v (+ ,(nth (mod i nprefix) pvars) ,(* (1+ i) 7))))
                   (declare (ignorable ,@lvars))
                   (let ((a (if (null r) -1 (length r)))
                         (b (nth ,idx r))
                         (c (car r))
                         (d (cadr r))
                         (e (caddr r))
                         (mv1 (multiple-value-list
                               (multiple-value-prog1
                                   (values-list r)
                                 (opaque-id (list ,@lvars)))))
                         (mv2 (multiple-value-list
                               (values-list (reverse (list ,@(subseq pvars 0 (min 4 nprefix))))))))
                     (list a b c d e mv1 mv2 (list ,@lvars))))))
         (values
          `(lambda (,@pvars &rest r)
             (declare (optimize (speed 3) (safety 0) (debug 0))
                      (type fixnum ,@pvars))
             ,body)
          `(lambda (,@pvars &rest r)
             (declare (optimize (speed 0) (safety 3) (debug 3)))
             ,body)
          :rest
          nprefix)))
      ;; Flavor 1: Complex single-float & complex double-float register pressure
      (1
       (let* ((fvars (subseq pvars 0 4))
              (body
                `(let* ((c0 (complex ,(first fvars) ,(second fvars)))
                        (c1 (complex ,(third fvars) ,(fourth fvars)))
                        ,@(loop for v in lvars for i from 0
                                collect `(,v ,(ecase (mod i 5)
                                                (0 `(+ c0 c1))
                                                (1 `(- c0 c1))
                                                (2 `(* c0 c1))
                                                (3 `(/ c0 ,(third fvars)))
                                                (4 `(complex (imagpart c1) (realpart c0)))))))
                   (list ,@(mapcar (lambda (v) `(list (realpart ,v) (imagpart ,v))) lvars)
                         (= c0 c1)
                         ,(first fvars) ,(second fvars) ,(third fvars) ,(fourth fvars)))))
         (values
          `(lambda ,fvars
             (declare (optimize (speed 3) (safety 0) (debug 0))
                      (type single-float ,@fvars))
             ,body)
          `(lambda ,fvars
             (declare (optimize (speed 0) (safety 3) (debug 3)))
             ,body)
          :csf
          4)))
      ;; Flavor 2: Non-known-buggy SIMD constructors under register pressure
      ;; (%make-simd-pack-double, %make-simd-pack-ub64, %make-simd-pack-ub32)
      (2
       (let* ((uvars (subseq pvars 0 4))
              (body
                `(let* ((p64-a (sb-ext:%make-simd-pack-ub64 ,(first uvars) ,(second uvars)))
                        (p64-b (sb-ext:%make-simd-pack-ub64 ,(third uvars) ,(fourth uvars)))
                        (p32-a (sb-ext:%make-simd-pack-ub32
                                (ldb (byte 32 0) ,(first uvars))
                                (ldb (byte 32 0) ,(second uvars))
                                (ldb (byte 32 0) ,(third uvars))
                                (ldb (byte 32 0) ,(fourth uvars))))
                        (pd-a  (sb-ext:%make-simd-pack-double
                                (coerce (ldb (byte 20 0) ,(first uvars)) 'double-float)
                                (coerce (ldb (byte 20 0) ,(third uvars)) 'double-float))))
                   (prin1-to-string
                    (list p64-a p64-b p32-a pd-a
                          ,(first uvars) ,(second uvars) ,(third uvars) ,(fourth uvars))))))
         (values
          `(lambda ,uvars
             (declare (optimize (speed 3) (safety 0) (debug 0))
                      (type (unsigned-byte 64) ,@uvars))
             ,body)
          `(lambda ,uvars
             (declare (optimize (speed 0) (safety 3) (debug 3)))
             ,body)
          :simd
          4))))))

(defun approx-same-p (x y)
  (cond ((and (floatp x) (floatp y))
         (or (and (sb-ext:float-nan-p x) (sb-ext:float-nan-p y))
             (<= (abs (- x y)) (* 1f-5 (max 1.0f0 (abs x) (abs y))))))
        ((and (consp x) (consp y))
         (and (approx-same-p (car x) (car y))
              (approx-same-p (cdr x) (cdr y))))
        (t (equal x y))))

(let ((t0 (get-internal-real-time))
      (calls 0)
      (mismatches 0))
  (format t "Starting Wave 2 fuzzer on ~A (~D functions)...~%" (machine-type) *num-trials*)
  (dotimes (trial *num-trials*)
    (multiple-value-bind (fast-f safe-f kind nargs) (gen-wave2-forms)
      (let ((fn-fast (compile nil fast-f))
            (fn-safe (compile nil safe-f)))
        (dotimes (iv 4)
          (let ((args (ecase kind
                        (:rest (append (loop for i below nargs collect (- (rint 2000) 1000))
                                       (loop repeat (rint 6) collect (rint 999))))
                        (:csf  (list (+ 1.5f0 (rint 20)) (- -3.25f0 (rint 20))
                                     (+ 2.0f0 (rint 15)) (+ 0.5f0 (rint 15))))
                        (:simd (loop repeat 4 collect (ldb (byte 64 0)
                                                           (logior (ash (1+ (rint #xFFFFFF)) 32)
                                                                   (1+ (rint #xFFFFFF)))))))))
            (incf calls)
            (let ((rf (apply fn-fast args))
                  (rs (apply fn-safe args)))
              (unless (approx-same-p rf rs)
                (incf mismatches)
                (format t "~%[WAVE2-MISMATCH! trial=~D kind=~S]~%Args: ~S~%Fast: ~S~%Safe: ~S~%Form:~%~S~%"
                        trial kind args rf rs fast-f)
                (return))))))))
  (let ((dt (/ (- (get-internal-real-time) t0) (float internal-time-units-per-second))))
    (format t "Wave 2 DONE on ~A: ~D functions, ~D calls in ~,2Fs (~,1F fns/s): mismatches=~D~%"
            (machine-type) *num-trials* calls dt (/ *num-trials* (max dt 0.001)) mismatches)))
