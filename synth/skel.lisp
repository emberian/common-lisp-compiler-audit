;;; Skeletal enumeration of binding and usage patterns (after Zhang, Sun, Su,
;;; PLDI 2017), crossed with context-envelope features.
;;;
;;; A skeleton is an IR tree with binder holes B and integer use holes (:u).
;;; Every way of filling the holes is enumerated up to renaming:
;;;   binder   the next unused name (a, b, c ...), or a name already in scope
;;;            (shadowing: the formal X, the formal L for loop variables, or the
;;;            innermost enclosing binder); duplicate names inside one LET /
;;;            MV-LET / LAMBDA$ parameter list are illegal in ACL2 and skipped
;;;   use      any integer variable in scope, or the constant 1
;;; so zero uses, shadowing and one variable in two roles all occur.  Each LET,
;;; LET* and MV-LET with unused variables is then emitted with no declaration,
;;; with IGNORE and with IGNORABLE.
;;;
;;; Known-failure exclusion, by exact shape: an unused, undeclared LET / LET* /
;;; MV-LET binding lexically inside a LOOP$ or LAMBDA$ body, in a book that
;;; relies on SET-IGNORE-OK (findings F1, F2).  They are counted, not emitted
;;; (pass KEEP-F1 to emit them and re-confirm the findings).
;;;
;;; Usage: sbcl --script skel.lisp OUTROOT/ [KEEP-F1]
;;; Writes OUTROOT/<context>/ (book.lisp, queries.lisp, ...) for every context
;;; and OUTROOT/counts.txt.
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)

(defparameter *fresh-names* '(a b c d e f))

(defparameter *skeletons*
  '((let1      (let ((B (:u))) (+ (:u) (:u))))
    (let2      (let ((B (:u)) (B (:u))) (+ (:u) (:u))))
    (let*2     (let* ((B (:u)) (B (:u))) (:u)))
    (let*3     (let* ((B 1) (B (:u)) (B (:u))) (:u)))
    (letlet    (let ((B (:u))) (let ((B (:u))) (:u))))
    (mvlet     (mv-let (B B) (mv (:u) (:u)) (+ (:u) (:u))))
    (lambda2   (apply$ (lambda$ (B B) (+ (:u) (:u))) (list (:u) (:u))))
    (loop-in   (loop$ for B in l sum (+ (:u) (:u))))
    (loop-from (loop$ for B from (:u) to 3 sum (+ (:u) (:u))))
    (loop-when (loop$ for B in l when (< (:u) 2) sum (:u)))
    (loop-alw  (if (loop$ for B in l always (< (:u) (:u))) 1 0))
    (loop-coll (len (loop$ for B in l collect (:u))))
    (loop-let  (loop$ for B in l sum (let ((B (:u))) (:u))))
    (lam-let   (apply$ (lambda$ (B) (let ((B (:u))) (:u))) (list (:u))))
    (let-loop  (let ((B (:u))) (loop$ for B in l sum (+ (:u) (:u)))))
    (loop-mv   (loop$ for B in l sum (mv-let (B B) (mv (:u) 1) (:u))))
    (loop-loop (loop$ for B in l sum (loop$ for B from 0 to 2 sum (+ (:u) (:u)))))
    (lam-loop  (apply$ (lambda$ (B) (loop$ for B from 0 to 2 sum (+ (:u) (:u)))) (list (:u))))
    (mac-let   (zm-sel (< (:u) 0) (let ((B (:u))) (:u)) (:u)))
    (loop-mac  (loop$ for B in l sum (zm-inc (let ((B (:u))) (:u)))))
    (flet1     (flet ((zlf (B) (+ (:u) 1))) (zlf (:u))))
    (loop-let* (loop$ for B in l sum (let* ((B (:u)) (B 1)) (:u))))))

(defun int-names (scope)
  "Distinct names visible as integers (innermost binding wins)."
  (let (seen out)
    (dolist (b scope (nreverse out))
      (unless (member (car b) seen)
        (push (car b) seen)
        (when (eq (cdr b) :int) (push (car b) out))))))

