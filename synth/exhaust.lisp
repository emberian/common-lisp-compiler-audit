;;; Bounded-exhaustive mode: ALL integer IR terms with at most K operator nodes
;;; over a fixed operator set and two typed variables, each as its own function,
;;; each queried on the full cross product of boundary values of its parameters.
;;;
;;; Terms:   leaves  x y 0 1 -1 3
;;;          unary   - lognot 1+ 1- abs integer-length logcount
;;;                  (ash e 1) (ash e -1) (ash e 63) (ash e -63)
;;;          binary  + - * logand logior logxor min max floor truncate mod rem
;;;                  (if (< a b) 1 0) (if (<= a b) 1 0) (if (= a b) 1 0) (if (logtest a b) 1 0)
;;; Commutative operators are enumerated with ordered operands; terms without a
;;; variable are skipped.  A term is emitted iff INFER accepts it (every guard
;;; provable from the declared parameter types: a possibly-zero divisor is the
;;; only way to be rejected, since results up to 220 bits are allowed); rejected
;;; terms are counted per reason.
;;;
;;; Usage: sbcl --script exhaust.lisp K CONFIG WORKDIR/ HOST [DENSITY] [LIMIT]
;;;   CONFIG  s64 | u64 | mixed | fix | small   (declared types of x and y)
;;;   DENSITY THE-annotation density in percent (default 0: parameter declarations only)
;;; Writes WORKDIR/exhaust-K-CONFIG-HOST.txt with exact counts.
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)

