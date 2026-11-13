;; Probe I:
;;  I1: select-tagging bug shape (017564a7a) — value level.
;;  I2: comparisons mixing unsigned words with negative constants / signed derivations.
;;  I3: constraint narrowing across if + raw-word ops in the narrowed branch.
(load (merge-pathnames "harness.lisp" *load-truename*))

;; I1: from the fix's own test
(format t "=== I1 select-tagging shapes ===~%")
(flet ((drive (name src)
         (handler-case
             (let* ((f (quiet-compile nil src))
                    (g (quiet-compile nil
                        ;; rebuild with notinline by string surgery is fragile;
                        ;; instead compare against a generic identity-based evaluator
                        nil)))
               (declare (ignorable f g))
               ;; run f on fixed args and compare with FUNCALL-based reference
               (format t "  ~a compiled~%" name))
           (error (e) (format t "  ~a ERR: ~a~%" name e)))))
  (declare (ignorable #'drive)))

;; direct value comparison, manual args
(flet ((cmp2 (name src ref-src args)
         (handler-case
             (let ((f (quiet-compile nil src))
                   (g (quiet-compile nil ref-src)))
               (let ((args2 (mapcar (lambda (x)
                                      (if (arrayp x) (copy-seq x) x))
                                    args)))
                 (let ((r1 (norm-result (multiple-value-list (ignore-errors (apply f args)))))
                       (r2 (norm-result (multiple-value-list (ignore-errors (apply g args2))))))
                   (unless (equalp r1 r2)
                     (incf *fails*)
                     (format t "DIVERGE ~a args=~s inline=~s ref=~s~%" name args r1 r2)))))
           (error (e) (format t "ERR ~a: ~a~%" name e)))))
  (let ((b32 (make-array 20 :element-type '(unsigned-byte 32)
                          :initial-contents (loop for i below 20 collect (+ 100 i))))
        (b64 (make-array 20 :element-type '(unsigned-byte 64)
                          :initial-contents (loop for i below 20 collect (+ 100 i))))
        (bs8 (make-array 20 :element-type '(signed-byte 64)
                          :initial-contents (loop for i below 20 collect (- 100 i))))
        (bf (make-array 20 :initial-contents (loop for i below 20 collect (* i 3)))))
    (declare (ignorable bf))
    ;; I1a: (setf (aref b 0) (logxor (aref b 0) a)), a fixnum, b u32
    (cmp2 'I1a-logxor-u32
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 32) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (setf (aref b 0) (logxor (aref b 0) a))
            (aref b 0))
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 32) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (locally (declare (notinline logxor))
              (setf (aref b 0) (logxor (aref b 0) a))
              (aref b 0)))
          (list 5 (copy-seq b32)))
    ;; I1b: logand variant
    (cmp2 'I1b-logand-u32
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 32) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (setf (aref b 0) (logand (aref b 0) a))
            (aref b 0))
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 32) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (locally (declare (notinline logand))
              (setf (aref b 0) (logand (aref b 0) a))
              (aref b 0)))
          (list -3 (copy-seq b32)))
    ;; I1c: logior variant, u64
    (cmp2 'I1c-logior-u64
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 64) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (setf (aref b 0) (logior (aref b 0) a))
            (aref b 0))
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (unsigned-byte 64) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (locally (declare (notinline logior))
              (setf (aref b 0) (logior (aref b 0) a))
              (aref b 0)))
          (list 4611686018427387903 (copy-seq b64)))
    ;; I1d: + variant with fixnum overflow crossing, s64 array
    (cmp2 'I1d-add-s64
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (signed-byte 64) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (setf (aref b 0) (+ (aref b 0) a))
            (aref b 0))
          '(lambda (a b)
            (declare (fixnum a) ((simple-array (signed-byte 64) (20)) b)
                     (optimize (speed 3) (safety 0)))
            (locally (declare (notinline +))
              (setf (aref b 0) (+ (aref b 0) a))
              (aref b 0)))
          (list 4611686018427387903 (copy-seq bs8)))
    (format t "I1 done, fails=~a~%" *fails*)))