(defun binder-choices (scope n taken &key loop-var dup-ok)
  "((name . next-fresh-index) ...) for one binder hole."
  (let* ((inner (find-if (lambda (b) (and (eq (cdr b) :int) (not (member (car b) '(x l))))) scope))
         (cands (remove-duplicates
                 (append (list 'x) (when loop-var (list 'l)) (when inner (list (car inner))) taken))))
    (cons (cons (nth n *fresh-names*) (1+ n))
          (loop for c in cands
                when (or dup-ok (not (member c taken)))
                  collect (cons c n)))))

(declaim (ftype function ex))

(defun ex-seq (tpls scope n)
  (if (null tpls)
      (list (cons nil n))
      (loop for (f . n1) in (ex (car tpls) scope n)
            append (loop for (fs . n2) in (ex-seq (cdr tpls) scope n1)
                         collect (cons (cons f fs) n2)))))

(defun ex-binders (count scope n &key loop-var dup-ok)
  "All ways to name COUNT binders: ((names . n) ...)."
  (if (= count 0)
      (list (cons nil n))
      (loop for (rest . n1) in (ex-binders (1- count) scope n :loop-var loop-var :dup-ok dup-ok)
            append (loop for (name . n2) in (binder-choices scope n1 rest :loop-var loop-var
                                                                         :dup-ok dup-ok)
                         collect (cons (append rest (list name)) n2)))))

(defun bind (names scope) (append (reverse (mapcar (lambda (v) (cons v :int)) names)) scope))

(defun ex (tpl scope n)
  "All fillings of TPL: ((form . next-fresh-index) ...)."
  (cond ((equal tpl '(:u)) (loop for u in (append (int-names scope) '(1)) collect (cons u n)))
        ((atom tpl) (list (cons tpl n)))
        ((eq (car tpl) 'quote) (list (cons tpl n)))
        ((eq (car tpl) 'let)
         (destructuring-bind (bindings body) (cdr tpl)
           (loop for (es . n1) in (ex-seq (mapcar #'second bindings) scope n)
                 append (loop for (names . n2) in (ex-binders (length bindings) scope n1)
                              append (loop for (b . n3) in (ex body (bind names scope) n2)
                                           collect (cons `(let ,(mapcar #'list names es) ,b) n3))))))
        ((eq (car tpl) 'let*)
         (destructuring-bind (bindings body) (cdr tpl)
           (labels ((go-on (bs scope n acc taken)
                      (if (null bs)
                          (loop for (b . n3) in (ex body scope n)
                                collect (cons `(let* ,(reverse acc) ,b) n3))
                          (loop for (e . n1) in (ex (second (car bs)) scope n)
                                append (loop for (name . n2) in (binder-choices scope n1 taken :dup-ok t)
                                             append (go-on (cdr bs) (bind (list name) scope) n2
                                                           (cons (list name e) acc)
                                                           (cons name taken)))))))
             (go-on bindings scope n nil nil))))
        ((eq (car tpl) 'mv-let)
         (destructuring-bind (vars e body) (cdr tpl)
           (loop for (ef . n1) in (ex e scope n)
                 append (loop for (names . n2) in (ex-binders (length vars) scope n1)
                              append (loop for (b . n3) in (ex body (bind names scope) n2)
                                           collect (cons `(mv-let ,names ,ef ,b) n3))))))
        ((eq (car tpl) 'lambda$)
         (destructuring-bind (vars body) (cdr tpl)
           (loop for (names . n2) in (ex-binders (length vars) scope n)
                 append (loop for (b . n3) in (ex body (bind names nil) n2)
                              collect (cons `(lambda$ ,names ,b) n3)))))
        ((eq (car tpl) 'flet)
         (destructuring-bind (((fname (v) fbody)) call) (cdr tpl)
           (declare (ignore v))
           (loop for (c . n1) in (ex call scope n)
                 append (loop for (names . n2) in (ex-binders 1 scope n1)
                              append (loop for (b . n3) in (ex fbody (bind names nil) n2)
                                           collect (cons `(flet ((,fname ,names ,b)) ,c) n3))))))
        ((eq (car tpl) 'loop$)
         ;; (loop$ for B in E . rest) | (loop$ for B from E1 to E2 . rest)
         (let* ((in-p (eq (fourth tpl) 'in))
                (targets (if in-p (list (fifth tpl)) (list (fifth tpl) (seventh tpl))))
                (rest (nthcdr (if in-p 5 7) tpl)))
           (loop for (ts . n1) in (ex-seq targets scope n)
                 append (loop for (names . n2) in (ex-binders 1 scope n1 :loop-var t)
                              append (loop for (r . n3) in (ex-seq rest (bind names scope) n2)
                                           collect (cons `(loop$ for ,(first names)
                                                                 ,@(if in-p `(in ,(first ts))
                                                                       `(from ,(first ts) to ,(second ts)))
                                                                 ,@r)
                                                         n3))))))
        (t (loop for (args . n1) in (ex-seq (cdr tpl) scope n)
                 collect (cons (cons (car tpl) args) n1)))))

;;;; IGNORE / IGNORABLE variants

(defun unused-of (form)
  "Unused variables of the binder FORM (LET, LET*, MV-LET), or NIL."
  (let ((body (car (last form))))
    (case (car form)
      (let (loop for b in (second form)
                 unless (free-in (first b) body) collect (first b)))
      (let* (remove-duplicates
             (loop for (b . more) on (second form)
                   unless (free-in (first b) `(let* ,more ,body)) collect (first b))))
      (mv-let (remove-if (lambda (v) (free-in v body)) (second form))))))

(defun decl-variants (form)
  "FORM with each binder that has unused variables left bare, or declared IGNORE,
or declared IGNORABLE.  Returns ((form . has-bare-unused-inside-loop/lambda) ...)."
  (labels ((walk (x inside)             ; -> list of (form . f1-shape-p)
             (cond ((atom x) (list (cons x nil)))
                   ((eq (car x) 'quote) (list (cons x nil)))
                   (t (let* ((inner-inside (or inside (member (car x) '(loop$ lambda$))))
                             (kids (product (mapcar (lambda (y) (walk y inner-inside)) (cdr x))))
                             (out nil))
                        (dolist (k kids (nreverse out))
                          (let* ((f (cons (car x) (mapcar #'car k)))
                                 (flag (some #'cdr k))
                                 (un (and (member (car x) '(let let* mv-let)) (unused-of f)))
                                 (ign-ok (or (not (eq (car x) 'let*))
                                             (= (length (second f))
                                                (length (remove-duplicates (mapcar #'first (second f))))))))
                            (if un
                                (let ((n (if (eq (car x) 'mv-let) 3 2)))
                                  (push (cons f (or flag (and inside t))) out)
                                  ;; ACL2 rejects any IGNORE/IGNORABLE of a name bound twice in one LET*
                                  (dolist (d (if ign-ok '(ignore ignorable) nil))
                                    (push (cons (append (subseq f 0 n) `((declare (,d ,@un))) (nthcdr n f))
                                                flag)
                                          out)))
                                (push (cons f flag) out))))))))
           (product (lists)
             (if (null lists) (list nil)
                 (loop for a in (car lists)
                       append (loop for r in (product (cdr lists)) collect (cons a r))))))
    (walk form nil)))

(defun bare-unused-p (form)
  "Does FORM contain a LET/LET*/MV-LET with an unused variable and no declaration for it?"
  (and (consp form) (not (eq (car form) 'quote))
       (or (and (member (car form) '(let let* mv-let))
                (let ((decls (remove-if-not (lambda (x) (and (consp x) (eq (car x) 'declare)))
                                            (cddr form))))
                  (remove-if (lambda (v) (mentions v decls)) (unused-of form))))
           (some #'bare-unused-p (cdr form)))))

;;;; Programs and contexts

(defparameter *xt* (list :int -8 8))
(defparameter *lt* (list :list 0 12 -8 8))
(defparameter *skel-queries*
  '((0 -8 nil) (0 3 '(1 -2 8)) (0 7 '(-8 0 5 5 2))))

(defun skeleton-fns (keep-f1)
  "(values fns counts): one FN per valid filling."
  (let ((fns nil) (idx 0) (counts nil))
    (setf *elem* *xt* *fields* nil *feats* nil *consts* nil *fns* (make-hash-table))
    (dolist (sk *skeletons*)
      (destructuring-bind (name tpl) sk
        (let ((total 0) (invalid 0) (f1 0) (kept 0) (bare 0) (seen (make-hash-table :test 'equal)))
          (dolist (filled (ex tpl '((x . :int) (l . :list)) 0))
            (dolist (v (decl-variants (car filled)))
              (destructuring-bind (form . f1p) v
                (unless (gethash form seen)
                  (setf (gethash form seen) t)
                  (incf total)
                  (let ((chk (valid-or-nil (infer form (list (cons 'x *xt*) (cons 'l *lt*))))))
                    (cond ((not (and chk (intp* (first chk)))) (incf invalid))
                          ((and f1p (not keep-f1)) (incf f1))
                          (t (incf kept)
                             (when (bare-unused-p form) (incf bare))
                             (push (make-fn :name (intern (format nil "ZF~D" idx) :zs)
                                            :params '(x l) :ptypes (list *xt* *lt*)
                                            :rtype (first chk) :ir form :kind name
                                            :density nil :queries *skel-queries*)
                                   fns)
                             (incf idx))))))))
          (push (list name total invalid f1 kept bare) counts))))
    (values (nreverse fns) (nreverse counts))))

(defun context-list ()
  (let* ((base '(:ignore :ok :irrelevant t))
         (singles
           (append
            (list (list "base" base nil)
                  (list "decl" '(:ignore :decl :irrelevant t) nil)
                  (list "sub-plain" (append '(:sub :plain) base) nil)
                  (list "sub-local" (append '(:sub :local) base) nil)
                  (list "port" (append '(:port t) base) nil)
                  (list "setters" (append (list :setters (loop for s in *neutral-setters* for i from 0
                                                                collect (list s (nth (mod i 3) '(:before :mid :after)))))
                                          base)
                        nil)
                  (list "inline" base :inline)
                  (list "ann" base :ann))
            (loop for s in (cdr *styles*)
                  collect (list (format nil "style-~(~A~)" s) base s))))
         (pairs (list (list "decl+sub-plain" '(:sub :plain :ignore :decl :irrelevant t) nil)
                      (list "decl+make-event" '(:ignore :decl :irrelevant t) :make-event)
                      (list "sub-plain+program" (append '(:sub :plain) base) :program)
                      (list "port+encap" (append '(:port t) base) :encap)
                      (list "sub-local+make-event" (append '(:sub :local) base) :make-event)
                      (list "sub-plain+inline" (append '(:sub :plain) base) :inline)
                      (list "decl+nested-encap" '(:ignore :decl :irrelevant t) :nested-encap)
                      (list "port+sub-plain+late-guards" (append '(:port t :sub :plain) base) :late-guards))))
    (append singles pairs)))

(let* ((keep-f1 (equal (car (last sb-ext:*posix-argv*)) "KEEP-F1"))
       (root (car (last sb-ext:*posix-argv* (if keep-f1 2 1))))
       (*keep-f1-shape* t))             ; emit declarations exactly as enumerated
  (multiple-value-bind (fns counts) (skeleton-fns keep-f1)
    (with-open-file (s (format nil "~Acounts.txt" root) :direction :output :if-exists :supersede)
      (format s "skeleton fillings invalid(infer) excluded(F1/F2-shape) emitted bare-unused~%")
      (dolist (c counts) (format s "~{~A~^ ~}~%" c))
      (format s "TOTAL ~D ~D ~D ~D ~D~%" (reduce #'+ (mapcar #'second counts))
              (reduce #'+ (mapcar #'third counts)) (reduce #'+ (mapcar #'fourth counts))
              (reduce #'+ (mapcar #'fifth counts)) (reduce #'+ (mapcar #'sixth counts))))
    (dolist (c (context-list))
      (destructuring-bind (name ctx how) c
        (let* ((dir (format nil "~A~A/" root name))
               (p (%make-prog :seed 0 :elem *xt* :ctx ctx
                              :fns (mapcar (lambda (f)
                                             (let ((g (copy-fn f)))
                                               (case how
                                                 ((nil))
                                                 (:inline (setf (fn-inline g) t))
                                                 (:ann (setf (fn-density g) 60 (fn-ann-seed g) 7))
                                                 (t (setf (fn-style g) how)))
                                               g))
                                           (if (eq (getf ctx :ignore) :decl)
                                               ;; a LET* that rebinds a name cannot declare it, so
                                               ;; its unused bindings need SET-IGNORE-OK
                                               (remove-if (lambda (f)
                                                            (bare-unused-p (fix-ignores (fn-ir f) :decl)))
                                                          fns)
                                               fns)))))
          (ensure-directories-exist dir)
          (emit-prog p dir))))
    (format t "~D functions, ~D contexts~%" (length fns) (length (context-list)))))
