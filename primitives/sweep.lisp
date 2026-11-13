; sweep.lisp -- bounded-exhaustive logical-vs-actual sweep of ACL2 built-ins.
;
; Loaded in raw Lisp (after :q) by the driver that run.sh generates.  The
; driver sets *psw-outdir* before loading and calls (psw-main) afterwards.
; See README.md for what is compared and what is not.

(in-package "ACL2")

(defvar *psw-outdir* nil)            ; set by the driver; must end in "/"
(defvar *psw-depth* 6000)            ; big-n: nesting-depth bound of the logical evaluator
(defvar *psw-time-limit* 2)          ; seconds, wall clock, per single evaluation
(defvar *psw-max-timeouts* 40)       ; per function; then the function is abandoned (PARTIAL)
(defvar *psw-max-fn-seconds* 1800)   ; per function; then the function is abandoned (PARTIAL)
(defvar *psw-max-logged* 25)         ; divergence records written per function and category
(defvar *psw-max-arity* 3)
(defvar *psw-only* nil)              ; optional list of function symbols: sweep only these
(defvar *psw-binary-*-workaround* t) ; see psw-install-workarounds

; Functions that qualify syntactically but are not swept because calling them
; has effects outside the value they return.  Reviewed by name against the
; derived list; every entry is reported in excluded.tsv.
(defvar *psw-unsafe*
  '((good-bye-fn . "exits the Lisp process")
    (sys-call . "runs an operating system command built from its arguments")
    (setenv$ . "sets process environment variables")
    (break$ . "enters the Lisp debugger")
    (sleep . "blocks for its argument in seconds")
    (gc$-fn . "applies the host garbage collector to arbitrary arguments")
    (gc-verbose-fn . "changes host GC settings")
    (set-gc-strategy-fn . "changes host GC settings")
    (extend-world . "raw code installs a world on a symbol's property list")
    (retract-world . "raw code installs a world on a symbol's property list")
    (set-bad-lisp-consp-memoize . "changes global memoization of the reader check")
    (never-memoize-fn . "changes the global never-memoize table")
    (set-absstobj-debug-fn . "changes a global debug flag")
    (print-call-history . "prints a host backtrace")
    (hons-acons . "raw code allocates a hash table sized by an integer final cdr (exhausted a 12 GB heap)")
    (hons-acons! . "raw code allocates a hash table sized by an integer final cdr (exhausted a 12 GB heap)")))

; ---------------------------------------------------------------------------
; Universe

