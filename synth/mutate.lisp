;;;; IR mutation.  A mutant is a deep copy of a corpus program with one or more
;;;; changes; it is kept only if VALIDATE-PROG accepts it.

(defmacro safely (&body body)
  "First value of BODY, or NIL if it threw INVALID or signalled an error."
  `(handler-case (first (valid-or-nil ,@body)) (error () nil)))

(defun site-ok (s)
  (let ((ty (third s)))
    (and (consp (first s))
         (or (eq ty :bool) (small-int-p ty) (charp* ty) (strp* ty) (eq ty :sym) (listp* ty)
             (and (ratp* ty) (< (integer-length (third ty)) 300))))))

(defun fn-sites (f p)
  "Mutable sites of F: (form env type restricted).  Leaves the tables as they are
just before F is admitted, with F's own group registered (so self-calls infer)."
  (install-prog p f)
  (dolist (g (mates f p)) (register g))
  (let ((cell (list nil)))
    (let ((*trace* cell))
      (safely (infer (fn-ir f) (mapcar #'cons (fn-params f) (fn-ptypes f)))))
    (remove-if-not #'site-ok (car cell))))

(defparameter *swap-classes*
  '((+ - *) (logand logior logxor logeqv logandc1 logandc2 lognand lognor logorc1 logorc2)
    (floor truncate mod rem ceiling round) (< <= > >= = /=) (min max) (1+ 1-)
    (integer-length logcount) (char< char> char<= char>=) (string< string> string<= string>=)
    (evenp oddp) (zerop plusp minusp) (char-upcase char-downcase) (string-upcase string-downcase)
    (union$ intersection$ set-difference$) (and or)))

(defun boundary-near (c)
  (let ((k (pick *edge-widths*)))
    (pick (list (1+ c) (1- c) (- c) (pow2 k) (1- (pow2 k)) (- (pow2 (1- k))) (1- (pow2 (1- k)))
                (pow2 (1- k)) (- (pow2 k)) 0 1 -1))))

(defun var-class (ty)
  (cond ((intp* ty) :int) ((ratp* ty) :rat) ((charp* ty) :char) ((strp* ty) :str) ((dfp* ty) :df)
        ((listp* ty) :list) (t ty)))

(defun adapt-donor (form denv env)
  "FORM (from another function, typed under DENV) with its variables replaced by
variables of the same class in ENV, or by a literal.  One donor variable always
maps to the same replacement (the two sides of an MBE must stay equal)."
  (let ((map nil))
   (labels ((walk (x)
             (cond ((and (symbolp x) x (assoc x denv))
                    (cdr (or (assoc x map)
                             (car (push (cons x
                                              (let* ((cls (var-class (cdr (assoc x denv))))
                                                     (cands (remove-if-not
                                                             (lambda (b) (and (eq (var-class (cdr b)) cls)
                                                                              (or (not (eq cls :int))
                                                                                  (small-int-p (cdr b)))))
                                                             env)))
                                                (if cands (car (pick cands)) (arg-for (cdr (assoc x denv))))))
                                        map)))))
                   ((atom x) x)
                   ((eq (car x) 'quote) x)
                   (t (cons (car x) (mapcar #'walk (cdr x)))))))
    (walk form))))

(defun mutate-site (f p donors)
  "A new IR for F with one site changed, or NIL."
  (let* ((sites (fn-sites f p)) (site (and sites (pick sites))))
    (when site
      (destructuring-bind (form env ty restricted) site
        (let* ((*restrict* restricted)
               (*feats* (if (chance 50) (union *feats* (list (pick *all-features*))) *feats*))
               (*gensym* (+ 1000 (rnd 100000)))
               (new
                 (safely
                   (ecase (pick '(:regen :regen :swap :swap :const :splice :splice :word))
                     (:regen (gen-of-type ty (1+ (rnd 3)) env))
                     (:swap (let ((cls (find (car form) *swap-classes* :test #'member)))
                              (unless cls (invalid :no-swap))
                              (fit-to (typed (cons (pick (remove (car form) cls)) (cdr form)) env) ty)))
                     (:const (let ((pos (loop for a in (cdr form) for i from 1
                                              when (integerp a) collect i)))
                               (unless pos (invalid :no-constant))
                               (let ((c (copy-list form)) (i (pick pos)))
                                 (setf (nth i c) (boundary-near (nth i c)))
                                 (fit-to (typed c env) ty))))
                     (:splice (let* ((d (pick donors)))
                                (unless (and d (eq (var-class (third d)) (var-class ty))
                                             (null (calls-in (first d)))
                                             (not (mentions 'zst (first d)))
                                             (or (not restricted) (fourth d)))
                                  (invalid :no-donor))
                                (fit-to (typed (adapt-donor (first d) (second d) env) env) ty)))
                     (:word (unless (and (intp* ty) (not restricted)) (invalid :not-int))
                      (let* ((w (pick '(64 63 62 61 32))) (m (1- (pow2 w))) (e (cons form ty)))
                        (fit-to (ecase (rnd 4)
                                  (0 (op2 'logand (op2 (pick '(+ - *)) e (edge-operand 2 env)) (lit m)))
                                  (1 (op2 'logand (op2 'ash e (lit (rnd 65))) (lit m)))
                                  (2 (op2 (pick '(truncate floor ceiling round mod rem)) e
                                          (lit (pick *divisors*))))
                                  (3 (op2 'logand (op1 (pick '(lognot -)) e) (lit m))))
                                ty)))))))
          (and new (not (equal (car new) form))
               (subst (car new) form (fn-ir f) :test #'eq)))))))

(defun widen-param (f)
  "Declare one integer parameter at a machine-edge width that contains its old
range and clamp it back on entry (the body sees the old range)."
  (let* ((cands (loop for prm in (fn-params f) for ty in (fn-ptypes f) for i from 0
                      when (and (intp* ty) (char= (char (symbol-name prm) 0) #\X)
                                (some (lambda (e) (and (sub-p ty e) (not (equal ty e)))) *edge-types*))
                        collect i))
         (i (and cands (pick cands))))
    (when i
      (let* ((prm (nth i (fn-params f))) (old (nth i (fn-ptypes f)))
             (new (pick (remove-if-not (lambda (e) (and (sub-p old e) (not (equal old e))))
                                       *edge-types*)))
             (clamp (safely (fit-type (cons prm new) old))))
        (when clamp
          (setf (fn-ptypes f) (let ((l (copy-list (fn-ptypes f)))) (setf (nth i l) new) l)
                (fn-ir f) `(let ((,prm ,(car clamp))) ,(fn-ir f)))
          (fresh-queries f)
          t)))))

