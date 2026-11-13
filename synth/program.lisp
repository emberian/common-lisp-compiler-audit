;;;; Programs as data: creation, table installation, validation, (de)serialization.

(defstruct (pg (:conc-name prog-) (:constructor %make-prog))
  seed elem fields features kinds
  consts            ; literal constants: (name . type)
  computed          ; (fn-name const-name args): DEFCONST evaluated by raw code at admission
  fns               ; in admission order
  ctx)              ; context envelope, a plist (see context.lisp)

(defvar *nq* 8 "Queries per function.")

(defun any-arg ()
  (case (rnd 12)
    (0 (random-const)) (1 (rnd 100))
    (2 (car (lit-rat -50 50 nil)))
    (3 (car (lit-char 0 255)))
    (4 (car (lit-str 0 8 0 255)))
    (5 `(quote ,(pick '(zsa zsb :zka nil t car zzz))))
    (6 ''(1 . 2)) (7 ''(zsa "b" 3 #\c 2/3)) (8 nil) (9 ''((1 2) (3)))
    (10 (- (rnd 20) 10))
    (t (pow2 (pick *seam-bits*)))))

(defun arg-for (ty)
  (cond ((intp* ty) (const-in (second ty) (third ty)))
        ((ratp* ty) (if (chance 25) (const-in (second ty) (third ty))
                        (car (lit-rat (second ty) (third ty) (fourth ty)))))
        ((charp* ty) (car (lit-char (second ty) (third ty))))
        ((dfp* ty) `(to-df ,(if (chance 30) (const-in (second ty) (third ty))
                               (car (lit-rat (max -100 (second ty)) (min 100 (third ty)) nil)))))
        ((strp* ty) (car (lit-str (second ty) (third ty) (fourth ty) (fifth ty))))
        ((eq ty :sym) (let ((s (pick *sym-pool*))) (if (keywordp s) s `(quote ,s))))
        ((eq ty :any) (any-arg))
        ((listp* ty)
         (let ((n (rnd 9)))
           (if (= n 0) nil
               `(quote ,(loop repeat n collect (const-in (fourth ty) (fifth ty)))))))
        (t 'zst)))

(defun query-args (f) (mapcar #'arg-for (fn-ptypes f)))
(defun fresh-queries (f)
  (setf (fn-queries f) (loop repeat *nq* collect (cons (rnd 1000) (query-args f)))))

(defun mates (f p)
  (if (fn-clique f)
      (remove-if-not (lambda (g) (equal (fn-clique g) (fn-clique f))) (prog-fns p))
      (list f)))

(defun zf-name-p (s)
  (and (symbolp s) s (> (length (symbol-name s)) 2)
       (string= "ZF" (symbol-name s) :end2 2)
       (digit-char-p (char (symbol-name s) 2))))

(defun calls-in (tree)
  "Every (ZFn ...) call form in TREE."
  (let (out)
    (labels ((walk (x)
               (when (consp x)
                 (when (and (zf-name-p (car x)) (listp (cdr x))) (push x out))
                 (unless (eq (car x) 'quote)
                   (loop for y on x while (consp y) do (walk (car y)))))))
      (walk tree))
    out))

(defun install-base (p)
  (setf *fns* (make-hash-table) *int-fns* nil *mv-fns* nil *list-fns* nil *val-fns* nil
        *st-read-fns* nil *st-upd-fns* nil
        *elem* (prog-elem p) *fields* (prog-fields p) *feats* (prog-features p)
        *consts* (copy-list (prog-consts p))))

(defun note-computed (f p)
  (let ((k (find (fn-name f) (prog-computed p) :key #'first)))
    (when k (push (cons (second k) (fn-rtype f)) *consts*))))

(defun install-prog (p &optional before)
  "Set the program-level tables as they stand once every function (or every
function admitted before BEFORE's group) has been admitted."
  (install-base p)
  (let ((stop (and before (mates before p))))
    (dolist (f (prog-fns p))
      (when (member f stop) (return))
      (register f) (publish f) (note-computed f p)))
  p)

(defun recursive-shape-ok (f group)
  "A function with a measure is (if (zp n) BASE STEP) or (if (endp l) BASE STEP),
possibly under LETs that do not rebind the measured variable, with its recursive
call inside STEP.  Mutation must not touch the test: the recursion would not end."
  (let* ((m (fn-measure f)) (v (second m)) (ir (fn-ir f)))
    (loop while (and (consp ir) (eq (car ir) 'let) (= (length ir) 3)
                     (not (member v (second ir) :key #'first)))
          do (setf ir (third ir)))
    (and (consp ir) (eq (car ir) 'if)
         (equal (second ir) (if (eq (car m) 'nfix) `(zp ,v) `(endp ,v)))
         (null (remove-if-not (lambda (c) (member (car c) group :key #'fn-name))
                              (calls-in (third ir))))
         (not (free-binder-of v (fourth ir))))))

(defun free-binder-of (v form)
  "Does FORM bind V anywhere (LET, LET*, MV-LET, LOOP$)?  Conservative."
  (and (consp form) (not (eq (car form) 'quote))
       (or (and (member (car form) '(let let*)) (listp (second form))
                (member v (second form) :key (lambda (b) (and (consp b) (first b)))))
           (and (member (car form) '(mv-let lambda$)) (listp (second form)) (member v (second form)))
           (and (eq (car form) 'loop$) (eq (third form) v))
           (some (lambda (x) (free-binder-of v x)) (cdr form)))))

(defun recursion-ok (f group earlier)
  "Calls go only to earlier functions, or to F's own group in the one decreasing
shape; a function with a measure keeps exactly one such call (ACL2 rejects a
measure on a non-recursive function), one without has none."
  (let ((own 0))
    (dolist (c (calls-in (fn-ir f)) (= own (if (fn-measure f) 1 0)))
      (cond ((member (car c) earlier))
            ((member (car c) group :key #'fn-name)
             (incf own)
             (let* ((callee (find (car c) group :key #'fn-name))
                    (m (fn-measure callee))
                    (pos (and m (position (second m) (fn-params callee))))
                    (arg (and pos (nth pos (cdr c)))))
               (unless (and m (equal arg (if (eq (car m) 'nfix) `(- ,(second m) 1) `(cdr ,(second m)))))
                 (return nil))))
            (t (return nil))))))

(defun validate-prog (p)
  "T, or (values NIL reason).  Leaves the tables installed for the whole program."
  (install-base p)
  (let ((done nil) (earlier nil) (*tainted* nil))
    (dolist (f (prog-fns p) t)
      (unless (member f done)
        (let ((group (mates f p)))
          (dolist (g group) (register g))
          (dolist (g group)
            (let ((chk (valid-or-nil
                         (infer (fn-ir g) (mapcar #'cons (fn-params g) (fn-ptypes g))))))
              (unless (and chk (sub-p (first chk) (fn-rtype g)))
                (return-from validate-prog (values nil (list (fn-name g) :type))))
              (unless (and (recursion-ok g group earlier)
                           (or (null (fn-measure g)) (recursive-shape-ok g group)))
                (return-from validate-prog (values nil (list (fn-name g) :recursion))))))
          ;; ACL2 forbids DEFCONST to depend, even ancestrally, on LOOP$ or LAMBDA$.
          (when (some (lambda (g) (tainted-p (fn-ir g))) group)
            (dolist (g group) (push (fn-name g) *tainted*))
            (when (some (lambda (g) (find (fn-name g) (prog-computed p) :key #'first)) group)
              (return-from validate-prog (values nil (list (fn-name f) :defconst-on-loop$)))))
          (dolist (g group)
            (publish g) (note-computed g p) (push (fn-name g) earlier))
          (setf done (append group done)))))))

;;;; Creation

(defun make-prog (seed nfns &key (features :swarm) ctx)
  (setf *rs* (sb-ext:seed-random-state seed))
  (let* ((p (%make-prog :seed seed :elem (random-int-type)))
         (use-st (chance 70))
         (kinds nil) (fns nil) (idx 0))
    (setf (prog-fields p) (and use-st (make-fields))
          (prog-features p)
          (if (eq features :swarm)
              (and (chance 85) (remove-if (lambda (f) (declare (ignore f)) (chance 55)) *all-features*))
              features)
          (prog-consts p) (loop for i below 3
                                collect (let ((c (random-const)))
                                          (cons (intern (format nil "*ZC~D*" i) :zs) (ti c c)))))
    (install-base p)
    ;; Swarm: each program draws its own subset of function kinds.
    (setf kinds (let ((all (append '(:plain :plain :inline :mv :loop :rec :fold :map :loop$)
                                   (when use-st '(:st-upd :st-upd :st-loop :st-read))
                                   (when (member :any *feats*) '(:dispatch :dispatch)))))
                  (or (remove-if (lambda (k) (declare (ignore k)) (chance 25)) all) all))
          (prog-kinds p) (remove-duplicates kinds))
    (let ((*tainted* nil))
      (loop while (< idx nfns)
            do (if (and (chance 12) (< (1+ idx) nfns))
                   (let ((pair (make-mutual idx (+ 2 (rnd 2)))))
                     (when pair
                       (when (some (lambda (g) (tainted-p (fn-ir g))) pair)
                         (dolist (g pair) (push (fn-name g) *tainted*)))
                       (setf fns (append (reverse pair) fns)) (incf idx 2)))
                   (let ((f (make-function idx kinds)))
                     (push f fns) (incf idx)
                     ;; ACL2 forbids DEFCONST to depend, even ancestrally, on LOOP$ or LAMBDA$.
                     (when (tainted-p (fn-ir f)) (push (fn-name f) *tainted*))
                     (when (and (intp* (fn-rtype f)) (every #'intp* (fn-ptypes f))
                                (not (member (fn-name f) *tainted*)) (chance 30))
                       (let ((name (intern (format nil "*ZK~D*" idx) :zs)))
                         (push (list (fn-name f) name (query-args f)) (prog-computed p))
                         (push (cons name (fn-rtype f)) *consts*)))))))
    (setf (prog-fns p) (nreverse fns))
    (dolist (f (prog-fns p)) (fresh-queries f))
    (setf (prog-ctx p) (or ctx (random-context p)))
    p))

;;;; Serialization (symbols are read back into package ZS)

(defun fn->sexp (f)
  (list :name (fn-name f) :params (fn-params f) :ptypes (fn-ptypes f) :rtype (fn-rtype f)
        :ir (fn-ir f) :kind (fn-kind f) :measure (fn-measure f) :inline (fn-inline f)
        :clique (fn-clique f) :style (fn-style f) :ann-seed (fn-ann-seed f)
        :density (fn-density f) :gmode (fn-gmode f) :queries (fn-queries f)))

(defun prog->sexp (p)
  (list :seed (prog-seed p) :elem (prog-elem p) :fields (prog-fields p)
        :features (prog-features p) :kinds (prog-kinds p) :consts (prog-consts p)
        :computed (prog-computed p) :ctx (prog-ctx p)
        :fns (mapcar #'fn->sexp (prog-fns p))))

(defun sexp->prog (x)
  (let ((p (apply #'%make-prog (loop for (k v) on x by #'cddr
                                    unless (eq k :fns) append (list k v)))))
    (setf (prog-fns p) (mapcar (lambda (fx) (apply #'make-fn fx)) (getf x :fns)))
    p))

(defmacro with-zs-io (&body body)
  `(let ((*package* (find-package :zs)) (*print-pretty* nil) (*print-case* :downcase)
         (*print-right-margin* 1000000) (*print-readably* nil) (*print-length* nil)
         (*print-level* nil) (*read-default-float-format* 'double-float))
     ,@body))

(defun save-prog (p path)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (with-zs-io (prin1 (prog->sexp p) s) (terpri s))))

(defun load-prog (path)
  (with-open-file (s path) (with-zs-io (sexp->prog (read s)))))

(defun copy-prog-deep (p)
  (with-zs-io (sexp->prog (read-from-string (prin1-to-string (prog->sexp p))))))