(defun psw-make-universe ()
  ; Fresh structure on every call, so that nothing a swept function does to an
  ; argument can leak into the next function.
  (list 0 1 -1 2
        536870911                        ; 2^29 - 1
        536870912                        ; 2^29
        1152921504606846976              ; 2^60      (CCL most-positive-fixnum + 1)
        4611686018427387904              ; 2^62      (SBCL most-positive-fixnum + 1)
        -9223372036854775808             ; -2^63
        18446744073709551616             ; 2^64
        (expt 10 40)                     ; bignum
        1/2 -7/3
        (complex 0 1) (complex 1/2 -3)   ; #c(1 0) is the integer 1, see psw-meta
        #\a (code-char 0) (code-char 127) (code-char 255)
        (copy-seq "") (copy-seq "abc")
        (coerce (list (code-char 255) #\Space (code-char 0) #\A) 'string)
        nil t :key 'abc 'car             ; car: symbol-package-name is "COMMON-LISP"
        (list 1 2 3)
        (list* 'a 'b 'c)                 ; dotted list (A B . C)
        (list (cons 'a 1) (cons 'b 2))))

; ---------------------------------------------------------------------------
; Per-evaluation wall-clock bound: one watchdog thread, no per-call timers.

(defvar *psw-epoch* 0)
(defvar *psw-deadline* nil)
(defvar *psw-limit-ticks* 0)
(defvar *psw-watchdog* nil)

(defun psw-interrupt-main (main fn)
  #+sbcl (sb-thread:interrupt-thread main fn)
  #+ccl (ccl:process-interrupt main fn)
  #-(or sbcl ccl) (error "unsupported host"))

(defun psw-start-watchdog ()
  (setq *psw-limit-ticks* (* *psw-time-limit* internal-time-units-per-second))
  (let* ((main #+sbcl sb-thread:*current-thread* #+ccl ccl:*current-process*
               #-(or sbcl ccl) nil)
         (body (lambda ()
                 (loop
                  (sleep 0.2)
                  (let ((d *psw-deadline*) (e *psw-epoch*))
                    (when (and d (> (get-internal-real-time) d))
                      (psw-interrupt-main
                       main
                       (lambda ()
                         (when (and *psw-deadline* (eql e *psw-epoch*))
                           (setq *psw-deadline* nil)
                           (throw 'psw-timeout (list :err :timeout)))))))))))
    (setq *psw-watchdog*
          #+sbcl (sb-thread:make-thread body :name "psw-watchdog")
          #+ccl (ccl:process-run-function "psw-watchdog" body)
          #-(or sbcl ccl) nil)))

(defmacro psw-bounded (&body body)
  ; Value of body, or (:err :timeout) if the watchdog fired.
  `(let ((r (catch 'psw-timeout
              (setq *psw-epoch* (1+ *psw-epoch*))
              (setq *psw-deadline* (+ (get-internal-real-time) *psw-limit-ticks*))
              (prog1 (progn ,@body) (setq *psw-deadline* nil)))))
     (setq *psw-deadline* nil)
     r))

; ---------------------------------------------------------------------------
; Outcomes.  An outcome is (:val . v) or (:err kind . detail).

(defun psw-condition-text (c)
  (let ((s (or (ignore-errors (princ-to-string c)) "?")))
    (substitute #\Space #\Newline (subseq s 0 (min 160 (length s))))))

(defmacro psw-guarded (&body body)
  ; Body returns an outcome.  ACL2 throws and Lisp conditions become outcomes.
  `(handler-case
       (block psw-b
         (let ((top (catch 'local-top-level
                      (let ((thrown (catch-raw-ev-fncall
                                     (return-from psw-b (progn ,@body)))))
                        (return-from psw-b
                          (list :err :throw
                                (if (consp thrown) (car thrown) thrown)
                                (and (consp thrown) (consp (cdr thrown))
                                     (cadr thrown))
                                (and (consp thrown) (consp (cdr thrown))
                                     (consp (cddr thrown))
                                     (symbolp (caddr thrown))
                                     (caddr thrown))))))))
           (list :err :top-level top)))
     (serious-condition (c)
       (list :err :lisp (type-of c) (psw-condition-text c)))))

(defun psw-msg-kind (val)
  ; Val is the message returned with a non-nil erp by the logical evaluator.
  (let ((s (cond ((stringp val) val)
                 ((and (consp val) (stringp (car val))) (car val))
                 (t ""))))
    (if (search "ran out of time" s)
        (list :depth)
        (list :logical
              (substitute #\Space #\Newline (subseq s 0 (min 110 (length s))))
              ; the first fmt argument usually names the function that could not be run
              (and (consp val) (consp (cdr val)) (consp (cadr val)) (cdr (cadr val)))))))

(defvar *psw-original-ev-fncall-rec-logical* nil)

(defun psw-install-workarounds ()
  ; ev-fncall-rec-logical's BINARY-* case tests only (acl2-numberp y) before
  ; calling the host's *, so (binary-* #\a 0) is a host type error instead of
  ; the logical value 0 (repros/ev-fncall-rec-logical-binary-star.lisp).  Left
  ; alone, that removes every tuple whose logical evaluation multiplies a
  ; non-number by a number.  With the workaround, exactly that case is sent to
  ; the *1* function of binary-*, which is what ev-fncall-rec-logical itself
  ; does (via ec-call) for every other guard-violating primitive call.  Nothing
  ; in ACL2's sources is changed; only this image's function cell.
  (when (and *psw-binary-*-workaround* (null *psw-original-ev-fncall-rec-logical*))
    (setq *psw-original-ev-fncall-rec-logical* (symbol-function 'ev-fncall-rec-logical))
    (let ((orig *psw-original-ev-fncall-rec-logical*)
          (*1*times (*1*-symbol 'binary-*)))
      (setf (symbol-function 'ev-fncall-rec-logical)
            (lambda (fn arg-values &rest rest)
              ; rest = arg-exprs w user-stobj-alist big-n safe-mode gc-off latches ...
              (if (and (eq fn 'binary-*)
                       (nth 5 rest) ; gc-off
                       (not (acl2-numberp (car arg-values)))
                       (acl2-numberp (cadr arg-values)))
                  (values nil
                          (funcall *1*times (car arg-values) (cadr arg-values))
                          (nth 6 rest))
                  (apply orig fn arg-values rest)))))))

(defun psw-logical (fn args w)
  ; The logical value: interpret fn's logical body, guard checking off.
  ; State global guard-checking-on must be :none here, because the primitive
  ; cases of ev-fncall-rec-logical use ec-call (the *1* primitive), which reads
  ; the state global, not the gc-off argument.
  (psw-bounded
   (psw-guarded
    (let ((*ev-shortcut-okp* nil))
      (multiple-value-bind (erp val)
          (ev-fncall-rec-logical fn args nil w nil *psw-depth*
                                 nil ; safe-mode
                                 t   ; gc-off
                                 nil ; latches
                                 t   ; hard-error-returns-nilp
                                 nil ; aok
                                 nil)
        (if erp (cons :err (psw-msg-kind val)) (cons :val val)))))))

(defun psw-logical-term (term alist w)
  (psw-bounded
   (psw-guarded
    (let ((*ev-shortcut-okp* nil))
      (multiple-value-bind (erp val)
          (ev-rec term alist w nil *psw-depth* nil t nil t nil)
        (if erp (cons :err (psw-msg-kind val)) (cons :val val)))))))

(defun psw-star1 (fn args nvals)
  ; The *1* executable counterpart, under the current guard-checking-on.
  (psw-bounded
   (psw-guarded
    (let ((*aokp* nil) (**1*-as-raw* nil) (*hard-error-returns-nilp* t)
          (*1*fn (*1*-symbol fn)))
      (cons :val (if (eql nvals 1)
                     (values (apply *1*fn args))
                     (multiple-value-list (apply *1*fn args))))))))

(defun psw-raw (fn args nvals rawkind)
  ; The raw Lisp definition.  Only ever called on guard-satisfying arguments.
  (psw-bounded
   (psw-guarded
    (let ((*aokp* nil) (*hard-error-returns-nilp* t))
      (cons :val
            (if (eq rawkind :function)
                (if (eql nvals 1)
                    (values (apply (symbol-function fn) args))
                    (multiple-value-list (apply (symbol-function fn) args)))
                (let ((form (cons fn (mapcar (lambda (a) (list 'quote a)) args))))
                  (if (eql nvals 1)
                      (values (eval form))
                      (multiple-value-list (eval form))))))))))

(defun psw-apply-prim (fn args)
  ; (apply$-prim 'fn args) through its raw definition, a hand-built dispatch
  ; that exists only in raw Lisp (the logical body of apply$-prim is non-exec).
  ; Its guard, (true-listp args), always holds here.  It reaches fn by ec-call,
  ; so it is run with guard-checking :none.
  (psw-bounded
   (psw-guarded
    (let ((*aokp* nil) (**1*-as-raw* nil) (*hard-error-returns-nilp* t))
      (cons :val (values (apply$-prim fn args)))))))

(defun psw-set-gc (val)
  (f-put-global 'guard-checking-on val *the-live-state*))

; ---------------------------------------------------------------------------
; Host-independent digest of outcomes (two 32-bit running hashes).

(defvar *psw-h1* 0)
(defvar *psw-h2* 0)

(defun psw-byte (b)
  (setq *psw-h1* (logand (* (logxor *psw-h1* b) 16777619) #xffffffff))
  (setq *psw-h2* (logand (+ (* *psw-h2* 16777213) b 1) #xffffffff)))

(defun psw-int (n)
  (psw-byte (if (minusp n) 45 43))
  (let ((m (abs n)))
    (loop (psw-byte (logand m 255))
          (setq m (ash m -8))
          (when (zerop m) (return))))
  (psw-byte 59))

(defun psw-str (s)
  (psw-int (length s))
  (loop for c across s do (psw-int (char-code c))))

(defun psw-obj (x)
  (loop
   (cond ((consp x) (psw-byte 7) (psw-obj (car x)) (setq x (cdr x)))
         (t (return))))
  (cond ((integerp x) (psw-byte 1) (psw-int x))
        ((rationalp x) (psw-byte 2) (psw-int (numerator x)) (psw-int (denominator x)))
        ((and (complexp x) (rationalp (realpart x)) (rationalp (imagpart x)))
         (psw-byte 3) (psw-obj (realpart x)) (psw-obj (imagpart x)))
        ((characterp x) (psw-byte 4) (psw-int (char-code x)))
        ((stringp x) (psw-byte 5) (psw-str x))
        ((and (symbolp x) (symbol-package x))
         (psw-byte 6) (psw-str (symbol-package-name x)) (psw-str (symbol-name x)))
        (t (psw-byte 99))))

(defun psw-outcome-digest (o)
  (cond ((eq (car o) :val) (psw-byte 86) (psw-obj (cdr o)))
        ((eq (cadr o) :depth) (psw-byte 68))
        ((eq (cadr o) :timeout) (psw-byte 84))
        (t (psw-byte 69))))

(defmacro psw-with-digest ((h1 h2) &body body)
  ; Runs body with the running hashes taken from / stored back to places.
  `(let ((*psw-h1* ,h1) (*psw-h2* ,h2))
     ,@body
     (setq ,h1 *psw-h1* ,h2 *psw-h2*)))

; ---------------------------------------------------------------------------
; Comparison

(defun psw-compare (l a)
  ; :agree      both sides produced equal values
  ; :agree-err  neither side produced a value
  ; :mismatch   both sides produced values and they differ   <- the soundness-relevant case
  ; :act-err    logical value, actual side aborted with an error
  ; :log-err    the logical evaluator could not produce a value, the actual side did
  ; :act-timeout
  (cond ((and (not (eq (car a) :val)) (eq (cadr a) :timeout)) :act-timeout)
        ((and (eq (car l) :val) (eq (car a) :val))
         (if (equal (cdr l) (cdr a)) :agree :mismatch))
        ((and (not (eq (car l) :val)) (not (eq (car a) :val))) :agree-err)
        ((eq (car l) :val) :act-err)
        (t :log-err)))

(defvar *psw-kinds* '(:agree :agree-err :mismatch :act-err :log-err))
(defvar *psw-routes* '(:none :prim :t :raw))

(defun psw-print (x stream)
  (let ((*package* (find-package "ACL2")) (*print-pretty* nil) (*print-circle* nil)
        (*print-base* 10) (*print-radix* nil) (*print-length* 60) (*print-level* 10)
        (*print-readably* nil) (*print-escape* t) (*print-case* :upcase))
    (handler-case (prin1 x stream)
      (serious-condition () (format stream "#<unprintable>")))))

(defun psw-log-divergence (stream fn route kind idx args l a)
  (format stream "(:fn ")
  (psw-print fn stream)
  (format stream " :route ~s :kind ~s :idx ~s :args " route kind idx)
  (psw-print args stream)
  (format stream " :logical ")
  (psw-print l stream)
  (format stream " :actual ")
  (psw-print a stream)
  (format stream ")~%")
  (finish-output stream))

; ---------------------------------------------------------------------------
; Function selection

(defun psw-control-p (fn)
  (let ((s (symbol-name fn)))
    (and (>= (length s) 8) (string= "PSW-CTL-" s :end2 8))))

(defun psw-all-function-symbols (w)
  ; Every symbol with a 'formals property in world w, most recent first.
  (let ((seen (make-hash-table :test 'eq)) (acc nil))
    (dolist (trip w)
      (when (and (eq (cadr trip) 'formals)
                 (not (gethash (car trip) seen)))
        (setf (gethash (car trip) seen) t)
        (unless (eq (getpropc (car trip) 'formals t w) t)
          (push (car trip) acc))))
    (nreverse acc)))

(defun psw-exclusion-reason (fn w)
  ; NIL if fn qualifies, else a string.  First matching reason wins.
  (cond ((not (logicp fn w)) "program-mode")
        ((member fn *stobjs-out-invalid* :test 'eq)
         (if (member fn '(return-last do$) :test 'eq)
             nil ; treated as single-valued, as raw-ev-fncall does
             "no-fixed-output-signature (if / read-user-stobj-alist)"))
        ((null (body fn nil w))
         (cond ((assoc fn *primitive-formals-and-guards* :test 'eq)
                "no-body: primitive")
               ((getpropc fn 'constrainedp nil w) "no-body: constrained")
               (t "no-body: other")))
        ((getpropc fn 'non-executablep nil w) "non-executable")
        (t nil)))

(defun psw-exclusion-reason2 (fn w)
  (let ((in (stobjs-in fn w))
        (out (if (member fn *stobjs-out-invalid* :test 'eq) '(nil) (stobjs-out fn w))))
    (cond ((or (member 'state in :test 'eq) (member 'state out :test 'eq)) "state formal or result")
          ((or (member :df in :test 'eq) (member :df out :test 'eq))
           "df formal or result (raw representation is a double-float)")
          ((or (some #'identity in) (some #'identity out)) "stobj formal or result")
          ((> (length (formals fn w)) *psw-max-arity*) "arity > 3")
          ((assoc fn *psw-unsafe* :test 'eq)
           (concatenate 'string "unsafe to call: " (cdr (assoc fn *psw-unsafe* :test 'eq))))
          (t nil))))

; ---------------------------------------------------------------------------
; Sweep of one function

(defvar *psw-progress-path* nil)

(defun psw-note-progress (fn)
  (with-open-file (p *psw-progress-path* :direction :output :if-exists :supersede)
    (psw-print fn p) (terpri p)))

(defun psw-sweep-fn (fn w sum div)
  (let* ((formals (formals fn w))
         (arity (length formals))
         (nvals (if (member fn *stobjs-out-invalid* :test 'eq) 1 (length (stobjs-out fn w))))
         (class (symbol-class fn w))
         (clc (eq class :common-lisp-compliant))
         (primp (and (apply$-primp fn) (not (member fn '(return-last mv-list) :test 'eq))))
         (rawkind (cond ((not (fboundp fn)) :unbound)
                        ((macro-function fn) :macro)
                        ((special-operator-p fn) :special)
                        (t :function)))
         (guard-term (guard fn nil w))
         (u (psw-make-universe))
         (n (length u))
         (start (get-internal-real-time))
         (max-ticks (* *psw-max-fn-seconds* internal-time-units-per-second))
         (status "OK")
         (tuples 0) (l-val 0) (l-err 0) (l-depth 0) (l-timeout 0)
         (g-true 0) (g-false 0) (g-err 0) (guard-div 0) (sub-guard 0)
         (act-timeouts 0) (timeouts 0)
         (counts (make-hash-table :test 'equal))   ; (route . kind) -> count
         (logged (make-hash-table :test 'equal))
         (lh1 2166136261) (lh2 0) (ah1 2166136261) (ah2 0)
         (idx (make-list arity :initial-element 0)))
    (labels ((note (route kind args l a)
               (let ((key (cons route kind)))
                 (when (< (gethash key logged 0) *psw-max-logged*)
                   (incf (gethash key logged 0))
                   (psw-log-divergence div fn route kind (copy-list idx) args l a))))
             (tally (route args l a)
               ; Compare, count, and log everything that is not agreement.
               (let ((kind (psw-compare l a)))
                 (cond ((eq kind :act-timeout) (incf act-timeouts) (incf timeouts)
                        (note route kind args l a))
                       (t (incf (gethash (cons route kind) counts 0))
                          (unless (member kind '(:agree :agree-err))
                            (note route kind args l a))))
                 kind)))
      (block tuples
        (loop
         (let* ((args (mapcar (lambda (i) (nth i u)) idx))
                (l (progn (psw-set-gc :none) (psw-logical fn args w))))
           (incf tuples)
           (psw-with-digest (lh1 lh2) (psw-outcome-digest l))
           (cond
            ((eq (car l) :val) (incf l-val))
            ((eq (cadr l) :depth) (incf l-depth))
            ((eq (cadr l) :timeout) (incf l-timeout) (incf timeouts)
             (note :logical :timeout args l nil))
            (t (incf l-err)))
           (unless (and (not (eq (car l) :val))
                        (member (cadr l) '(:depth :timeout)))
             (let* ((g (psw-logical-term guard-term (pairlis formals args) w))
                    (a0 (psw-star1 fn args nvals)))
               (psw-with-digest (ah1 ah2) (psw-outcome-digest a0))
               (tally :none args l a0)
               (when primp (tally :prim args l (psw-apply-prim fn args)))
               (psw-set-gc t)
               (let* ((a1 (psw-star1 fn args nvals))
                      (guard-er (and (not (eq (car a1) :val))
                                     (eq (cadr a1) :throw)
                                     (eq (caddr a1) 'ev-fncall-guard-er)))
                      (guard-er-self (and guard-er (eq (cadddr a1) fn))))
                 (cond
                  ((not (eq (car g) :val)) (incf g-err))
                  ((cdr g)
                   (incf g-true)
                   (cond
                    (guard-er-self (incf guard-div) (note :guard :guard-div args g a1))
                    ; A guard error raised for a callee: an :ideal function, or a
                    ; guard-verified one that uses ec-call.  An abort, not a value.
                    (guard-er (incf sub-guard) (note :t :sub-guard args l a1))
                    (t
                     (tally :t args l a1)
                     ; Raw macros and special forms (mv-list, return-last,
                     ; wormhole-eval) are not called: translate restricts
                     ; the syntax of their arguments, which a quoted object
                     ; does not satisfy.
                     (when (and clc (eq (car a1) :val) (eq rawkind :function))
                       (tally :raw args l (psw-raw fn args nvals rawkind))))))
                  (t
                   (incf g-false)
                   (unless guard-er-self
                     (incf guard-div) (note :guard :guard-div args g a1)))))))
           (when (> timeouts *psw-max-timeouts*)
             (setq status "PARTIAL-timeouts") (return-from tuples))
           (when (> (- (get-internal-real-time) start) max-ticks)
             (setq status "PARTIAL-seconds") (return-from tuples))
           ; next tuple, lexicographic, last index fastest
           (let ((k (1- arity)))
             (loop
              (when (< k 0) (return-from tuples))
              (cond ((< (nth k idx) (1- n)) (incf (nth k idx)) (return))
                    (t (setf (nth k idx) 0) (decf k)))))))))
    (psw-set-gc t)
    (psw-print fn sum)
    (format sum "~c~a~c~a~c~a~c~a~c~a~c~a" #\Tab arity #\Tab nvals #\Tab class #\Tab rawkind
            #\Tab (if (psw-control-p fn) (concatenate 'string "CONTROL-" status) status)
            #\Tab tuples)
    (dolist (x (list l-val l-err l-depth l-timeout g-true g-false g-err guard-div sub-guard
                     act-timeouts))
      (format sum "~c~a" #\Tab x))
    (dolist (route *psw-routes*)
      (dolist (kind *psw-kinds*)
        (format sum "~c~a" #\Tab (gethash (cons route kind) counts 0))))
    (format sum "~c~8,'0x~8,'0x~c~8,'0x~8,'0x~c~a~%" #\Tab lh1 lh2 #\Tab ah1 ah2 #\Tab
            (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second))
    (finish-output sum)))

; ---------------------------------------------------------------------------
; Negative control: hand-written models, independent of ACL2's definitions.

(defun psw-model-nfix (x) (if (and (integerp x) (>= x 0)) x 0))
(defun psw-model-len (x) (let ((k 0)) (loop (if (consp x) (setq k (1+ k) x (cdr x)) (return k)))))
(defun psw-model-binary-append (x y)
  (if (consp x) (cons (car x) (psw-model-binary-append (cdr x) y)) y))

(defun psw-model-check (out w)
  (let ((u (psw-make-universe)))
    (psw-set-gc :none)
    (dolist (spec '((nfix 1 psw-model-nfix) (len 1 psw-model-len)
                    (binary-append 2 psw-model-binary-append)))
      (let ((fn (car spec)) (model (caddr spec)) (ok 0) (bad 0))
        (flet ((check (args)
                 (let ((l (psw-logical fn args w))
                       (a (psw-star1 fn args 1))
                       (m (apply model args)))
                   (if (and (eq (car l) :val) (equal (cdr l) m)
                            (eq (car a) :val) (equal (cdr a) m))
                       (incf ok)
                       (progn (incf bad)
                              (format out "MODEL-MISMATCH ")
                              (psw-print (list fn args l a m) out) (terpri out))))))
          (if (eql (cadr spec) 1)
              (dolist (x u) (check (list x)))
              (dolist (x u) (dolist (y u) (check (list x y))))))
        (format out "MODEL ~a tuples-matching-hand-model=~a mismatches=~a~%" fn ok bad)))
    (psw-set-gc t)))

; ---------------------------------------------------------------------------
; Main

(defun psw-path (name) (concatenate 'string *psw-outdir* name))

(defun psw-read-names (path)
  ; First s-expression of every line of a file, as a hash set.
  (let ((h (make-hash-table :test 'eq)))
    (when (probe-file path)
      (with-open-file (s path)
        (let ((*package* (find-package "ACL2")))
          (loop for line = (read-line s nil nil) while line
                do (when (> (length line) 0)
                     (setf (gethash (read-from-string line) h) t))))))
    h))

(defun psw-exit (code)
  (finish-output)
  #+sbcl (sb-ext:exit :code code :abort t)
  #+ccl (ccl:quit code))

(defun psw-main ()
  ; ACL2's own read-eval-print loop runs with the host's package locks off
  ; (new symbols may be interned into COMMON-LISP); raw Lisp after :q does not.
  #+sbcl (sb-ext:without-package-locks (psw-main1))
  #-sbcl (psw-main1))

(defun psw-main1 ()
  (let* ((w (w *the-live-state*))
         (fns (psw-all-function-symbols w))
         (done (psw-read-names (psw-path "summary.tsv")))
         (crashed (psw-read-names (psw-path "crashed.txt")))
         (resuming (> (hash-table-count done) 0))
         (reasons (make-hash-table :test 'equal))
         (todo nil) (controls nil)
         (saved-gc (f-get-global 'guard-checking-on *the-live-state*))
         (*defeat-slow-alist-action* t) ; fast-alist discipline warnings would enter a break loop
         (*ld-level* 1)) ; so that ACL2 errors throw to raw-ev-fncall, as inside the loop
    (setq *psw-progress-path* (psw-path "progress"))
    (psw-install-workarounds)
    (psw-start-watchdog)
    (with-open-file (ex (psw-path "excluded.tsv") :direction :output :if-exists :supersede)
      (dolist (fn fns)
        (let ((r (if (psw-control-p fn)
                     nil
                     (or (psw-exclusion-reason fn w) (psw-exclusion-reason2 fn w)))))
          (cond (r (incf (gethash r reasons 0))
                   (unless (equal r "program-mode")
                     (psw-print fn ex) (format ex "~c~a~%" #\Tab r)))
                ((psw-control-p fn) (push fn controls))
                (t (push fn todo))))))
    (setq todo (append (reverse controls) (reverse todo)))
    (when *psw-only*
      (setq todo (remove-if-not (lambda (f) (or (psw-control-p f) (member f *psw-only* :test 'eq)))
                                todo)))
    (unless resuming
      (with-open-file (m (psw-path "meta.txt") :direction :output :if-exists :supersede)
        (let ((u (psw-make-universe)))
          (format m "host ~a ~a~%" (lisp-implementation-type) (lisp-implementation-version))
          (format m "acl2 ~a~%" (f-get-global 'acl2-version *the-live-state*))
          (format m "most-positive-fixnum ~a~%" most-positive-fixnum)
          (format m "depth-bound ~a time-limit-seconds ~a max-timeouts-per-fn ~a max-fn-seconds ~a~%"
                  *psw-depth* *psw-time-limit* *psw-max-timeouts* *psw-max-fn-seconds*)
          (format m "binary-*-workaround ~a~%" (and *psw-original-ev-fncall-rec-logical* t))
          (format m "function-symbols-in-world ~a~%" (length fns))
          (format m "controls ~a~%" (length controls))
          (format m "qualifying ~a~%" (- (length todo) (length controls)))
          (let ((rs nil))
            (maphash (lambda (k v) (push (cons k v) rs)) reasons)
            (dolist (p (sort rs #'> :key #'cdr))
              (format m "excluded ~a~c~a~%" (cdr p) #\Tab (car p))))
          (format m "universe-size ~a~%" (length u))
          (format m "universe-distinct ~a~%"
                  (length (remove-duplicates u :test 'equal)))
          (format m "universe-bad-lisp-objects ~a~%"
                  (count-if (lambda (x) (bad-lisp-objectp x)) u))
          (format m "reader #c(1 0) is integer 1: ~a; #c(1/2 0) is 1/2: ~a~%"
                  (eql (read-from-string "#c(1 0)") 1)
                  (eql (read-from-string "#c(1/2 0)") 1/2))
          (loop for x in u for i from 0
                do (format m "universe ~a " i) (psw-print x m) (terpri m))
          (psw-model-check m w))))
    ; The files are opened and closed around every function: a host that dies
    ; (or quits) with a stream open may discard what was written to it.
    (flet ((call-with-files (f)
             (with-open-file (sum (psw-path "summary.tsv") :direction :output
                                  :if-exists :append :if-does-not-exist :create)
               (with-open-file (div (psw-path "divergences.lisp") :direction :output
                                    :if-exists :append :if-does-not-exist :create)
                 (funcall f sum div)))))
      (dolist (fn todo)
        (when (probe-file (psw-path "STOP"))
          (format t "~&@PSW stopped by STOP file~%")
          (psw-exit 0))
        (cond ((gethash fn done))
              ((gethash fn crashed)
               (call-with-files
                (lambda (sum div)
                  (declare (ignore div))
                  (psw-print fn sum)
                  (format sum "~c~a~c-~c-~c-~cCRASHED~%" #\Tab (length (formals fn w))
                          #\Tab #\Tab #\Tab #\Tab))))
              (t (psw-note-progress fn)
                 (call-with-files
                  (lambda (sum div) (psw-sweep-fn fn w sum div)))))))
    (psw-set-gc saved-gc)
    (with-open-file (d (psw-path "DONE") :direction :output :if-exists :supersede)
      (format d "done~%"))
    (format t "~&@PSW done~%")))