(defun all-sites (p)
  (loop for f in (prog-fns p) append (fn-sites f p)))

(defun mutate-prog (p donor-progs)
  "A valid mutant of P (deep copy), or NIL."
  (let* ((q (copy-prog-deep p))
         (donors (let ((d (and donor-progs (pick donor-progs)))) (and d (all-sites d))))
         (changed nil))
    (dotimes (k (1+ (rnd 3)))
      (let ((f (pick (prog-fns q))))
        (install-prog q)
        (case (rnd 12)
          ((0 1 2 3 4 5 6)
           (let ((ir (mutate-site f q donors)))
             (when ir (setf (fn-ir f) ir changed t))))
          (7 (when (widen-param f) (setf changed t)))
          (8 (unless (or (fn-clique f) (member :st (fn-ptypes f)))
               (setf (fn-inline f) (not (fn-inline f)) (fn-style f) nil changed t)))
          (9 (unless (or (fn-clique f) (fn-inline f))
               (setf (fn-style f) (pick *styles*) changed t)))
          (10 (setf (fn-ann-seed f) (rnd 1000000) (fn-density f) (pick '(0 15 30 60 100))
                    (fn-gmode f) (pick '(:type :type :guard)) changed t))
          (11 (setf (prog-ctx q) (random-context q) changed t)))))
    ;; an :all-styles copy of a function that became inline or stateful is not emitted
    (setf (getf (prog-ctx q) :all-styles)
          (remove-if (lambda (n) (let ((f (find n (prog-fns q) :key #'fn-name)))
                                   (or (null f) (fn-inline f) (fn-clique f))))
                     (getf (prog-ctx q) :all-styles)))
    (and changed (validate-prog q) q)))