;; I2: mixed signed/unsigned comparisons
(format t "=== I2 mixed comparisons ===~%")
(flet ((cmp1 (name type v src ref-src)
         (when (typep v type)
           (handler-case
               (let ((f (quiet-compile nil src))
                     (g (quiet-compile nil ref-src)))
                 (let ((r1 (norm-result (multiple-value-list (ignore-errors (funcall f v)))))
                       (r2 (norm-result (multiple-value-list (ignore-errors (funcall g v))))))
                   (unless (equalp r1 r2)
                     (incf *fails*)
                     (format t "DIVERGE ~a x=~s inline=~s ref=~s~%" name v r1 r2))))
             (error (e) (format t "ERR ~a: ~a~%" name e))))))
  (dolist (v *u64*)
    (cmp1 'I2a-u<-neg '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (< x -1))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline <)) (< x -1))))
    (cmp1 'I2b-dec<0 '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (< (- x 1) 0))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline < -)) (< (- x 1) 0))))
    (cmp1 'I2c-u>=2^63 '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (>= x 9223372036854775808))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline >=)) (>= x 9223372036854775808))))
    (cmp1 'I2d-u>mpw '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (> x 18446744073709551615))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline >)) (> x 18446744073709551615))))
    (cmp1 'I2e-min-neg '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (min x -1))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline min)) (min x -1))))
    (cmp1 'I2f-logand-neg '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (logand x -2))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline logand)) (logand x -2))))
    (cmp1 'I2g-<-s64const '(unsigned-byte 64) v
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (< x -9223372036854775808))
          '(lambda (x) (declare ((unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline <)) (< x -9223372036854775808))))
    (cmp1 'I2h-s64<-u64max '(signed-byte 64) v
          '(lambda (x) (declare ((signed-byte 64) x) (optimize (speed 3) (safety 0))) (< x 18446744073709551615))
          '(lambda (x) (declare ((signed-byte 64) x) (optimize (speed 3) (safety 0)))
            (locally (declare (notinline <)) (< x 18446744073709551615)))))
  (format t "I2 done, fails=~a~%" *fails*))

;; I3: constraint narrowing across if
(format t "=== I3 narrowing ===~%")
(flet ((cmp1 (name type v src ref-src)
         (when (typep v type)
           (handler-case
               (let ((f (quiet-compile nil src))
                     (g (quiet-compile nil ref-src)))
                 (let ((r1 (norm-result (multiple-value-list (ignore-errors (funcall f v)))))
                       (r2 (norm-result (multiple-value-list (ignore-errors (funcall g v))))))
                   (unless (equalp r1 r2)
                     (incf *fails*)
                     (format t "DIVERGE ~a x=~s inline=~s ref=~s~%" name v r1 r2))))
             (error (e) (format t "ERR ~a: ~a~%" name e))))))
  ;; x integer; if (< x K) then treat as fixnum-safe word op
  (dolist (spec
           '(((< x 4611686018427387903) (integer -4611686018427387904 4611686018427387903))
             ((<= x 4611686018427387903) (integer -4611686018427387904 4611686018427387903))
             ((< x 9223372036854775807) (integer -9223372036854775808 9223372036854775807))
             ((<= x 9223372036854775807) (integer -9223372036854775808 9223372036854775807))
             ((< x 18446744073709551615) (integer 0 18446744073709551615))
             ((<= x 18446744073709551615) (integer 0 18446744073709551615))
             ((typep x '(unsigned-byte 64)) (integer 0 18446744073709551615))
             ((= x 9223372036854775807) (integer -9223372036854775808 9223372036854775807))))
    (destructuring-bind (test type) spec
      (let* ((vals (vals-for type))
             (src `(lambda (x)
                     (declare (type ,type x) (optimize (speed 3) (safety 0)))
                     (if ,test
                         (logand x 18446744073709551615)
                         0)))
             (ref `(lambda (x)
                     (declare (type ,type x) (optimize (speed 3) (safety 0)))
                     (locally (declare (notinline logand < <= = typep))
                       (if ,test
                           (logand x 18446744073709551615)
                           0)))))
        (dolist (v vals)
          (cmp1 'I3a type v src ref))
        ;; also with ash consumer
        (let* ((src2 `(lambda (x)
                        (declare (type ,type x) (optimize (speed 3) (safety 0)))
                        (if ,test (ash x -1) 0)))
               (ref2 `(lambda (x)
                        (declare (type ,type x) (optimize (speed 3) (safety 0)))
                        (locally (declare (notinline ash < <= = typep))
                          (if ,test (ash x -1) 0)))))
          (dolist (v vals)
            (cmp1 'I3b type v src2 ref2)))
        ;; and (+ x 1)
        (let* ((src3 `(lambda (x)
                        (declare (type ,type x) (optimize (speed 3) (safety 0)))
                        (if ,test (+ (* x 2) 1) 0)))
               (ref3 `(lambda (x)
                        (declare (type ,type x) (optimize (speed 3) (safety 0)))
                        (locally (declare (notinline + * < <= = typep))
                          (if ,test (+ (* x 2) 1) 0)))))
          (dolist (v vals)
            (cmp1 'I3c type v src3 ref3))))))
  (format t "I3 done, fails=~a~%" *fails*))
(format t "probe I done, fails=~a~%" *fails*)