(defparameter *leaves* '(x y 0 1 -1 3))
(defparameter *unary*
  (append (mapcar (lambda (op) (lambda (e) (list op e))) '(- lognot 1+ 1- abs integer-length logcount))
          (mapcar (lambda (k) (lambda (e) `(ash ,e ,k))) '(1 -1 63 -63))))
(defparameter *commutative-binary* '(+ * logand logior logxor min max))
(defparameter *ordered-binary*
  (append (mapcar (lambda (op) (lambda (a b) (list op a b))) '(- floor truncate mod rem))
          (mapcar (lambda (op) (lambda (a b) `(if (,op ,a ,b) 1 0))) '(< <= = logtest))))

(defvar *memo* (make-hash-table))
(defun terms (k)
  "All terms with exactly K operator nodes."
  (or (gethash k *memo*)
      (setf (gethash k *memo*)
            (if (= k 0)
                (copy-list *leaves*)
                (let ((out nil))
                  (dolist (e (terms (1- k)))
                    (dolist (u *unary*) (push (funcall u e) out)))
                  (loop for i from 0 to (1- k)
                        do (let ((as (terms i)) (bs (terms (- k 1 i))))
                             (dolist (op *ordered-binary*)
                               (dolist (a as) (dolist (b bs) (push (funcall op a b) out))))
                             ;; commutative: (i, j) with i <= j, and within i = j ordered pairs
                             (when (<= i (- k 1 i))
                               (dolist (op *commutative-binary*)
                                 (if (= i (- k 1 i))
                                     (loop for (a . more) on as
                                           do (dolist (b (cons a more)) (push (list op a b) out)))
                                     (dolist (a as) (dolist (b bs) (push (list op a b) out))))))))
                  (nreverse out))))))

(defun has-var (e) (or (member e '(x y)) (and (consp e) (some #'has-var (cdr e)))))

(defun boundary (ty)
  (let ((lo (second ty)) (hi (third ty)))
    (remove-duplicates
     (remove-if-not (lambda (v) (<= lo v hi))
                    (list lo (1+ lo) -1 0 1 (1- hi) hi (floor (+ lo hi) 3))))))

(defun config-types (name)
  (flet ((s (n) (ti (- (pow2 (1- n))) (1- (pow2 (1- n))))) (u (n) (ti 0 (1- (pow2 n)))))
    (cond ((equal name "s64") (list (s 64) (s 64)))
          ((equal name "u64") (list (u 64) (u 64)))
          ((equal name "mixed") (list (s 64) (u 64)))
          ((equal name "fix") (list (s 62) (s 61)))
          ((equal name "small") (list (ti -8 8) (ti 0 3)))
          (t (error "unknown config ~A" name)))))

(let* ((argv (cdr sb-ext:*posix-argv*))
       (k (parse-integer (first argv))) (config (second argv)) (w (third argv))
       (host (if (equal (fourth argv) "ccl") :ccl :head))
       (density (if (fifth argv) (parse-integer (fifth argv)) 0))
       (limit (and (sixth argv) (parse-integer (sixth argv))))
       (types (config-types config))
       (env (list (cons 'x (first types)) (cons 'y (second types))))
       (queries (loop for a in (boundary (first types))
                      append (loop for b in (boundary (second types)) collect (list 0 a b))))
       (chunk 4000)
       (enumerated 0) (closed 0) (rejected (make-hash-table :test 'equal)) (fns nil) (idx 0)
       (*aggregate-queries* t) (*edge-bias* 60))
  (setf *elem* (ti 0 0) *fields* nil *feats* nil *consts* nil *fns* (make-hash-table)
        *rs* (sb-ext:seed-random-state 1))
  (loop for size from 1 to k
        do (dolist (e (terms size))
             (incf enumerated)
             (cond ((not (has-var e)) (incf closed))
                   ((and limit (>= idx limit)))
                   (t (let ((r (catch 'invalid (list (infer e env)))))
                        (if (and (consp r) (eq (car r) :invalid))
                            (incf (gethash (princ-to-string (second r)) rejected 0))
                            (progn
                              (push (make-fn :name (intern (format nil "ZF~D" idx) :zs)
                                             :params '(x y) :ptypes types :rtype (first r) :ir e
                                             :kind :plain :density density :ann-seed idx
                                             :queries queries)
                                    fns)
                              (incf idx))))))))
  (setf fns (nreverse fns))
  (let ((dirs nil) (ok 0) (diff 0) (answered 0) (invalid-chunks 0) (cov (make-hash-table :test 'equal))
        (diff-lines nil))
    (loop for start from 0 below (length fns) by chunk for c from 0
          do (let ((dir (format nil "~Ax~D/" w c))
                   (p (%make-prog :seed 0 :elem (ti 0 0) :ctx '(:ignore :ok :irrelevant t)
                                  :fns (subseq fns start (min (length fns) (+ start chunk))))))
               (ensure-directories-exist dir)
               (emit-prog p dir) (push dir dirs)))
    (setf dirs (nreverse dirs))
    (loop for group on dirs by (lambda (l) (nthcdr 5 l))
          do (dolist (r (run-batch-robust (subseq group 0 (min 5 (length group))) w
                                          :host host :cov t :timeout 3000
                                          :tag (format nil "exhaust-~(~A~)" host)))
               (unless (res-valid r) (incf invalid-chunks))
               (dolist (l (q-lines r))
                 (incf answered)
                 (if (search ":DIFF" l)
                     (progn (incf diff) (push (format nil "~A ~A" (res-dir r) l) diff-lines))
                     (incf ok)))
               (dolist (key (res-cov r)) (setf (gethash key cov) t))))
    (with-open-file (s (format nil "~Aexhaust-~D-~A-~(~A~)-d~D.txt" w k config host density)
                       :direction :output :if-exists :supersede)
      (flet ((say (fmt &rest a) (apply #'format s fmt a) (apply #'format t fmt a)))
        (say "bounded-exhaustive K=~D config=~A x:~S y:~S host=~(~A~) density=~D~%" k config
             (first types) (second types) host density)
        (say "terms enumerated (size 1..~D): ~D; without a variable (skipped): ~D~%" k enumerated closed)
        (maphash (lambda (why n) (say "rejected by infer (~A): ~D~%" why n)) rejected)
        (say "functions emitted: ~D~:[~; (LIMITED)~]; inputs per function: ~D~%" (length fns) limit
             (length queries))
        (say "functions answered: ~D  agree: ~D  DIFF: ~D  chunks not valid: ~D~%"
             answered ok diff invalid-chunks)
        (say "coverage of these functions: ~D transforms, ~D VOPs~%"
             (loop for key being the hash-keys of cov count (eql 0 (search "T:" key)))
             (loop for key being the hash-keys of cov count (eql 0 (search "V:" key))))
        (dolist (l diff-lines) (say "DIFF ~A~%" l))))
    (with-open-file (s (format nil "~Acov-~D-~A-~(~A~)-d~D.sexp" w k config host density)
                       :direction :output :if-exists :supersede)
      (prin1 (loop for key being the hash-keys of cov collect key) s))))
