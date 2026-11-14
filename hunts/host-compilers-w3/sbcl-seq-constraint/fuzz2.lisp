;;;; Differential fuzzer Part 2:
;;;;   - seqtran derive-type downstream consumers, merge/sort/every/some/concatenate/string-case
;;;;   - array-tran multi-dim/displaced/row-major/bounds/equal/equalp/vector-push
;;;;   - constraint-back (+,-,*,/,truncate,car,cdr,array-rank), tagbody widening, float open bounds

(defpackage #:sbcl-fuzz2
  (:use #:cl)
  (:export #:main))

(in-package #:sbcl-fuzz2)

(defvar *seed* 987654321)

(defun next-u31 ()
  (setf *seed* (logand (+ (* *seed* 1103515245) 12345) #x7fffffff))
  (ash *seed* -1))

(defun rand-int (n) (mod (next-u31) n))
(defun rand-range (lo hi) (+ lo (rand-int (1+ (- hi lo)))))
(defun rand-pick (vec) (elt vec (rand-int (length vec))))
(defun rand-bool (&optional (num 1) (den 2)) (< (rand-int den) num))

(defun canon (x)
  (cond
    ((null x) "NIL")
    ((eq x t) "T")
    ((symbolp x) (format nil "~a" (symbol-name x)))
    ((integerp x) (format nil "~d" x))
    ((rationalp x) (format nil "~d/~d" (numerator x) (denominator x)))
    ((floatp x)
     (if (zerop x)
         (if (minusp (float-sign x)) "-0.0" "+0.0")
         (format nil "~,6e" x)))
    ((characterp x) (format nil "#\\u~x" (char-code x)))
    ((bit-vector-p x)
     (with-output-to-string (s)
       (write-string "#*" s)
       (dotimes (i (length x)) (write-char (if (zerop (bit x i)) #\0 #\1) s))))
    ((stringp x)
     (with-output-to-string (s)
       (write-char #\" s)
       (dotimes (i (length x)) (format s "~x," (char-code (char x i))))
       (write-char #\" s)))
    ((consp x)
     (with-output-to-string (s)
       (write-char #\( s)
       (loop for cur = x then (cdr cur)
             for first = t then nil
             while (consp cur)
             do (unless first (write-char #\Space s))
                (write-string (canon (car cur)) s)
             finally (when cur (write-string " . " s) (write-string (canon cur) s)))
       (write-char #\) s)))
    ((vectorp x)
     (with-output-to-string (s)
       (write-string "#(" s)
       (dotimes (i (length x))
         (when (> i 0) (write-char #\Space s))
         (write-string (canon (aref x i)) s))
       (write-char #\) s)))
    ((arrayp x)
     (with-output-to-string (s)
       (format s "#A~s(" (array-dimensions x))
       (dotimes (i (array-total-size x))
         (when (> i 0) (write-char #\Space s))
         (write-string (canon (row-major-aref x i)) s))
       (write-char #\) s)))
    (t (format nil "~s" x))))

(defparameter *opt-decls* nil)
(defparameter *use-notinline* nil)
(defparameter *all-ops*
  '(merge sort stable-sort every some notany notevery concatenate coerce make-sequence
    find-if position-if count-if remove-if delete-if substitute-if nsubstitute-if
    find-if-not position-if-not reduce search position find subseq
    string-upcase string-downcase string-capitalize nstring-upcase nstring-downcase
    string-trim string-left-trim string-right-trim char-upcase char-downcase
    equal equalp array-in-bounds-p array-row-major-index row-major-aref aref
    adjust-array vector-push vector-push-extend bit-not array-rank array-dimensions array-total-size))

(defun wrap-compile (params body &optional extra-decls)
  (let ((decls `(,@(when *opt-decls* (list *opt-decls*))
                 #+sbcl (sb-ext:muffle-conditions sb-ext:compiler-note style-warning)
                 ,@(when *use-notinline* (list `(notinline ,@*all-ops*)))
                 ,@extra-decls)))
    (compile nil `(lambda ,params (declare ,@decls) ,body))))

(defparameter *chars*
  #(#\a #\b #\c #\A #\B #\C #\0 #\Space #\- #.(code-char #xe9) #.(code-char #xc9)
    #.(code-char #xdf) #.(code-char #xb5) #.(code-char #x131) #.(code-char #x17f) #.(code-char #x212a)))

(defun mk-vec (len &key fp disp)
  (let* ((ext (if fp (rand-range 0 4) 0))
         (off (if disp (rand-range 1 4) 0))
         (base (make-array (+ len ext off) :initial-element 0)))
    (dotimes (i (length base)) (setf (aref base i) (rand-range -5 8)))
    (cond (disp (make-array len :displaced-to base :displaced-index-offset off))
          (fp (let ((v (make-array (+ len ext) :fill-pointer len :initial-element 0)))
                (dotimes (i (length v)) (setf (aref v i) (aref base i))) v))
          (t base))))

(defun mk-str (len &key base fp disp)
  (let* ((ext (if fp (rand-range 0 4) 0))
         (off (if disp (rand-range 1 4) 0))
         (et (if base 'base-char 'character))
         (b (make-array (+ len ext off) :element-type et :initial-element #\a)))
    (dotimes (i (length b))
      (setf (char b i) (if base (aref *chars* (rand-int 9)) (rand-pick *chars*))))
    (cond (disp (make-array len :element-type et :displaced-to b :displaced-index-offset off))
          (fp (let ((s (make-array (+ len ext) :element-type et :fill-pointer len :initial-element #\a)))
                (dotimes (i (length s)) (setf (char s i) (char b i))) s))
          (t b))))

(defun mk-seq (len)
  (ecase (rand-int 5)
    (0 (loop repeat len collect (rand-range -5 8)))
    (1 (mk-vec len))
    (2 (mk-vec len :fp t))
    (3 (mk-vec len :disp t))
    (4 (let ((bv (make-array len :element-type 'bit :initial-element 0)))
         (dotimes (i len) (setf (sbit bv i) (rand-int 2)))
         bv))))

(defun gen-a (idx)
  (case (mod idx 8)
    ;; 0: merge / sort / stable-sort
    (0
     (let* ((len1 (rand-range 0 8))
            (len2 (rand-range 0 8))
            (s1 (mk-seq len1))
            (s2 (mk-seq len2))
            (use-key (rand-bool)))
       (case (rand-int 3)
         (0 (let ((cs1 (sort (copy-seq s1) #'<))
                  (cs2 (sort (copy-seq s2) #'<))
                  (rtype (if (bit-vector-p s1) 'bit-vector (if (listp s1) 'list 'vector))))
              (values '(a b) nil
                      `(merge ',rtype (copy-seq a) (copy-seq b) #'< ,@(when use-key '(:key #'identity)))
                      (list cs1 cs2))))
         (1 (values '(a) nil
                    `(sort (copy-seq a) #'> ,@(when use-key '(:key #'identity)))
                    (list s1)))
         (t (values '(a) nil
                    `(stable-sort (copy-seq a) #'< :key #'abs)
                    (list s1))))))
    ;; 1: every / some / notany / notevery with 1..3 seqs
    (1
     (let* ((nseqs (rand-range 1 3))
            (seqs (loop repeat nseqs collect (mk-seq (rand-range 0 7))))
            (op (rand-pick #(every some notany notevery))))
       (case nseqs
         (1 (values '(a) nil `(,op #'plusp a) seqs))
         (2 (values '(a b) nil `(,op #'< a b) seqs))
         (t (values '(a b c) nil `(,op (lambda (x y z) (< (+ x y) z)) a b c) seqs)))))
    ;; 2: concatenate / coerce / make-sequence + downstream length/typep
    (2
     (let* ((kind (rand-int 4)))
       (case kind
         (0
          (let ((s1 (mk-str (rand-range 0 8) :base (rand-bool) :fp (rand-bool)))
                (s2 (mk-str (rand-range 0 8) :base (rand-bool) :disp (rand-bool))))
            (values '(a b) nil
                    `(let ((r (concatenate 'string a b)))
                       (list r (length r) (stringp r) (simple-string-p r)))
                    (list s1 s2))))
         (1
          (let ((s1 (mk-str (rand-range 0 8) :base t :fp (rand-bool)))
                (s2 (mk-str (rand-range 0 8) :base t :disp (rand-bool))))
            (values '(a b) nil
                    `(let ((r (concatenate 'base-string a b)))
                       (list r (length r) (typep r 'base-string)))
                    (list s1 s2))))
         (2
          (let ((a (mk-seq (rand-range 0 7)))
                (b (mk-seq (rand-range 0 7))))
            (values '(a b) nil
                    `(let ((r (concatenate 'vector a b)))
                       (list r (length r) (vectorp r)))
                    (list a b))))
         (t
          (let ((a (mk-seq (rand-range 0 7))))
            (values '(a) nil
                    `(let ((l (coerce a 'list))
                           (v (coerce a 'vector)))
                       (list l v (= (length l) (length v))))
                    (list a)))))))
    ;; 3: find-if / position-if / count-if / remove-if / substitute-if
    (3
     (let* ((len (rand-range 0 12))
            (s (mk-seq len))
            (st (rand-range 0 len))
            (en (rand-range st len))
            (fe (rand-bool))
            (op (rand-pick #(find-if position-if count-if find-if-not position-if-not remove-if delete-if))))
       (values '(s) nil
               `(let ((c (copy-seq s)))
                  (,op #'plusp c :start ,st :end ,en :from-end ,fe))
               (list s))))
    ;; 4: reduce derive-type downstream checks (+, *, logand, logxor, min, max; skip logior)
    (4
     (let* ((len (rand-range 0 5))
            (s (if (rand-bool) (loop repeat len collect (rand-range 1 6))
                   (coerce (loop repeat len collect (rand-range 1 6)) 'vector)))
            (st (rand-range 0 len))
            (en (rand-range st len))
            (fe (rand-bool))
            (init-p (rand-bool))
            (init (rand-range -5 -1))
            (fn (rand-pick #(+ * logand logxor)))
            (use-key (rand-bool)))
       (values '(s) nil
               `(let ((r (reduce #',fn s :start ,st :end ,en :from-end ,fe
                                 ,@(when init-p `(:initial-value ,init))
                                 ,@(when use-key '(:key (lambda (x) (declare (type (integer 1 10) x)) x))))))
                  (list r (plusp r) (minusp r) (zerop r) (integerp r)))
               (list s))))
    ;; 5: string case & trim transforms
    (5
     (let* ((s (mk-str (rand-range 0 10) :base (rand-bool) :fp (rand-bool) :disp (rand-bool)))
            (st (rand-range 0 (length s)))
            (en (rand-range st (length s)))
            (op (rand-pick #(string-upcase string-downcase string-capitalize))))
       (if (rand-bool)
           (values '(s) nil
                   `(let ((c (copy-seq s)))
                      (list (,op c :start ,st :end ,en)
                            (string-trim '(#\Space #\a) c)
                            (string-left-trim '(#\Space #\a) c)
                            (string-right-trim '(#\Space #\a) c)))
                   (list s))
           (let ((ch (rand-pick *chars*)))
             (values '(ch) '((type character ch))
                     `(list (char-upcase ch) (char-downcase ch)
                            (both-case-p ch) (upper-case-p ch) (lower-case-p ch))
                     (list ch))))))
    ;; 6: array-tran: multi-dim / displaced arrays, row-major-aref, array-in-bounds-p, equalp
    (6
     (let* ((d1 (rand-range 1 4))
            (d2 (rand-range 1 4))
            (base (make-array (* 2 d1 d2) :initial-element 0))
            (off (rand-range 0 (1- (* d1 d2)))))
       (dotimes (i (length base)) (setf (aref base i) (rand-range -4 4)))
       (let* ((a1 (make-array (list d1 d2) :displaced-to base :displaced-index-offset off))
              (a2 (make-array (list d1 d2) :initial-element 0))
              (r (rand-range -1 (1+ d1)))
              (c (rand-range -1 (1+ d2))))
         (dotimes (i (* d1 d2)) (setf (row-major-aref a2 i) (row-major-aref a1 i)))
         (values '(a1 a2 r c)
                 '((type (array t (* *)) a1 a2) (type fixnum r c))
                 `(list (equalp a1 a2)
                        (equal a1 a2)
                        (array-rank a1)
                        (array-dimensions a1)
                        (array-total-size a1)
                        (array-in-bounds-p a1 r c)
                        (when (array-in-bounds-p a1 r c)
                          (list (aref a1 r c)
                                (row-major-aref a1 (array-row-major-index a1 r c)))))
                 (list a1 a2 r c)))))
    ;; 7: search / subseq / bit-not downstream type checks
    (t
     (let* ((len1 (rand-range 0 5))
            (len2 (rand-range 0 12))
            (s1 (mk-seq len1))
            (s2 (mk-seq len2))
            (st (rand-range 0 len2))
            (en (rand-range st len2)))
       (values '(s1 s2) nil
               `(let* ((pos (search s1 s2 :start2 ,st :end2 ,en))
                       (sub (subseq s2 ,st ,en))
                       (bv (make-array 65 :element-type 'bit :initial-element 1)))
                  (list pos
                        (when pos (<= ,st pos ,en))
                        sub
                        (length sub)
                        (bit-not bv)))
               (list s1 s2))))))

(defun gen-b (idx)
  (case (mod idx 6)
    ;; 0: constraint-back +, -, *
    (0
     (let* ((lo1 (rand-range -15 5)) (hi1 (+ lo1 (rand-range 0 20)))
            (lo2 (rand-range -15 5)) (hi2 (+ lo2 (rand-range 0 20)))
            (x (rand-range lo1 hi1))
            (y (rand-range lo2 hi2))
            (k (rand-range -20 20))
            (op (rand-pick #(+ - *)))
            (cmp (rand-pick #(< <= > >= =))))
       (values '(x y)
               `((type (integer ,lo1 ,hi1) x) (type (integer ,lo2 ,hi2) y))
               `(if (,cmp (,op x y) ,k)
                    (list (,cmp (,op x y) ,k) (<= ,lo1 x ,hi1) (<= ,lo2 y ,hi2) (eql x ,lo1) (eql y ,hi2))
                    (list (,cmp (,op x y) ,k) (<= ,lo1 x ,hi1) (<= ,lo2 y ,hi2) (eql x ,hi1) (eql y ,lo2)))
               (list x y))))
    ;; 1: constraint-back array-rank, car/cdr, length
    (1
     (case (mod idx 3)
       (0
        (let* ((rank (rand-range 0 3))
               (dims (loop repeat rank collect (rand-range 1 3)))
               (arr (make-array dims :initial-element 0))
               (rlo (rand-range 0 2)) (rhi (+ rlo (rand-range 0 2)))
               (y (rand-range rlo rhi))
               (cmp (rand-pick #(< <= > >= =))))
          (values '(a y)
                  `((type array a) (type (integer ,rlo ,rhi) y))
                  `(if (,cmp (array-rank a) y)
                       (list (vectorp a) (<= 0 (array-rank a) 4) (eql (array-rank a) y))
                       (list (vectorp a) (<= 0 (array-rank a) 4) (eql (array-rank a) y)))
                  (list arr y))))
       (1
        (let* ((x (if (rand-bool) nil (cons (rand-range -5 5) (if (rand-bool) nil (cons 9 nil)))))
               (y (rand-range -5 5)))
          (values '(x y)
                  '((type list x) (type (integer -10 10) y))
                  `(if (eql (car x) y)
                       (list (consp x) (null x) (eql (car x) y) (typep (cdr x) 'list))
                       (list (consp x) (null x) (eql (car x) y)))
                  (list x y))))
       (t
        (let* ((x (if (rand-bool) (cons (rand-range -5 5) (rand-range -5 5)) (list 1)))
               (y (rand-range -5 5)))
          (values '(x y)
                  '((type cons x) (type (integer -10 10) y))
                  `(if (eql (cdr x) y)
                       (list (numberp (cdr x)) (null (cdr x)) (eql (cdr x) y))
                       (list (numberp (cdr x)) (null (cdr x)) (eql (cdr x) y)))
                  (list x y))))))
    ;; 2: tagbody loop widening with multiple vars & inner branch
    (2
     (let* ((a0 (rand-range -10 5))
            (b0 (rand-range -10 5))
            (n  (rand-range 0 12))
            (s1 (rand-pick #(-2 -1 1 2 3)))
            (s2 (rand-pick #(-1 0 1 2))))
       (values '(a0 b0 n)
               '((type (integer -20 20) a0 b0) (type (integer 0 20) n))
               `(let ((a a0) (b b0) (i 0))
                  (declare (type (integer -200 200) a b)
                           (type (integer 0 30) i))
                  (tagbody
                   top
                     (when (>= i n) (go done))
                     (if (evenp i)
                         (setq a (+ a ,s1))
                         (setq b (+ b ,s2)))
                     (setq i (1+ i))
                     (go top)
                   done)
                  (list a b i (eql a a0) (eql b b0) (<= -200 a 200) (< i 30)))
               (list a0 b0 n))))
    ;; 3: Float open/closed bounds & -0.0 / +0.0 & cross-float
    (3
     (let* ((svals #(-1.0f0 -0.0f0 0.0f0 0.5f0 1.0f0 1.0000001f0))
            (dvals #(-1.0d0 -0.0d0 0.0d0 0.5d0 1.0d0 1.0000000000000002d0))
            (x (rand-pick svals))
            (y (rand-pick dvals))
            (op (rand-pick #(< <= > >= =))))
       (values '(x y)
               '((type (single-float -2.0f0 2.0f0) x)
                 (type (double-float -2.0d0 2.0d0) y))
               `(list
                 (if (typep x '(single-float (0.0f0) (1.0f0)))
                     (list (> x 0.0f0) (< x 1.0f0) (= x 0.0f0) (= x 1.0f0))
                     (list (<= x 0.0f0) (>= x 1.0f0) (eql x -0.0f0) (eql x 0.0f0)))
                 (if (,op x y)
                     (list (<= x 1.0f0) (< x 1.0f0) (= x 1.0f0) (>= y 0.0d0))
                     (list (>= x 1.0f0) (> x 1.0f0) (= x 1.0f0) (<= y 0.0d0))))
               (list x y))))
    ;; 4: Complex negated typep & disjoint intervals
    (4
     (let* ((x (rand-range -15 15))
            (a (rand-range -10 0)) (b (+ a (rand-range 1 8)))
            (c (rand-range -5 5)) (d (+ c (rand-range 1 8))))
       (values '(x)
               '((type (integer -20 20) x))
               `(if (not (typep x '(integer ,a ,b)))
                    (if (typep x '(integer ,c ,d))
                        (list (or (< x ,a) (> x ,b)) (<= ,c x ,d) (eql x ,a) (eql x ,b))
                        (list (or (< x ,a) (> x ,b)) (or (< x ,c) (> x ,d))))
                    (list (<= ,a x ,b) (= x ,a) (= x ,b)))
               (list x))))
    ;; 5: Unary/binary truncate & / & mod backprop
    (t
     (let* ((x (rand-range -25 25))
            (d (rand-pick #(-6 -3 -2 2 3 6)))
            (k (rand-range -10 10))
            (cmp (rand-pick #(< <= > >= =))))
       (values '(x)
               '((type (integer -30 30) x))
               `(list
                 (if (,cmp (truncate x ,d) ,k)
                     (list (,cmp (truncate x ,d) ,k) (<= -30 x 30) (= (mod x ,d) 0))
                     (list (,cmp (truncate x ,d) ,k) (<= -30 x 30)))
                 (if (,cmp (/ x ,d) ,k)
                     (list (integerp (/ x ,d)) (<= -30 x 30))
                     (list (integerp (/ x ,d)) (<= -30 x 30))))
               (list x))))))

(defun run-suite (out-path count seed-val mode)
  (setf *seed* seed-val)
  (case mode
    (:sbcl-s3-safe3 (setf *opt-decls* '(optimize (speed 3) (safety 3)) *use-notinline* nil))
    (:sbcl-s3-safe0 (setf *opt-decls* '(optimize (speed 3) (safety 0)) *use-notinline* nil))
    (:sbcl-s0-notinline (setf *opt-decls* '(optimize (speed 0) (safety 3)) *use-notinline* t))
    (:ccl (setf *opt-decls* '(optimize (speed 3) (safety 3)) *use-notinline* nil)))
  (with-open-file (out out-path :direction :output :if-exists :supersede)
    (dotimes (i count)
      (multiple-value-bind (params decls body args) (gen-a i)
        (let* ((fn (wrap-compile params body decls))
               (res (handler-case (canon (apply fn args))
                      (error (e) (format nil "ERR:~a" (type-of e))))))
          (format out "A~5,'0d ~a~%" i res))))
    (dotimes (i count)
      (multiple-value-bind (params decls body args) (gen-b i)
        (let* ((fn (wrap-compile params body decls))
               (res (handler-case (canon (apply fn args))
                      (error (e) (format nil "ERR:~a" (type-of e))))))
          (format out "B~5,'0d ~a~%" i res))))))

(defun dump-case (kind idx seed-val seq-count)
  (setf *seed* seed-val)
  (let ((count (1+ idx)))
    (if (eq kind :A)
        (dotimes (i count)
          (multiple-value-bind (params decls body args) (gen-a i)
            (when (= i idx)
              (format t "CASE A~5,'0d~%PARAMS: ~s~%DECLS: ~s~%BODY: ~s~%ARGS: ~s~%" i params decls body args))))
        (progn
          (dotimes (i seq-count) (gen-a i))
          (dotimes (i count)
            (multiple-value-bind (params decls body args) (gen-b i)
              (when (= i idx)
                (format t "CASE B~5,'0d~%PARAMS: ~s~%DECLS: ~s~%BODY: ~s~%ARGS: ~s~%" i params decls body args))))))))

(defun main (args)
  (cond
    ((string= (first args) "dump")
     (let ((kind (if (char= (char (second args) 0) #\A) :A :B))
           (idx (parse-integer (subseq (second args) 1)))
           (seed (parse-integer (third args)))
           (seq-count (if (fourth args) (parse-integer (fourth args)) 1000)))
       (dump-case kind idx seed seq-count)))
    (t
     (let* ((mode-str (first args))
            (out-path (second args))
            (count (parse-integer (third args)))
            (seed (parse-integer (fourth args)))
            (mode (cond
                    ((string= mode-str "sbcl-s3-safe3") :sbcl-s3-safe3)
                    ((string= mode-str "sbcl-s3-safe0") :sbcl-s3-safe0)
                    ((string= mode-str "sbcl-s0-notinline") :sbcl-s0-notinline)
                    ((string= mode-str "ccl") :ccl)
                    (t (error "Unknown mode: ~a" mode-str)))))
       (run-suite out-path count seed mode)))))
