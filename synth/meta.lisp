;;; Metamorphic variants (after EMI, Le/Afshari/Su PLDI 2014): an oracle that
;;; does not depend on the REF twin.
;;;
;;; For a program P with fixed queries, emit rewrites that preserve the value
;;; of every query and require identical query records (the residue of the
;;; value, per query).  Rewrites, on the IR unless noted:
;;;   dead-opaque   e -> (if FALSE-FOR-ALL-INPUTS D e), D freshly generated at e's type
;;;   dead-emi      body -> (if (= x K) D body), K a value of parameter x that no
;;;                 query supplies; only for functions nothing else calls
;;;   hoist         (op .. a ..) -> (let ((h a)) (op .. h ..)) for strict op
;;;   commute       (op a b) -> (op b a) for commutative op
;;;   permute       parameter order of a function, at its definition, every call
;;;                 and its queries
;;;   inline, style, annotation (THE density, declared widths, TYPE vs :GUARD), context
;;;   mv-as-list    (emission) an MV function returns a list; callers take it apart
;;;
;;; Usage: sbcl --script meta.lisp SEED NFNS NVARIANTS WORKDIR/ HOST   (HOST: head | ccl | both)
;;; Exit code 0 iff P and all variants are valid and all records agree (and, with
;;; both, agree across hosts).
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)

(defparameter *strict-ops*
  '(+ - * 1+ 1- ash logand logior logxor logeqv logandc1 logandc2 lognand lognor logorc1 logorc2
    lognot floor truncate mod rem ceiling round integer-length logcount abs min max signum expt
    car cdr cons len nth nthcdr append char-code code-char length numerator denominator /))
