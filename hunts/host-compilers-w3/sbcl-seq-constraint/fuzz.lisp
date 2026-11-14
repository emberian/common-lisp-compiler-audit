;;;; Differential fuzzer for SBCL vs CCL:
;;;;   Part A: Sequence, string, bit-vector, and list-set transforms/derive-type
;;;;   Part B: Branching, loop interval, arithmetic, and constraint propagation
;;;; Run via run-fuzz.sh with mode arg: sbcl-s3-safe3 | sbcl-s3-safe0 | sbcl-s0-notinline | ccl

(defpackage #:sbcl-fuzz
  (:use #:cl)
  (:export #:main))

(in-package #:sbcl-fuzz)

;;; Deterministic portable 31-bit PRNG
(defvar *seed* 123456789)

(defun next-u31 ()
  (setf *seed* (logand (+ (* *seed* 1103515245) 12345) #x7fffffff))
  (ash *seed* -1))

(defun rand-int (n)
  (mod (next-u31) n))

(defun rand-range (lo hi)
  (+ lo (rand-int (1+ (- hi lo)))))

(defun rand-pick (vec)
  (elt vec (rand-int (length vec))))

(defun rand-bool (&optional (num 1) (den 2))
  (< (rand-int den) num))

;;; Safe canonical printer for comparison across SBCL and CCL
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
       (dotimes (i (length x))
         (write-char (if (zerop (bit x i)) #\0 #\1) s))))
    ((stringp x)
     (with-output-to-string (s)
       (write-char #\" s)
       (dotimes (i (length x))
         (format s "~x," (char-code (char x i))))
       (write-char #\" s)))
    ((consp x)
     (with-output-to-string (s)
       (write-char #\( s)
       (loop for cur = x then (cdr cur)
             for first = t then nil
             while (consp cur)
             do (unless first (write-char #\Space s))
                (write-string (canon (car cur)) s)
             finally (when cur
                       (write-string " . " s)
                       (write-string (canon cur) s)))
       (write-char #\) s)))
    ((vectorp x)
     (with-output-to-string (s)
       (write-string "#(" s)
       (dotimes (i (length x))
         (when (> i 0) (write-char #\Space s))
         (write-string (canon (aref x i)) s))
       (write-char #\) s)))
    (t (format nil "~s" x))))

;;; Fresh value constructors (zero-UB, never shares literals with mutated targets)
(defun make-rand-list (len lo hi)
  (loop repeat len collect (rand-range lo hi)))

(defun make-rand-vector (len lo hi &key fill-pointer displaced)
  (let* ((extra (if fill-pointer (rand-range 0 5) 0))
         (offset (if displaced (rand-range 1 5) 0))
         (total (+ offset len extra))
         (base (make-array total :initial-element 0)))
    (dotimes (i total)
      (setf (aref base i) (rand-range lo hi)))
    (cond
      (displaced
       (make-array len :displaced-to base :displaced-index-offset offset))
      (fill-pointer
       (let ((v (make-array (+ len extra) :fill-pointer len :initial-element 0)))
         (dotimes (i (+ len extra)) (setf (aref v i) (aref base i)))
         v))
      (t base))))

(defun make-rand-bitvec (len &key fill-pointer displaced)
  (let* ((extra (if fill-pointer (rand-range 0 9) 0))
         (offset (if displaced (rand-range 1 17) 0))
         (total (+ offset len extra))
         (base (make-array total :element-type 'bit :initial-element 0)))
    (dotimes (i total)
      (setf (sbit base i) (rand-int 2)))
    (cond
      (displaced
       (make-array len :element-type 'bit :displaced-to base :displaced-index-offset offset))
      (fill-pointer
       (let ((v (make-array (+ len extra) :element-type 'bit :fill-pointer len :initial-element 0)))
         (dotimes (i (+ len extra)) (setf (aref v i) (sbit base i)))
         v))
      (t base))))

(defparameter *sample-chars*
  #(#\a #\b #\c #\A #\B #\C #\0 #\9 #\Space #\-
    #.(code-char #xe9) #.(code-char #xc9)
    #.(code-char #xb5) #.(code-char #x131) #.(code-char #x17f) #.(code-char #x212a)))

(defun make-rand-string (len &key base-only fill-pointer displaced)
  (let* ((extra (if fill-pointer (rand-range 0 4) 0))
         (offset (if displaced (rand-range 1 4) 0))
         (total (+ offset len extra))
         (etype (if base-only 'base-char 'character))
         (base (make-array total :element-type etype :initial-element #\a)))
    (dotimes (i total)
      (setf (char base i)
            (if base-only
                (aref *sample-chars* (rand-int 10))
                (rand-pick *sample-chars*))))
    (cond
      (displaced
       (make-array len :element-type etype :displaced-to base :displaced-index-offset offset))
      (fill-pointer
       (let ((s (make-array (+ len extra) :element-type etype :fill-pointer len :initial-element #\a)))
         (dotimes (i (+ len extra)) (setf (char s i) (char base i)))
         s))
      (t base))))

(defparameter *opt-decls* nil)
(defparameter *use-notinline* nil)

(defparameter *seq-ops*
  '(search position find mismatch count subseq replace fill
    remove delete substitute nsubstitute reduce
    set-exclusive-or nset-exclusive-or union intersection set-difference subsetp
    string= string/= string< string-equal string-not-equal
    bit-and bit-ior bit-xor bit-eqv bit-andc1 bit-andc2 bit-orc1 bit-orc2 bit-nand bit-nor bit-not))

(defun wrap-compile (params body &optional extra-decls)
  (let ((decls `(,@(when *opt-decls* (list *opt-decls*))
                 #+sbcl (sb-ext:muffle-conditions sb-ext:compiler-note style-warning)
                 ,@(when *use-notinline* (list `(notinline ,@*seq-ops*)))
                 ,@extra-decls)))
    (compile nil `(lambda ,params
                    (declare ,@decls)
                    ,body))))

;;; ------------------------------------------------------------------
;;; Part A: Sequence / String / Bit-vector test generator
;;; ------------------------------------------------------------------
(defun rand-seq (kind len)
  (case kind
    (:list (make-rand-list len -3 5))
    (:simple-vec (make-rand-vector len -3 5))
    (:fp-vec (make-rand-vector len -3 5 :fill-pointer t))
    (:disp-vec (make-rand-vector len -3 5 :displaced t))
    (:simple-bv (make-rand-bitvec len))
    (:fp-bv (make-rand-bitvec len :fill-pointer t))
    (:disp-bv (make-rand-bitvec len :displaced t))
    (:simple-base (make-rand-string len :base-only t))
    (:simple-str (make-rand-string len :base-only nil))
    (:fp-str (make-rand-string len :fill-pointer t))
    (:disp-str (make-rand-string len :displaced t))))

(defun gen-seq-case (idx)
  (let* ((op-cat (mod idx 7))
         (lens #(0 1 2 7 8 15 16 31 32 63 64 65 128 129)))
    (case op-cat
      ;; 0: search / mismatch
      (0
       (let* ((kind (rand-pick #(:list :simple-vec :fp-vec :disp-vec :simple-bv :disp-bv :simple-base :simple-str :disp-str)))
              (len1 (rand-range 0 6))
              (len2 (rand-pick lens))
              (s1 (rand-seq kind len1))
              (s2 (rand-seq kind len2))
              (st1 (rand-range 0 len1))
              (en1 (rand-range st1 len1))
              (st2 (rand-range 0 len2))
              (en2 (rand-range st2 len2))
              (from-end (rand-bool))
              (op (if (rand-bool) 'search 'mismatch))
              (use-key (and (not (member kind '(:simple-bv :disp-bv :simple-base :simple-str :disp-str)))
                            (rand-bool 1 3)))
              (use-test (rand-bool 1 3))
              (body `(,op s1 s2
                          :start1 ,st1 :end1 ,en1
                          :start2 ,st2 :end2 ,en2
                          :from-end ,from-end
                          ,@(when use-test `(:test ,(if (member kind '(:simple-base :simple-str :disp-str)) '#'char-equal '#'equalp)))
                          ,@(when use-key '(:key #'abs)))))
         (values body (list s1 s2))))
      ;; 1: find / position / count
      (1
       (let* ((kind (rand-pick #(:list :simple-vec :fp-vec :disp-vec :simple-bv :fp-bv :disp-bv :simple-base :simple-str :disp-str)))
              (len (rand-pick lens))
              (s (rand-seq kind len))
              (st (rand-range 0 len))
              (en (rand-range st len))
              (from-end (rand-bool))
              (op (rand-pick #(find position count)))
              (item (case kind
                      ((:simple-bv :fp-bv :disp-bv) (rand-int 2))
                      ((:simple-base :simple-str :disp-str) (rand-pick *sample-chars*))
                      (t (rand-range -3 5))))
              (use-test (rand-bool 1 3))
              (use-key (and (member kind '(:list :simple-vec :fp-vec :disp-vec)) (rand-bool 1 3)))
              (body `(,op item s
                          :start ,st :end ,en
                          :from-end ,from-end
                          ,@(when use-test
                              (cond
                                ((member kind '(:simple-base :simple-str :disp-str)) '(:test #'char-equal))
                                ((member kind '(:simple-bv :fp-bv :disp-bv)) '(:test #'eql))
                                (t '(:test #'=))))
                          ,@(when use-key '(:key #'1+)))))
         (values body (list item s))))
      ;; 2: subseq / replace / fill
      (2
       (let* ((kind (rand-pick #(:list :simple-vec :fp-vec :disp-vec :simple-bv :fp-bv :disp-bv :simple-base :simple-str :disp-str)))
              (len (rand-pick lens))
              (s (rand-seq kind len))
              (st (rand-range 0 len))
              (en (rand-range st len))
              (sub-op (rand-int 3)))
         (case sub-op
           (0
            (values `(subseq s ,st ,en) (list s)))
           (1
            (let* ((s2 (rand-seq kind (rand-pick lens)))
                   (st2 (rand-range 0 (length s2)))
                   (en2 (rand-range st2 (length s2)))
                   (same (rand-bool 1 4)))
              (if same
                  (values `(let ((c (copy-seq s))) (replace c c :start1 ,st :end1 ,en :start2 ,st :end2 ,en)) (list s))
                  (values `(let ((c (copy-seq s))) (replace c s2 :start1 ,st :end1 ,en :start2 ,st2 :end2 ,en2)) (list s s2)))))
           (t
            (let ((item (case kind
                          ((:simple-bv :fp-bv :disp-bv) (rand-int 2))
                          ((:simple-base) (aref *sample-chars* (rand-int 10)))
                          ((:simple-str :disp-str) (rand-pick *sample-chars*))
                          (t (rand-range -3 5)))))
              (values `(let ((c (copy-seq s))) (fill c item :start ,st :end ,en)) (list s item)))))))
      ;; 3: remove / delete / substitute / nsubstitute
      (3
       (let* ((kind (rand-pick #(:list :simple-vec :fp-vec :disp-vec :simple-bv :simple-str :disp-str)))
              (len (rand-range 0 18))
              (s (rand-seq kind len))
              (st (rand-range 0 len))
              (en (rand-range st len))
              (from-end (rand-bool))
              (cnt (if (rand-bool) nil (rand-range 0 4)))
              (op (rand-pick #(remove delete substitute nsubstitute)))
              (item (case kind
                      ((:simple-bv) (rand-int 2))
                      ((:simple-str :disp-str) (rand-pick *sample-chars*))
                      (t (rand-range -3 5))))
              (new-item (case kind
                          ((:simple-bv) (rand-int 2))
                          ((:simple-str :disp-str) (rand-pick *sample-chars*))
                          (t (rand-range -3 5)))))
         (if (member op '(remove delete))
             (values `(let ((c (copy-seq s)))
                        (,op item c :start ,st :end ,en :from-end ,from-end ,@(when cnt `(:count ,cnt))))
                     (list item s))
             (values `(let ((c (copy-seq s)))
                        (,op new-item item c :start ,st :end ,en :from-end ,from-end ,@(when cnt `(:count ,cnt))))
                     (list new-item item s)))))
      ;; 4: reduce (with & without initial-value, empty & non-empty, from-end, :key)
      (4
       (let* ((len (rand-range 0 6))
              (s (if (rand-bool) (make-rand-list len -4 6) (make-rand-vector len -4 6)))
              (st (rand-range 0 len))
              (en (rand-range st len))
              (from-end (rand-bool))
              (has-init (rand-bool))
              (init (rand-range -3 5))
              (fn (rand-pick #(+ * logand logior logxor)))
              (use-key (rand-bool)))
         (values `(reduce #',fn s :start ,st :end ,en :from-end ,from-end
                          ,@(when has-init `(:initial-value ,init))
                          ,@(when use-key '(:key (lambda (x) (declare (type (integer -10 10) x)) (1+ (* 2 x))))))
                 (list s))))
      ;; 5: string comparisons & bit-vector ops
      (5
       (if (rand-bool)
           (let* ((k1 (rand-pick #(:simple-base :simple-str :fp-str :disp-str)))
                  (k2 (rand-pick #(:simple-base :simple-str :fp-str :disp-str)))
                  (l1 (rand-range 0 12))
                  (l2 (rand-range 0 12))
                  (s1 (rand-seq k1 l1))
                  (s2 (rand-seq k2 l2))
                  (st1 (rand-range 0 l1))
                  (en1 (rand-range st1 l1))
                  (st2 (rand-range 0 l2))
                  (en2 (rand-range st2 l2))
                  (op (rand-pick #(string= string/= string< string-equal string-not-equal))))
             (values `(,op s1 s2 :start1 ,st1 :end1 ,en1 :start2 ,st2 :end2 ,en2) (list s1 s2)))
           (let* ((len (rand-pick #(0 1 7 8 63 64 65 128 129)))
                  (k1 (rand-pick #(:simple-bv :fp-bv :disp-bv)))
                  (k2 (rand-pick #(:simple-bv :fp-bv :disp-bv)))
                  (b1 (rand-seq k1 len))
                  (b2 (rand-seq k2 len))
                  (dest (rand-bool))
                  (op (rand-pick #(bit-and bit-ior bit-xor bit-eqv bit-andc1 bit-andc2 bit-orc1 bit-orc2 bit-nand bit-nor))))
             (if dest
                 (let ((r (rand-seq (rand-pick #(:simple-bv :fp-bv :disp-bv)) len)))
                   (values `(let ((rc (copy-seq r))) (,op b1 b2 rc)) (list b1 b2 r)))
                 (values `(,op b1 b2) (list b1 b2))))))
      ;; 6: list set operations & sort/merge
      (t
       (let* ((op (rand-pick #(union intersection set-difference subsetp)))
              (l1 (make-rand-list (rand-range 0 6) -3 4))
              (l2 (make-rand-list (rand-range 0 6) -3 4))
              (same (rand-bool 1 4)))
         (if (eq op 'subsetp)
             (if same
                 (values `(subsetp l1 l1 :test #'eql) (list l1))
                 (values `(subsetp l1 l2 :test #'eql) (list l1 l2)))
             ;; Compare sorted deduplicated set across SBCL vs CCL (ANSI permits arbitrary order & dups)
             (if same
                 (values `(remove-duplicates (sort (copy-list (,op l1 l1)) #'<)) (list l1))
                 (values `(remove-duplicates (sort (copy-list (,op l1 l2)) #'<)) (list l1 l2)))))))))

(defun find-symbol-in-tree (sym tree)
  (cond
    ((eq sym tree) t)
    ((consp tree) (or (find-symbol-in-tree sym (car tree))
                      (find-symbol-in-tree sym (cdr tree))))
    (t nil)))

;;; Build case with consistent param names
(defun build-seq-case (idx)
  (multiple-value-bind (body args) (gen-seq-case idx)
    (let* ((s1-p (find-symbol-in-tree 's1 body))
           (s2-p (find-symbol-in-tree 's2 body))
           (s-p  (find-symbol-in-tree 's body))
           (item-p (find-symbol-in-tree 'item body))
           (new-p (find-symbol-in-tree 'new-item body))
           (b1-p (find-symbol-in-tree 'b1 body))
           (b2-p (find-symbol-in-tree 'b2 body))
           (r-p  (find-symbol-in-tree 'r body))
           (l1-p (find-symbol-in-tree 'l1 body))
           (l2-p (find-symbol-in-tree 'l2 body))
           (pnames (append (when new-p '(new-item))
                           (when item-p '(item))
                           (when s-p '(s))
                           (when s1-p '(s1))
                           (when s2-p '(s2))
                           (when b1-p '(b1))
                           (when b2-p '(b2))
                           (when r-p '(r))
                           (when l1-p '(l1))
                           (when l2-p '(l2))))
           (ordered-args
             (cond
               ((equal pnames '(item s))
                (if (typep (first args) 'sequence)
                    (list (second args) (first args))
                    args))
               (t args))))
      (values pnames body ordered-args))))

;;; ------------------------------------------------------------------
;;; Part B: Constraint propagation, loops, interval arithmetic fuzzer
;;; ------------------------------------------------------------------
(defun rand-int-range ()
  (let* ((lo (rand-range -30 20))
         (span (rand-pick #(0 1 2 5 10 25 60)))
         (hi (+ lo span)))
    (list lo hi)))

(defun gen-constraint-case (idx)
  (let ((cat (mod idx 5)))
    (case cat
      ;; 0: Nested numeric branches + derived equality/inequality checks
      (0
       (let* ((r1 (rand-int-range))
              (r2 (rand-int-range))
              (x (rand-range (first r1) (second r1)))
              (y (rand-range (first r2) (second r2)))
              (k1 (rand-range -20 25))
              (k2 (rand-range -20 25))
              (op1 (rand-pick #(< <= > >= = /=)))
              (op2 (rand-pick #(< <= > >= = /=)))
              (arith (rand-pick #(+ - *)))
              (pred1 (rand-pick #(< <= > >= = /=)))
              (t1 `(integer ,(first r1) ,(second r1)))
              (t2 `(integer ,(first r2) ,(second r2))))
         (values
          '(x y)
          `((type ,t1 x) (type ,t2 y))
          `(let ((z (,arith x y)))
             (list
              (if (,op1 x ,k1)
                  (if (,op2 y ,k2)
                      (list (,pred1 z (+ ,k1 ,k2)) (,pred1 x y) (typep x ',t1))
                      (list (,pred1 z (- ,k1 ,k2)) (eql x ,k1)))
                  (if (,op2 z ,k2)
                      (list (,pred1 x y) (eql y ,k2))
                      (list (,pred1 y ,k1) (typep z '(integer -2000 2000)))))))
          (list x y))))
      ;; 1: char-code / length / abs / truncate constraint-propagate-back
      (1
       (let* ((sub (mod idx 4))
              (c1 (rand-range 10 80))
              (c2 (+ c1 (rand-range 0 25)))
              (ch (code-char (rand-range c1 c2)))
              (y (rand-range c1 c2))
              (k (rand-range 10 100)))
         (case sub
           (0
            ;; char-code comparisons (<, <=, >, >=; = already confirmed)
            (let ((op (rand-pick #(< <= > >=)))
                  (invert (rand-bool)))
              (values
               '(c y)
               `((type character c) (type (integer ,c1 ,c2) y))
               `(let ((b (,op (char-code c) y)))
                  ,(if invert
                       `(if (not b) (list (<= ,c1 (char-code c) ,c2) (eql (char-code c) y)) :else)
                       `(if b (list (<= ,c1 (char-code c) ,c2) (eql (char-code c) y)) :else)))
               (list ch y))))
           (1
            ;; length constraint-propagate-back
            (let* ((l1 (rand-range 0 5))
                   (l2 (+ l1 (rand-range 0 6)))
                   (len (rand-range l1 l2))
                   (vec (make-array len :initial-element 0))
                   (op (rand-pick #(< <= > >= =))))
              (values
               '(v n)
               `((type simple-vector v) (type (integer ,l1 ,l2) n))
               `(let ((b (,op (length v) n)))
                  (if b
                      (list (<= ,l1 (length v) ,l2) (typep v '(simple-vector)))
                      (list (<= ,l1 (length v) ,l2) (eql (length v) n))))
               (list vec (rand-range l1 l2)))))
           (2
            ;; abs & %negate constraint-propagate-back
            (let* ((r (rand-int-range))
                   (x (rand-range (first r) (second r)))
                   (lo (rand-range 0 20))
                   (hi (+ lo (rand-range 0 20))))
              (values
               '(x)
               `((type (integer ,(first r) ,(second r)) x))
               `(if (<= ,lo (abs x) ,hi)
                    (list (<= ,(- hi) x ,hi) (<= ,lo (abs x)))
                    (list (<= ,(- hi) x ,hi) (> (abs x) ,hi) (< (abs x) ,lo)))
               (list x))))
           (t
            ;; truncate / floor back-propagation
            (let* ((r (rand-int-range))
                   (x (rand-range (first r) (second r)))
                   (d (rand-pick #(-7 -3 -2 -1 1 2 3 7)))
                   (q (truncate x d)))
              (values
               '(x)
               `((type (integer ,(first r) ,(second r)) x))
               `(let ((res (truncate x ,d)))
                  (if (eql res ,q)
                      (list (= res ,q) (<= ,(- (* (abs q) (abs d)) (abs d)) x ,(+ (* (abs q) (abs d)) (abs d))) (> x ,k))
                      (list (= res ,q) (< res ,q))))
               (list x)))))))
      ;; 2: Loop interval widening & induction variables
      (2
       (let* ((init (rand-range -10 5))
              (step (rand-pick #(1 2 3 -1 -2)))
              (iters (rand-range 0 12))
              (limit (if (plusp step)
                         (+ init (* step iters) (rand-range 0 2))
                         (- init (* (abs step) iters) (rand-range 0 2))))
              (acc-init (rand-range -5 5)))
         (values
          '(init limit)
          `((type (integer -50 50) init limit))
          `(let ((i init) (acc ,acc-init) (cnt 0))
             (declare (type (integer -200 200) i)
                      (type (integer -10000 10000) acc)
                      (type (integer 0 100) cnt))
             (loop while (and (< cnt 30)
                              ,(if (plusp step) `(<= i limit) `(>= i limit)))
                   do (incf acc i)
                      (incf i ,step)
                      (incf cnt))
             (list i acc cnt
                   (<= -200 i 200)
                   (if (zerop cnt) (= acc ,acc-init) t)
                   (eql i init)))
          (list init limit))))
      ;; 3: Signed zero / float comparisons (no NaNs, zero-UB)
      (3
       (let* ((vals #(-2.5d0 -1.0d0 -0.0d0 0.0d0 1.0d0 2.5d0))
              (x (rand-pick vals))
              (y (rand-pick vals))
              (op1 (rand-pick #(< <= > >= = /=)))
              (op2 (rand-pick #(< <= > >= = /= eql))))
         (values
          '(x y)
          `((type (double-float -10.0d0 10.0d0) x y))
          `(if (,op1 x y)
               (list (,op2 x y) (eql x 0.0d0) (eql x -0.0d0) (< x 0.0d0) (<= x 0.0d0))
               (list (,op2 x y) (eql x 0.0d0) (eql x -0.0d0) (>= x 0.0d0) (> x 0.0d0)))
          (list x y))))
      ;; 4: Cross-type comparisons (integer vs ratio vs single-float vs double-float)
      (t
       (let* ((x (rand-pick #(-2 -1 0 1 2)))
              (y (rand-pick #(-3/2 -1/2 0 1/2 3/2)))
              (z (rand-pick #(-1.0f0 -0.0f0 0.0f0 1.0f0 1.0000001f0)))
              (w (rand-pick #(-1.0d0 -0.0d0 0.0d0 1.0d0 1.0000000000000002d0))))
         (values
          '(x y z w)
          `((type (integer -5 5) x)
            (type rational y)
            (type (single-float -5.0f0 5.0f0) z)
            (type (double-float -5.0d0 5.0d0) w))
          `(list
            (if (< x y) (list (< x 2) (<= x 1) (= x 1)) (list (>= x -2) (= x 1)))
            (if (< z w) (list (<= z w) (= z 1.0f0) (<= z 1.0f0)) (list (>= z w) (= z 1.0f0))))
          (list x y z w)))))))

(defun run-suite (out-path count seed-val mode)
  (setf *seed* seed-val)
  (case mode
    (:sbcl-s3-safe3
     (setf *opt-decls* '(optimize (speed 3) (safety 3))
           *use-notinline* nil))
    (:sbcl-s3-safe0
     (setf *opt-decls* '(optimize (speed 3) (safety 0))
           *use-notinline* nil))
    (:sbcl-s0-notinline
     (setf *opt-decls* '(optimize (speed 0) (safety 3))
           *use-notinline* t))
    (:ccl
     (setf *opt-decls* '(optimize (speed 3) (safety 3))
           *use-notinline* nil)))
  (with-open-file (out out-path :direction :output :if-exists :supersede)
    ;; Part A: Sequence / string / bit-vector cases
    (dotimes (i count)
      (multiple-value-bind (params body args) (build-seq-case i)
        (let* ((fn (wrap-compile params body))
               (res (handler-case (canon (apply fn args))
                      (error (e) (format nil "ERR:~a" (type-of e))))))
          (format out "A~5,'0d ~a~%" i res))))
    ;; Part B: Constraint / loop / float / arithmetic cases
    (dotimes (i count)
      (multiple-value-bind (params decls body args) (gen-constraint-case i)
        (let* ((fn (wrap-compile params body decls))
               (res (handler-case (canon (apply fn args))
                      (error (e) (format nil "ERR:~a" (type-of e))))))
          (format out "B~5,'0d ~a~%" i res))))))

(defun dump-case (kind idx seed-val &optional (seq-count 500))
  (setf *seed* seed-val)
  (let ((count (1+ idx)))
    (if (eq kind :A)
        (dotimes (i count)
          (multiple-value-bind (params body args) (build-seq-case i)
            (when (= i idx)
              (format t "CASE A~5,'0d~%PARAMS: ~s~%BODY: ~s~%ARGS: ~s~%" i params body args))))
        (progn
          (dotimes (i seq-count) (build-seq-case i))
          (dotimes (i count)
            (multiple-value-bind (params decls body args) (gen-constraint-case i)
              (when (= i idx)
                (format t "CASE B~5,'0d~%PARAMS: ~s~%DECLS: ~s~%BODY: ~s~%ARGS: ~s~%" i params decls body args))))))))

(defun main (args)
  (cond
    ((string= (first args) "dump")
     (let ((kind (if (char= (char (second args) 0) #\A) :A :B))
           (idx (parse-integer (subseq (second args) 1)))
           (seed (parse-integer (third args)))
           (seq-count (if (fourth args) (parse-integer (fourth args)) 500)))
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
