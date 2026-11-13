; stage2.lisp -- typed-signature derived types and membership check (SBCL host).
;
; For every target operator OP and every tuple of declared argument types (one per formal,
; from *dt-types*), compile under ACL2's global policy
;     (lambda (a b ..) (declare (type T1 a) (type T2 b) ..) (values (OP a b ..) a b ..))
; and read the derived (values R A' B' ..).  Then, for boundary tuples that are of the
; declared types AND satisfy OP's ACL2 guard:
;   RESULT-NOT-IN-DERIVED   reference value is not typep R
;   ARG-NOT-IN-DERIVED      an argument value is not typep its post-call derived type
;   VALUE-MISMATCH          calling the compiled typed lambda gives a different value
; The reference value is ACL2's evaluator ev-w on the translated call with guard checking
; on (so a guard-violating tuple is recognised and skipped, never passed to raw code).
(in-package "ACL2")
(load "/Users/ember/dev/compiler-audit/derived-types/common.lisp")
(setq *dt-timeout* 0.3)

(defvar *dt-only* nil)
(defvar *dt-tag* #+sbcl "sbcl" #+ccl "ccl")
(defvar *dt-max-tuples-per-sig* 300)
(defvar *dt-slow* 0.02) ; seconds; see the call phase of dt-run-entry
(defvar *dt-trace* nil) ; print every evaluation before it is made (to locate a host crash)
(defun dt-trace (&rest x) (when *dt-trace* (format t "~&TRACE ~A~%" (dt-1line x)) (finish-output)))

(defparameter *dt-types*
  '(t bit (unsigned-byte 8) (signed-byte 61) fixnum (unsigned-byte 64) (signed-byte 64)
    (integer 0 *) integer rational (complex rational)
    character standard-char string symbol cons))
