;;;; Functions

(defstruct fn name params ptypes rtype
  ir                ; body with no THE and no declarations (what mutation works on)
  body              ; annotated body, computed from IR at emission
  kind measure inline clique style
  (ann-seed 0) (density 0)  ; annotation is a function of these and the IR
  (gmode :type)     ; integer parameters declared by TYPE, or only by a :GUARD
  queries)          ; list of (stobj-seed . argument forms)

(defun spec-for (ty)
  "A declaration for an integer parameter, exact for byte-shaped ranges (or the
type of a double-float or character stobj field)."
  (let ((lo (second ty)) (hi (third ty)))
    (cond ((dfp* ty) 'double-float)
          ((charp* ty) 'character)
          ((and (< lo 0) (= lo (- -1 hi)) (= (logcount (1+ hi)) 1))
           `(signed-byte ,(1+ (integer-length hi))))
          ((and (= lo 0) (>= hi 1) (= (logcount (1+ hi)) 1)) `(unsigned-byte ,(integer-length hi)))
          (t `(integer ,lo ,hi)))))

(defun register (f)
  (setf (gethash (fn-name f) *fns*) (list (fn-ptypes f) (fn-rtype f))))

(defun publish (f)
  "Make F callable from later functions."
  (let ((entry (list (fn-name f) (fn-ptypes f) (fn-rtype f))) (rty (fn-rtype f)))
    (cond ((eq (fn-kind f) :dispatch) nil)
          ((eq rty :st) (push entry *st-upd-fns*))
          ((member :st (fn-ptypes f)) (push entry *st-read-fns*))
          ((intp* rty) (push entry *int-fns*))
          ((listp* rty) (push entry *list-fns*))
          ((value-type-p rty) (push entry *val-fns*))
          ((and (consp rty) (eq (car rty) :mv)) (push entry *mv-fns*)))))

(defun random-param-type ()
  (case (and *feats* (chance 45) (pick *feats*))
    (:rat (let ((a (random-const)) (b (random-const)))
            (list :rat (min a b) (max a b) (pick '(1000 16 7 65536)))))
    (:char (pick (list (tc 0 255) (tc 0 255) (tc 32 126) (tc 97 122))))
    (:str (pick (list (ts 0 8 0 255) (ts 1 8 0 255) (ts 2 6 32 126) (ts 0 3 0 255))))
    (:sym :sym)
    (:any :any)
    (:df (pick (list (tdf -1024 1024) (tdf 0 4096) (tdf (- (pow2 40)) (pow2 40)))))
    (:word (pick *edge-types*))
    (t (random-int-type))))

(defun int-params (n)
  (loop for i below n collect (cons (intern (format nil "X~D" i) :zs) (random-param-type))))

(defun field-value (d env fty)
  "An expression storable in a stobj field of type FTY."
  (cond ((intp* fty) (fit-type (gen-int d env) fty))
        ((dfp* fty) (let ((e (if (member :df *feats*) (gen-df d env) (lit 0))))
                      (if (and (dfp* (cdr e)) (sub-p (cdr e) fty))
                          e
                          (op1 'to-df (fit-int (gen-int d env) -1024 1024)))))
        (t (gen-of-type fty d env))))

(defun field-initial (fty)
  (cond ((dfp* fty) 0) ((charp* fty) #\a)
        (t (max (second fty) (min 0 (third fty))))))

(defun digest-term (form fty)
  "FORM (a field read) as an integer."
  (cond ((dfp* fty) `(floor (* 1024 (from-df ,form)) 1))
        ((charp* fty) `(char-code ,form))
        (t form)))

(defun stobj-update (d env)
  "One form of type :st."
  (destructuring-bind (acc upd fty len) (pick *fields*)
    (declare (ignore acc))
    (let ((u (if len
                 `(,upd ,(car (fit-int (gen-int (1- d) env) 0 (1- len)))
                        ,(car (field-value d env fty)) zst)
                 `(,upd ,(car (field-value d env fty)) zst))))
      (cond ((and *st-upd-fns* (chance 25))
             (destructuring-bind (name ptys rty) (pick *st-upd-fns*)
               (declare (ignore rty))
               `(,name ,@(call-args ptys d env))))
            ((chance 25) `(if ,(car (gen-bool (1- d) env)) ,u zst))
            (t u)))))

(defun stobj-seq (d env)
  `(let* ,(loop repeat (1+ (rnd 4)) collect `(zst ,(stobj-update d env))) zst))

(defun build (name kind depth)
  "A fresh FN of KIND (body not yet validated or annotated)."
  (let* ((*gensym* 0)
         (xs (int-params (1+ (rnd 3))))
         (xnames (mapcar #'car xs)) (xtys (mapcar #'cdr xs))
         (env (copy-alist xs))
         (n 'n) (k (pick '(2 5 9 20))) (nty (ti 0 k))
         (r (random-int-type)) (lt (list-type))
         (stenv (acons 'zst :st env)))
    (flet ((mk (params ptypes rtype body &rest more)
             (apply #'make-fn :name name :params params :ptypes ptypes :rtype rtype
                              :body body :kind kind more))
           (self (&rest args) `(,name ,@args)))
      (ecase kind
        ((:plain :inline)
         (if (chance 30)
             (let ((body (gen-int depth (acons 'l lt env))))
               (mk (append xnames '(l)) (append xtys (list lt)) (cdr body) (car body)
                   :inline (eq kind :inline)))
             (let ((body (case (and *feats* (chance 30) (pick *feats*))
                           (:rat (gen-rat depth env)) (:char (gen-char depth env))
                           (:str (gen-str depth env)) (:sym (gen-sym depth env))
                           (:listx (gen-list depth env))
                           (t (gen-int depth env)))))
               (mk xnames xtys (cdr body) (car body) :inline (eq kind :inline)))))
        (:dispatch
         ;; One untyped parameter V (guard T), classified by type tests; each arm
         ;; sees V at the type its test establishes.
         (let* ((it (random-int-type)) (ilo (second it)) (ihi (third it))
                (arms (list (list `(and (integerp v) (and (>= v ,ilo) (<= v ,ihi))) it :word)
                            (list '(characterp v) (tc 0 255) :char)
                            (list '(and (stringp v) (<= (length v) 8)) (ts 0 8 0 255) :str)
                            (list '(symbolp v) :sym :sym)
                            (list '(consp v) :pair :any)
                            (list `(and (rationalp v) (and (>= v ,ilo) (<= v ,ihi)))
                                  (list :rat ilo ihi nil) :rat)))
                (arms (let ((a (copy-list arms)))   ; random order, random subset of >= 2
                        (loop for i from (length a) downto 2
                              do (rotatef (nth (rnd i) a) (nth (1- i) a)))
                        (subseq a 0 (+ 2 (rnd (- (length a) 1))))))
                (body (car (fit-type (gen-int (1- depth) (acons 'v :any env)) r))))
           (dolist (arm (reverse arms))
             (destructuring-bind (test vty f) arm
               (let ((*feats* (adjoin f *feats*)) (*feature-bias* 60))
                 (setf body `(if ,test
                                 ,(car (fit-type (gen-int depth (acons 'v vty env)) r))
                                 ,body)))))
           (mk (append xnames '(v)) (append xtys '(:any)) r body)))
        (:mv (let ((a (gen-int depth env)) (b (gen-int depth env)))
               (mk xnames xtys (list :mv (cdr a) (cdr b)) `(mv ,(car a) ,(car b)))))
        (:loop
         (let ((f (mk (append xnames (list n 'acc)) (append xtys (list nty r)) r nil
                      :measure '(nfix n))))
           (register f)
           (setf (fn-body f)
                 `(if (zp n) acc
                      ,(apply #'self (append xnames
                                             (list '(- n 1)
                                                   (car (fit-type
                                                         (gen-int depth
                                                                  (list* (cons 'acc r) (cons n nty) env))
                                                         r)))))))
           f))
        (:rec
         (let ((f (mk (append xnames (list n)) (append xtys (list nty)) r nil
                      :measure '(nfix n))))
           (register f)
           (setf (fn-body f)
                 `(if (zp n) ,(car (fit-type (gen-int (1- depth) env) r))
                      (let ((rv ,(apply #'self (append xnames (list '(- n 1))))))
                        ,(car (fit-type (gen-int depth (list* (cons 'rv r) (cons n nty) env))
                                        r)))))
           f))
        (:fold
         (let ((f (mk (append '(l acc) xnames) (append (list lt r) xtys) r nil
                      :measure '(acl2-count l))))
           (register f)
           (setf (fn-body f)
                 `(if (endp l) acc
                      ,(apply #'self '(cdr l)
                              (car (fit-type
                                    (gen-int depth
                                             (list* (cons 'l (tl 1 *ncap* (fourth lt) (fifth lt)))
                                                    (cons 'acc r) env))
                                    r))
                              xnames)))
           f))
        (:map
         (let ((f (mk (cons 'l xnames) (cons lt xtys) lt nil :measure '(acl2-count l))))
           (register f)
           (setf (fn-body f)
                 `(if (endp l) nil
                      (cons ,(car (fit-type
                                   (gen-int depth (acons 'l (tl 1 *ncap* (fourth lt) (fifth lt))
                                                         env))
                                   *elem*))
                            ,(apply #'self '(cdr l) xnames))))
           f))
        (:loop$
         (let* ((lenv (acons 'l lt env)))
           (if (chance 40)
               (let ((body (gen-list depth lenv)))
                 (mk (cons 'l xnames) (cons lt xtys) lt (car body)))
               (let ((body (gen-int depth lenv)))
                 (mk (cons 'l xnames) (cons lt xtys) (cdr body) (car body))))))
        (:st-upd
         (mk (append xnames '(zst)) (append xtys '(:st)) :st (stobj-seq depth stenv)))
        (:st-loop
         (let ((f (mk (append xnames (list n 'zst)) (append xtys (list nty :st)) :st nil
                      :measure '(nfix n))))
           (register f)
           (setf (fn-body f)
                 `(if (zp n) zst
                      (let* ,(loop repeat (1+ (rnd 3))
                                   collect `(zst ,(stobj-update depth (acons n nty stenv))))
                        ,(apply #'self (append xnames '((- n 1) zst))))))
           f))
        (:st-read
         (let ((body (tame (op2 (pick '(+ logxor -)) (stobj-read depth stenv)
                                (gen-int depth stenv)))))
           (mk (append xnames '(zst)) (append xtys '(:st)) (cdr body) (car body))))))))

(defun finish (f density)
  "Validate F's body with INFER and fix its annotation parameters.  NIL if invalid."
  (let ((env (mapcar #'cons (fn-params f) (fn-ptypes f))))
    (register f)
    (let ((chk (valid-or-nil (infer (fn-body f) env))))
      (cond ((and chk (sub-p (first chk) (fn-rtype f)))
             (setf (fn-ir f) (fn-body f) (fn-body f) nil
                   (fn-density f) density (fn-ann-seed f) (rnd 1000000)
                   (fn-gmode f) (if (chance 20) :guard :type))
             f)
            (t (remhash (fn-name f) *fns*) nil)))))

(defvar *depth-base* 2)
(defun make-function (idx kinds)
  (let ((name (intern (format nil "ZF~D" idx) :zs)))
    (loop repeat 8
          do (let* ((kind (pick kinds))
                    (f (valid-or-nil (build name kind (+ *depth-base* (rnd 3)))))
                    (g (and f (finish (first f) (pick '(0 15 30 60))))))
               (when g
                 (unless (fn-inline g)
                   (setf (fn-style g) (if (chance 45) nil (pick (cdr *styles*)))))
                 (publish g) (return g))
               (remhash name *fns*))
          finally (let ((f (make-fn :name name :params '(x0) :ptypes (list (ti -8 8))
                                    :rtype (ti -7 9) :body (list '+ 'x0 1) :kind :plain)))
                    (return (progn (finish f 0) (publish f) f))))))

(defun make-mutual (idx depth)
  "Two mutually recursive counter functions sharing an accumulator type."
  (let* ((*gensym* 0)
         (a (intern (format nil "ZF~D" idx) :zs)) (b (intern (format nil "ZF~D" (1+ idx)) :zs))
         (xs (int-params (1+ (rnd 2)))) (xnames (mapcar #'car xs)) (xtys (mapcar #'cdr xs))
         (k (pick '(3 6 11))) (nty (ti 0 k)) (r (random-int-type))
         (env (list* (cons 'acc r) (cons 'n nty) (copy-alist xs)))
         (params (append xnames '(n acc))) (ptys (append xtys (list nty r))))
    (flet ((one (name other base)
             (make-fn :name name :params params :ptypes ptys :rtype r :kind :mutual
                      :measure '(nfix n) :clique (list a b)
                      :body `(if (zp n) ,base
                                 (,other ,@xnames (- n 1)
                                         ,(car (fit-type (gen-int depth env) r)))))))
      (let ((fa (one a b 'acc))
            (fb (one b a (car (fit-type (gen-int (1- depth) (remove 'n env :key #'car)) r)))))
        (register fa) (register fb)
        (let ((ga (finish fa (pick '(0 30 60)))) (gb (finish fb (pick '(0 30 60)))))
          (cond ((and ga gb) (publish ga) (publish gb) (list ga gb))
                (t (remhash a *fns*) (remhash b *fns*) nil)))))))

;;;; Stobj layout and helpers

(defun make-fields ()
  (let ((out nil) (i 0))
    (dotimes (j (1+ (rnd 3)))
      (let ((ty (case (rnd 8) (0 (tdf -4096 4096)) (1 (tc 0 255)) (t (random-int-type)))))
        (push (list (intern (format nil "ZSC~D" i) :zs) (intern (format nil "UPDATE-ZSC~D" i) :zs)
                    ty nil)
              out)
        (incf i)))
    (dotimes (j (1+ (rnd 2)))
      (let ((ty (pick (list (ti 0 255) (ti 0 65535) (ti 0 (1- (pow2 32))) (ti 0 (1- (pow2 64)))
                            (ti (- (pow2 63)) (1- (pow2 63))) (ti (- (pow2 29)) (1- (pow2 29)))
                            (ti 0 1) (ti (- (pow2 61)) (1- (pow2 61))) (random-int-type)
                            (ti 0 3) (ti 0 15) (ti 0 127) (ti 0 32767) (ti 0 (1- (pow2 31)))
                            (ti 0 (1- (pow2 63))) (ti -128 127) (ti -32768 32767)
                            (ti (- (pow2 31)) (1- (pow2 31))) (ti (- (pow2 62)) (1- (pow2 62)))
                            (ti 0 (1- (pow2 62))) (ti 0 (1- (pow2 61)))
                            (tdf -4096 4096) (tdf -4096 4096) (tc 0 255)))))
        (push (list (intern (format nil "ZAR~DI" i) :zs) (intern (format nil "UPDATE-ZAR~DI" i) :zs)
                    ty (pick '(1 2 4 7 16)))
              out)
        (incf i)))
    (nreverse out)))

(defun field-name (f)                   ; ZSC0 or ZAR1 (accessor minus trailing I)
  (let ((s (symbol-name (first f))))
    (intern (if (fourth f) (subseq s 0 (1- (length s))) s) :zs)))

(defun stobj-helpers ()
  "DEFSTOBJ plus ZRESET (deterministic fill from a seed) and ZDIG (digest)."
  (let ((forms nil) (resets nil) (terms nil))
    (push `(defstobj zst
             ,@(loop for f in *fields*
                     collect (if (fourth f)
                                 `(,(field-name f) :type (array ,(spec-for (third f)) (,(fourth f)))
                                                   :initially ,(field-initial (third f))
                                                   :resizable ,(oddp (+ (fourth f)
                                                                        (integer-length (third (third f))))))
                                 `(,(field-name f) :type ,(spec-for (third f))
                                                   :initially ,(field-initial (third f)))))
             ,@(when *stobj-inline* '(:inline t)))
          forms)
    (loop for f in *fields* for j from 1
          do (destructuring-bind (acc upd fty len) f
               (let ((val (lambda (ix)
                            (let ((e (cons `(+ (* k ,(+ 3 (* 7 j))) (* ,ix ,(+ 11 j)) ,j)
                                           (ti 0 (pow2 20)))))
                              (cond ((dfp* fty) `(to-df (/ ,(car (fit-int e -2048 2047)) 4)))
                                    ((charp* fty) `(code-char ,(car (fit-int e 0 255))))
                                    (t (car (fit-type e fty))))))))
                 (if len
                     (let ((fill (intern (format nil "ZFILL~D" j) :zs))
                           (sum (intern (format nil "ZSUM~D" j) :zs)))
                       (push `(skip-proofs
                               (defun ,fill (i k zst)
                                 (declare (xargs :stobjs zst :verify-guards nil :measure (nfix i)))
                                 (if (zp i) zst
                                     (let ((zst (,upd (- i 1) ,(funcall val 'i) zst)))
                                       (,fill (- i 1) k zst)))))
                             forms)
                       (push `(skip-proofs
                               (defun ,sum (i acc zst)
                                 (declare (xargs :stobjs zst :verify-guards nil :measure (nfix i)))
                                 (if (zp i) acc
                                     (,sum (- i 1) (+ (* 31 acc) ,(digest-term `(,acc (- i 1) zst) fty)) zst))))
                             forms)
                       (push `(zst (,fill ,len k zst)) resets)
                       (push `(,sum ,len ,j zst) terms))
                     (progn (push `(zst (,upd ,(funcall val 1) zst)) resets)
                            (push `(* ,(+ 5 j) ,(digest-term `(,acc zst) fty)) terms))))))
    (push `(skip-proofs (defun zreset (k zst)
                          (declare (xargs :stobjs zst :verify-guards nil))
                          (let* ,(reverse resets) zst)))
          forms)
    (push `(skip-proofs (defun zdig (zst)
                          (declare (xargs :stobjs zst :verify-guards nil))
                          (+ ,@(reverse terms))))
          forms)
    (nreverse forms)))