(defparameter *commutative* '(+ * logand logior logxor logeqv min max))

(defun opaque-false (env)
  (let ((iv (int-vars env)))
    (if iv
        (let ((v (car (pick iv))))
          (pick (list `(< (abs ,v) 0) `(> (logand ,v 1) 1) `(and (evenp ,v) (oddp ,v))
                      `(= (logand (* (logand ,v 255) (+ (logand ,v 255) 1)) 1) 1)
                      `(< (logcount ,v) 0) `(/= ,v ,v))))
        (pick '((< 1 0) (= 0 1))))))

(defun called-elsewhere-p (f p)
  (or (find (fn-name f) (prog-computed p) :key #'first)
      (some (lambda (g) (and (not (eq g f)) (find (fn-name f) (calls-in (fn-ir g)) :key #'car)))
            (prog-fns p))))

(defun permute-params (f p)
  (let* ((n (length (fn-params f)))
         (perm (let ((l (loop for i below n collect i)))
                 (loop for i from n downto 2 do (rotatef (nth (rnd i) l) (nth (1- i) l)))
                 l)))
    (flet ((ap (l) (mapcar (lambda (i) (nth i l)) perm)))
      (labels ((walk (x)
                 (cond ((atom x) x)
                       ((eq (car x) 'quote) x)
                       ((eq (car x) (fn-name f)) (cons (car x) (ap (mapcar #'walk (cdr x)))))
                       (t (cons (walk (car x)) (mapcar #'walk (cdr x)))))))
        (dolist (g (prog-fns p)) (setf (fn-ir g) (walk (fn-ir g))))
        (setf (fn-params f) (ap (fn-params f)) (fn-ptypes f) (ap (fn-ptypes f))
              (fn-queries f) (mapcar (lambda (q) (cons (car q) (ap (cdr q)))) (fn-queries f)))
        (let ((k (find (fn-name f) (prog-computed p) :key #'first)))
          (when k (setf (third k) (ap (third k)))))
        t))))

(defun meta-step (q)
  "Apply one rewrite to Q in place.  Returns its name, or NIL if it did not apply."
  (let* ((f (pick (prog-fns q)))
         (kind (pick '(:dead-opaque :dead-opaque :dead-emi :hoist :hoist :commute :commute :permute
                       :inline :style :annotation :context :mv-as-list))))
    (install-prog q)
    (and
     (ecase kind
       ((:dead-opaque :hoist :commute)
        (let* ((sites (fn-sites f q)) (site (and sites (pick sites))))
          (when site
            (destructuring-bind (form env ty restricted) site
              (let* ((*restrict* restricted) (*gensym* (+ 5000 (rnd 100000)))
                     (new (safely
                            (ecase kind
                              (:dead-opaque
                               (let ((d (gen-of-type ty (1+ (rnd 2)) env)))
                                 (if (chance 50)
                                     (typed `(if ,(opaque-false env) ,(car d) ,form) env)
                                     (typed `(if (not ,(opaque-false env)) ,form ,(car d)) env))))
                              (:hoist
                               (let ((pos (loop for a in (cdr form) for i from 1
                                                when (consp a) collect i)))
                                 (unless (and pos (member (car form) *strict-ops*)) (invalid :no-hoist))
                                 (let* ((i (pick pos)) (h (fresh "H")) (c (copy-list form)))
                                   (setf (nth i c) h)
                                   (typed `(let ((,h ,(nth i form))) ,c) env))))
                              (:commute
                               (unless (and (member (car form) *commutative*) (= (length form) 3))
                                 (invalid :no-commute))
                               (typed (list (car form) (third form) (second form)) env))))))
                (when (and new (sub-p (cdr new) ty))
                  (setf (fn-ir f) (subst (car new) form (fn-ir f) :test #'eq))
                  t))))))
       (:dead-emi
        (let* ((ints (loop for prm in (fn-params f) for ty in (fn-ptypes f) for i from 0
                           when (and (small-int-p ty) (> (- (third ty) (second ty)) 40)) collect i))
               (rty (fn-rtype f)))
          (when (and ints (not (fn-measure f)) (not (fn-clique f)) (value-type-p rty)
                     (not (called-elsewhere-p f q)))
            (let* ((i (pick ints)) (prm (nth i (fn-params f))) (ty (nth i (fn-ptypes f)))
                   (used (mapcar (lambda (qq) (nth i (cdr qq))) (fn-queries f)))
                   (k (loop repeat 50
                            for c = (const-in (second ty) (third ty))
                            unless (member c used) return c))
                   (env (mapcar #'cons (fn-params f) (fn-ptypes f)))
                   (d (and k (progn (install-prog q f) (safely (gen-of-type rty 2 env))))))
              (when d
                (setf (fn-ir f) `(if (= ,prm ,k) ,(car d) ,(fn-ir f)))
                t)))))
       (:permute (and (> (length (fn-params f)) 1) (permute-params f q)))
       (:inline (unless (or (fn-clique f) (member :st (fn-ptypes f))
                            (and (fn-measure f) (not *keep-f18-shape*))
                            (member (fn-name f) (getf (prog-ctx q) :all-styles)))
                  (setf (fn-inline f) (not (fn-inline f)) (fn-style f) nil)
                  t))
       (:style (unless (or (fn-clique f) (fn-inline f))
                 (setf (fn-style f) (pick *styles*)) t))
       (:annotation (setf (fn-ann-seed f) (rnd 1000000) (fn-density f) (pick '(0 30 60 100))
                          (fn-gmode f) (pick '(:type :guard)))
        t)
       (:context (let ((old (prog-ctx q)))
                   (setf (prog-ctx q) (random-context q))
                   (setf (getf (prog-ctx q) :mv-as-list) (getf old :mv-as-list))
                   (setf (getf (prog-ctx q) :all-styles)
                         (remove-if (lambda (n) (fn-inline (find n (prog-fns q) :key #'fn-name)))
                                    (getf (prog-ctx q) :all-styles)))
                   t))
       (:mv-as-list
        (let ((mvs (remove-if-not (lambda (g) (and (consp (fn-rtype g)) (eq (car (fn-rtype g)) :mv)
                                                   (consp (fn-ir g)) (eq (car (fn-ir g)) 'mv)
                                                   (not (member (fn-name g)
                                                                (getf (prog-ctx q) :all-styles)))))
                                  (prog-fns q))))
          (when mvs
            (setf (getf (prog-ctx q) :mv-as-list)
                  (adjoin (fn-name (pick mvs)) (getf (prog-ctx q) :mv-as-list)))
            t))))
     kind)))

(defun make-variant (p)
  "(values variant rewrites) : P with 2 to 6 rewrites applied, validated."
  (loop repeat 20
        do (let ((q (copy-prog-deep p)) (names nil))
             (dotimes (i (+ 2 (rnd 5)))
               (let ((k (handler-case (meta-step q) (error () nil)))) (when k (push k names))))
             (when (and names (validate-prog q)) (return (values q (nreverse names)))))))

(let* ((args (last sb-ext:*posix-argv* 5))
       (seed (parse-integer (first args))) (nfns (parse-integer (second args)))
       (nvar (parse-integer (third args))) (w (fourth args)) (host (fifth args))
       (p (make-prog seed nfns))
       (variants nil) (dirs nil) (status 0))
  (setf *rs* (sb-ext:seed-random-state (+ seed 777)))
  (dotimes (i nvar)
    (multiple-value-bind (q names) (make-variant p)
      (when q (push (cons q names) variants))))
  (setf variants (nreverse variants))
  (loop for (q . nil) in (cons (cons p nil) variants) for i from 0
        do (let ((dir (format nil "~Av~D/" w i)))
             (ensure-directories-exist dir)
             (dolist (f (directory (format nil "~A*.*" dir))) (delete-file f))
             (emit-prog q dir) (push dir dirs)))
  (setf dirs (nreverse dirs))
  (with-open-file (log (format nil "~Ameta.txt" w) :direction :output :if-exists :supersede)
    (let ((per-host nil))
      (dolist (h (cond ((equal host "both") '(:head :ccl)) ((equal host "ccl") '(:ccl)) (t '(:head))))
        (let* ((results (run-batch-robust dirs w :host h :cov nil :timeout (* 60 (length dirs))
                                                 :tag (format nil "meta-~(~A~)" h)))
               (base (first results)) (agree 0))
          (push (q-lines base) per-host)
          (format log "~(~A~) original: valid ~A (~A) answered ~D/~D~%" h (res-valid base)
                  (res-reason base) (res-answered base) (res-queries base))
          (unless (res-valid base) (setf status 1))
          (loop for r in (rest results) for (nil . names) in variants for i from 1
                do (let ((same (equal (q-lines r) (q-lines base))))
                     (if (and same (res-valid r)) (incf agree) (setf status 1))
                     (format log "~(~A~) v~D ~:[INVALID ~A~;valid~*~] ~:[RECORDS DIFFER~;same~] ~(~A~)~%"
                             h i (res-valid r) (res-reason r) same names)))
          (format t "~(~A~): seed ~D original valid=~A answered ~D/~D; ~D/~D variants agree~%"
                  h seed (res-valid base) (res-answered base) (res-queries base) agree
                  (length variants))))
      (when (and (cdr per-host) (not (equal (first per-host) (second per-host))))
        (setf status 1)
        (format log "CROSS-HOST: residues differ~%") (format t "CROSS-HOST residue difference~%"))))
  (sb-ext:exit :code status :abort t))