(defparameter *dt-df-types* '(t double-float))

(defvar *dt-reduced* nil) ; true while re-running an operator that crashed the host

(defun dt-universe (arity)
  (let ((u (dt-universe-full arity)))
    ; reduced universe: no integer of more than 33 bits (rationals and the rest are kept)
    (if *dt-reduced* (remove-if (lambda (v) (and (integerp v) (> (integer-length v) 33))) u) u)))

(defun dt-universe-full (arity)
  (let* ((ints (list 0 1 -1 2 -2 3 7 8 31 32 63 64 65 255 256
                     (1- (expt 2 31)) (expt 2 31) (- (expt 2 31)) (1- (expt 2 32)) (expt 2 32)
                     (1- (expt 2 60)) (expt 2 60) (- (expt 2 60)) (- -1 (expt 2 60))
                     (1- (expt 2 62)) (expt 2 62) (- (expt 2 62)) (- -1 (expt 2 62))
                     (1- (expt 2 63)) (expt 2 63) (- (expt 2 63)) (- -1 (expt 2 63))
                     (1- (expt 2 64)) (expt 2 64) (1+ (expt 2 64)) (- (expt 2 64))
                     (expt 10 40) (- (expt 10 40))))
         (rest (list 1/2 -7/3 (/ (1+ (expt 2 64)) 3)
                     (complex 0 1) (complex 1/2 -3)
                     #\a #\A #\0 #\Space #\Newline #\~ #\Tab (code-char 0) (code-char 127) (code-char 255)
                     (copy-seq "") (copy-seq "abc") (copy-seq "Abd") (copy-seq "12")
                     (coerce (list (code-char 255) #\Space (code-char 0) #\A) 'string)
                     nil t :key 'abc 'car 'string
                     (list 1 2 3) (list* 'a 'b 'c) (list (cons 'a 1) (cons 'b 2))
                     (list #\a #\b) (list "abc" 'abc 1) (list 3 1 2 1)
                     ; a one-dimensional ACL2 array named ABC, and a two-dimensional one named CAR
                     (list '(:header :dimensions (4) :maximum-length 5 :default 0 :name abc)
                           '(0 . 5) '(2 . 7))
                     (list '(:header :dimensions (2 2) :maximum-length 5 :default 0 :name car)
                           '((0 . 1) . 9)))))
    (cond ((<= arity 2) (append ints rest))
          ((= arity 3)
           (append (list 0 1 -1 2 255 256 (1- (expt 2 60)) (expt 2 60) (- -1 (expt 2 60))
                         (1- (expt 2 62)) (expt 2 62) (- -1 (expt 2 62)) (expt 2 63)
                         (1- (expt 2 64)) (expt 2 64) (- (expt 10 40)))
                   rest))
          (t (append (list 0 1 -1 2 (expt 2 60) (expt 2 64))
                     (list 1/2 #\a "abc" nil 'abc 'car (list 1 2 3))
                     (last rest 2))))))

(defun dt-df-universe ()
  (list 0d0 -0d0 1d0 -1d0 0.5d0 -0.5d0 2d0 pi (- pi) (/ pi 2) 1d-300 -1d-300
        4.9406564584124654d-324 most-positive-double-float most-negative-double-float
        710d0 -746d0 1d16 9007199254740992d0 0.9999999999999999d0 1.0000000000000002d0))

; ---- entries -------------------------------------------------------------------------
; (name formals raw-form guard-term call-term dfp)
(defun dt-entry-for-function (fn w)
  (let ((formals (getpropc fn 'formals nil w)))
    (list fn formals (cons fn formals) (guard fn nil w) (cons fn formals)
          (and (or (member :df (stobjs-in fn w)) (member :df (stobjs-out fn w))) t))))

(defun dt-entry-for-form (label formals form w)
  ; FORM is an untranslated ACL2 form that is also the raw Lisp form.  No separate guard:
  ; a tuple is in the domain iff ev-w of the translated form completes without error.
  (multiple-value-bind (erp term) (translate-cmp form t nil t 'dt w (default-state-vars nil))
    (if erp nil (list label formals form *t* term nil))))

(defparameter *dt-macro-forms*
  ; logic macros whose raw Lisp counterpart is a host function (stage 1 lists all 68)
  (let ((acc nil))
    (dolist (op '(logand logior logxor logeqv + * list list* append))
      (push (list (list op 1) '(a) `(,op a)) acc)
      (push (list (list op 2) '(a b) `(,op a b)) acc)
      (push (list (list op 3) '(a b c) `(,op a b c)) acc))
    (dolist (op '(- /))
      (push (list (list op 1) '(a) `(,op a)) acc)
      (push (list (list op 2) '(a b) `(,op a b)) acc))
    (dolist (op '(>= > <= count search position remove rassoc assoc subsetp member))
      (push (list (list op 2) '(a b) `(,op a b)) acc))
    (dolist (op '(1- 1+ rest first second third fourth fifth sixth seventh eighth ninth tenth
                  remove-duplicates digit-char-p make-list
                  caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
                  caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
                  cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr))
      (push (list (list op 1) '(a) `(,op a)) acc))
    (push (list '(digit-char-p 2) '(a b) '(digit-char-p a b)) acc)
    (push (list '(concatenate string) '(a b) '(concatenate 'string a b)) acc)
    (push (list '(concatenate list) '(a b) '(concatenate 'list a b)) acc)
    (push (list '(intern "ACL2") '(a) '(intern a "ACL2")) acc)
    (push (list '(member :test eq) '(a b) '(member a b :test 'eq)) acc)
    (push (list '(assoc :test eq) '(a b) '(assoc a b :test 'eq)) acc)
    (push (list '(position :test eq) '(a b) '(position a b :test 'eq)) acc)
    (nreverse acc)))

(defparameter *dt-skip*
  '((sleep . "blocks for its argument in seconds")
    ; the next 15 are the effectful built-ins listed in primitives/sweep.lisp (*psw-unsafe*)
    (good-bye-fn . "exits the Lisp process")
    (sys-call . "runs an operating system command")
    (setenv$ . "sets process environment variables")
    (break$ . "enters the Lisp debugger")
    (gc$-fn . "applies the host garbage collector to arbitrary arguments")
    (gc-verbose-fn . "changes host GC settings")
    (set-gc-strategy-fn . "changes host GC settings")
    (extend-world . "raw code installs a world")
    (retract-world . "raw code installs a world")
    (set-bad-lisp-consp-memoize . "changes global memoization of the reader check")
    (never-memoize-fn . "changes the global never-memoize table")
    (set-absstobj-debug-fn . "changes a global debug flag")
    (print-call-history . "prints a host backtrace")
    (hons-acons . "raw code allocates a hash table sized by an integer final cdr")
    (hons-acons! . "raw code allocates a hash table sized by an integer final cdr")
    (fast-alist-len . "an alist that is not fast enters the debugger (slow-alist action)")
    (fast-alist-free . "an alist that is not fast enters the debugger (slow-alist action)")
    (hons-get . "an alist that is not fast enters the debugger (slow-alist action)")
    (make-list . "allocates a list of the requested length; derived type recorded in stage 1 only")))

(defun dt-target-functions (w)
  ; Every world function symbol that is a raw function and that the host compiler may treat
  ; specially at a call site: host-owned (COMMON-LISP package), proclaimed inline, given an
  ; ftype, or known to the compiler (SBCL: fun-info; CCL: nx1 handler or compiler macro).
  (let ((acc nil))
    (dolist (s (dt-all-function-symbols w))
      (when (and (fboundp s) (not (macro-function s)) (not (special-operator-p s))
                 (or (eq (symbol-package s) (find-package "COMMON-LISP"))
                     (assoc s *primitive-formals-and-guards*)
                     #+sbcl (sb-int:info :function :inlinep s)
                     #+sbcl (eq (sb-int:info :function :where-from s) :declared)
                     #+sbcl (sb-int:info :function :info s)
                     #+ccl (ccl::proclaimed-inline-p s)
                     #+ccl (ccl::proclaimed-ftype s)
                     #+ccl (compiler-macro-function s)
                     #+ccl (gethash s ccl::*nx1-alphatizers*)))
        (push s acc)))
    (nreverse acc)))

(defvar *dt-resume* t)
(defun dt-lines (name)
  (with-open-file (i (dt-path name) :if-does-not-exist nil)
    (and i (loop for l = (read-line i nil) while l collect l))))
(defun dt-first-column (name)
  (mapcar (lambda (l) (subseq l 0 (or (position #\Tab l) (length l)))) (dt-lines name)))

; ---- the check ------------------------------------------------------------------------
(defun dt-typemask (v types)
  (let ((m 0) (i 0))
    (dolist (ty types m) (when (typep v ty) (setq m (logior m (ash 1 i)))) (incf i))))

(defun dt-combos (lists)
  (if (null lists) (list nil)
      (let ((rest (dt-combos (cdr lists))) (acc nil))
        (dolist (x (car lists) (nreverse acc))
          (dolist (r rest) (push (cons x r) acc))))))

(defun dt-run-entry (entry w sig-out vio-out)
  (destructuring-bind (label formals form guard-term call-term dfp) entry
    (let* ((arity (length formals))
           (types (if dfp *dt-df-types* *dt-types*))
           (univ (if dfp (dt-df-universe) (dt-universe arity)))
           (masks (mapcar (lambda (v) (dt-typemask v types)) univ))
           (vm (mapcar #'cons univ masks))
           (tuples nil) (n-domain 0) (n-sigs 0) (n-checked 0) (n-vio 0) (n-compile-err 0)
           (n-timeout 0) (n-slow 0))
      ; 1. guard-satisfying tuples with their reference values
      (dolist (tu (dt-combos (make-list arity :initial-element vm)))
        (let* ((vals (mapcar #'car tu))
               (alist (mapcar #'cons formals (if dfp (mapcar #'rational vals) vals)))
               (g (progn (dt-trace :ref label vals) (dt-ev guard-term alist w))))
          (when (and (eq (car g) :val) (cdr g))
            (let* ((t0 (get-internal-real-time))
                   (r (dt-ev call-term alist w))
                   (slow (> (- (get-internal-real-time) t0)
                            (* *dt-slow* internal-time-units-per-second))))
              (when (equal r '(:err :timeout)) (incf n-timeout))
              (when (eq (car r) :val)
                (incf n-domain)
                (when slow (incf n-slow))
                (push (list vals (mapcar #'cdr tu) (cdr r) slow) tuples))))))
      (setq tuples (nreverse tuples))
      ; 2. per signature
      (let* ((nty (length types))
             (viable (loop for i below arity collect
                           (loop for k below nty
                                 when (some (lambda (tu) (logbitp k (nth i (cadr tu)))) tuples)
                                 collect k))))
        (dolist (sig (if (= arity 0) (list nil) (dt-combos viable)))
          (let* ((match (remove-if-not
                         (lambda (tu) (every (lambda (k m) (logbitp k m)) sig (cadr tu)))
                         tuples)))
            (when (or match (= arity 0))
              (let* ((sigtypes (mapcar (lambda (k) (nth k types)) sig))
                     (lam `(lambda ,formals
                             (declare (ignorable ,@formals)
                                      ,@(mapcar (lambda (f ty) `(type ,ty ,f)) formals sigtypes))
                             #+sbcl (values ,form ,@formals)
                             #+ccl ,form))
                     (ccl-op nil)
                     (fn #+sbcl (dt-compile lam)
                         #+ccl (multiple-value-bind (f op ty) (dt-ccl-probe lam)
                                 (setq ccl-op (list op ty)) f))
                     (rts #+sbcl (dt-result-types (if (functionp fn) (sb-kernel:%simple-fun-type fn) fn))
                          #+ccl (if (functionp fn)
                                    (list (if (member (cadr ccl-op) '(:unknown * nil)) t (cadr ccl-op)))
                                    :error))
                     (stride (max 1 (ceiling (length match) *dt-max-tuples-per-sig*)))
                     (nt 0) (i 0))
                (incf n-sigs)
                (unless (functionp fn) (incf n-compile-err))
                (when (and (functionp fn) (listp rts))
                  (dolist (tu match)
                    (when (zerop (mod i stride))
                      (incf nt)
                      (let* ((vals (car tu)) (ref (caddr tu)) (bad nil)
                             (slow (cadddr tu))
                             ; a tuple whose reference evaluation was slow (a very large
                             ; result) is not re-evaluated per signature: membership only
                             (got (if slow
                                      (cons :val ref)
                                      (progn (dt-trace :call label sigtypes vals)
                                             (dt-guarded (values (apply fn vals)))))))
                        ; df operators: the logical value is a rational and the raw value a
                        ; double, so the membership test uses the raw value
                        (when (and rts (not (ignore-errors
                                             (typep (if (and dfp (eq (car got) :val)) (cdr got) ref)
                                                    (car rts)))))
                          (push (list :result-not-in-derived ref (car rts)) bad))
                        (loop for v in vals for rt in (cdr rts) for k from 0
                              unless (ignore-errors (typep v rt))
                              do (push (list :arg-not-in-derived k v rt) bad))
                        (progn
                          (unless (and (eq (car got) :val)
                                       (if dfp (or (equal (cdr got) ref)
                                                   (and (realp (cdr got)) (realp ref)
                                                        (= (rational (cdr got)) (rational ref))))
                                           (equal (cdr got) ref)))
                            (push (list :value-mismatch :ref ref :got got) bad)))
                        (when bad
                          (incf n-vio)
                          (when (< n-vio 40)
                            (format vio-out "~A	~A	~A	~A~%" (dt-1line label) (dt-1line sigtypes)
                                    (dt-1line vals) (dt-1line bad))))))
                    (incf i)))
                (incf n-checked nt)
                (format sig-out "~A	~A	~A	~A	~A~%" (dt-1line label) (dt-1line sigtypes)
                        (dt-1line (if (listp rts) (car rts) rts))
                        #+sbcl (dt-1line (if (listp rts) (cdr rts) rts))
                        #+ccl (dt-1line (car ccl-op))
                        nt))))))
      (list label arity n-domain n-sigs n-checked n-vio n-compile-err n-timeout n-slow))))

(defun dt-stage2 ()
  (let* ((w (dt-world))
         (state *the-live-state*)
         (entries nil) (excluded nil))
    (f-put-global 'inhibit-output-lst *valid-output-names* state)
    ; planted control: a false declaration the oracle must report
    (push (list 'dt-control-false-narrowing '(a) '(the (unsigned-byte 8) (binary-+ a 1))
                '(integerp a) '(binary-+ a '1) nil)
          entries)
    (dolist (s (dt-target-functions w))
      (cond ((assoc s *dt-skip*) (push (list s (cdr (assoc s *dt-skip*))) excluded))
            ((remove-if (lambda (x) (member x '(nil :df))) (stobjs-in s w))
             (push (list s "takes a stobj or state") excluded))
            ((> (length (getpropc s 'formals nil w)) 4) (push (list s "arity above 4") excluded))
            (t (push (dt-entry-for-function s w) entries))))
    (dolist (m *dt-macro-forms*)
      (if (assoc (car (car m)) *dt-skip*)
          (push (list (car m) (cdr (assoc (car (car m)) *dt-skip*))) excluded)
          (let ((e (dt-entry-for-form (car m) (cadr m) (caddr m) w)))
            (if e (push e entries) (push (list (car m) "form does not translate") excluded)))))
    (setq entries (nreverse entries))
    (when *dt-only*
      (setq entries (remove-if-not (lambda (e) (member (if (consp (car e)) (caar e) (car e)) *dt-only*))
                                   entries)))
    (let* ((done (dt-first-column (format nil "results/~A-summary.tsv" *dt-tag*)))
           (crashed (dt-lines (format nil "results/~A-crashed.txt" *dt-tag*)))
           (resume (and *dt-resume* done t))
           (mode (if resume :append :supersede)))
     (with-open-file (sig (dt-path (format nil "results/~A-signatures.tsv" *dt-tag*))
                         :direction :output :if-exists mode :if-does-not-exist :create)
      (with-open-file (vio (dt-path (format nil "results/~A-violations.tsv" *dt-tag*))
                           :direction :output :if-exists mode :if-does-not-exist :create)
        (with-open-file (sum (dt-path (format nil "results/~A-summary.tsv" *dt-tag*))
                             :direction :output :if-exists mode :if-does-not-exist :create)
          (unless resume
          (format sig "operator	declared-arg-types	derived-result	derived-post-call-arg-types(sbcl)/acode-operator(ccl)	tuples-checked~%")
          (format vio "operator	declared-arg-types	argument-values	violations~%")
          (format sum "operator	arity	guard-satisfying-tuples	signatures-compiled	tuple-checks	violating-tuples	compile-errors	reference-timeouts	slow-tuples(membership-only)	universe~%"))
          (dolist (e entries)
            (let* ((lab (dt-1line (car e)))
                   (ncrash (count lab crashed :test #'equal)))
              (cond
                ((and resume (member lab done :test #'equal)))
                ((>= ncrash 2)
                 (format sum "~A	HOST-CRASH	the host process died twice evaluating this operator (full, then reduced universe)~%" lab)
                 (finish-output sum))
                (t
                 ; a sig/vio row is only valid once its operator has a summary row
                 (with-open-file (c (dt-path (format nil "results/~A-current.txt" *dt-tag*))
                                    :direction :output :if-exists :supersede)
                   (format c "~A~%" lab))
                 (let* ((*dt-reduced* (= ncrash 1))
                        (r (dt-run-entry e w sig vio)))
                   (format sum "~{~A~^	~}	~A~%" (mapcar #'dt-1line r) (if *dt-reduced* "reduced" "full"))
                   (finish-output sum) (finish-output vio) (finish-output sig))))))
          (dolist (x excluded)
            (format sum "~A	EXCLUDED	~A~%" (dt-1line (car x)) (cadr x)))))))
    (format t "~&STAGE2 DONE entries ~D excluded ~D~%" (length entries) (length excluded))))
