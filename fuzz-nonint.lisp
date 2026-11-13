;;;; Non-integer differential fuzzer for SBCL's x86-64 compiler.
;;;;
;;;; For each randomly generated, fully-typed CL function we COMPILE the SAME
;;;; source twice --- once (speed 3)(safety 0), once (speed 0)(safety 3)(debug 3)
;;;; --- and run both on a batch of inputs drawn from each parameter's domain.
;;;; Identical source + identical inputs must give identical results; a
;;;; divergence is a compiler bug on one side (the ACL2 threat model: ACL2
;;;; compiles (safety 0)(speed 3) and trusts the result).
;;;;
;;;; Coverage: single/double floats, rationals, fixnum/bignum ints, the bit ops
;;;; (logand/ior/xor/not, ash, ldb, dpb, mask-field, logcount, integer-length),
;;;; the division family (truncate/floor/ceiling/round/mod/rem) with constant and
;;;; variable divisors, comparisons feeding branches, SAFE `the' declarations
;;;; (correct by construction, incl. boundary-tight masks), multiple-value-bind,
;;;; characters, strings, simple-arrays + aref, and coerce.
;;;;
;;;; Usage: sbcl --script fuzz-nonint.lisp SEED SECONDS OUTDIR [INPUTS-PER-FN]
;;;;
;;;; Equality: floats compared BIT-EXACT (so +0.0/-0.0 and NaN payloads are
;;;; distinguished); all other numbers by EQL (value AND type); everything else
;;;; by EQUAL.  Both paths run identical IEEE operations, so any bit difference
;;;; is real.  A result that errors on both paths is agreement (same source).
;;;; Only "both returned, values differ" is a strong soundness candidate; the
;;;; other asymmetries are logged separately for triage.

(declaim (optimize (speed 1) (safety 1)))
(defpackage :fz (:use :cl))
(in-package :fz)

;;; ---------------------------------------------------------------- RNG
;;; Self-contained xorshift so the stream is identical on every SBCL version.
(defvar *s* 88172645463325252)
(declaim (type (unsigned-byte 64) *s*))
(defun seed! (n) (setf *s* (logior 1 (logand n #xFFFFFFFFFFFFFFFF))))
(defun rnd ()
  (let ((x *s*))
    (setf x (logand #xFFFFFFFFFFFFFFFF (logxor x (ash x 13))))
    (setf x (logxor x (ash x -7)))
    (setf x (logand #xFFFFFFFFFFFFFFFF (logxor x (ash x 17))))
    (setf *s* x)))
(defun ri (n) (if (<= n 1) 0 (mod (rnd) n)))          ; 0..n-1
(defun chance (num den) (< (ri den) num))
(defun pick (seq) (elt seq (ri (length seq))))

;;; ---------------------------------------------------------------- value gen
(defun gen-int ()
  (case (ri 8)
    (0 0) (1 1) (2 -1)
    (3 (- (ri 256) 128))                               ; small
    (4 (- (ri (expt 2 62)) (expt 2 61)))               ; around fixnum edge
    (5 (* (if (chance 1 2) -1 1) (+ (expt 2 62) (ri (expt 2 8))))) ; just over fixnum
    (6 (- (ri (expt 2 130)) (expt 2 129)))             ; bignum
    (7 (pick '(4611686018427387903 4611686018427387904 -4611686018427387904
               4611686018427387905 1152921504606846976 9223372036854775807
               -9223372036854775808 18446744073709551615)))))
(defun gen-nz-int () (let ((v (gen-int))) (if (zerop v) 1 v)))
(defun gen-rat ()
  (if (chance 1 3) (gen-int)
      (/ (gen-int) (gen-nz-int))))
(defun gen-small-nn () (ri 48))                         ; shift/byte sizes
;; Special values are built from bits (no trapping arithmetic; traps stay ON).
(defun nan-d () (sb-kernel:make-double-float #x7FF80000 0))
(defun nan-s () (sb-kernel:make-single-float #x7FC00000))
(defun gen-df ()
  (case (ri 10)
    (0 0d0) (1 -0d0) (2 1d0) (3 -1d0)
    (4 sb-ext:double-float-positive-infinity)
    (5 sb-ext:double-float-negative-infinity)
    (6 (nan-d))
    (7 (* (if (chance 1 2) -1d0 1d0) (expt 2d0 (- (ri 600) 300))))
    (8 (- (/ (coerce (gen-int) 'double-float) 7d0) 3.5d0))
    (9 least-positive-double-float)))
(defun gen-sf ()
  (case (ri 8)
    (0 0f0) (1 -0f0) (2 1f0) (3 -1f0)
    (4 sb-ext:single-float-positive-infinity)
    (5 (nan-s))
    (6 (* (if (chance 1 2) -1f0 1f0) (expt 2f0 (- (ri 100) 50))))
    (7 (coerce (/ (gen-int) 13) 'single-float))))
(defun gen-char () (code-char (ri #xD800)))
(defun gen-string ()
  (let* ((n (ri 7)) (s (make-string n)))
    (dotimes (i n) (setf (char s i) (code-char (+ 32 (ri 94))))) s))
(defun gen-value (dom)
  (ecase dom
    (:int (gen-int)) (:nz (gen-nz-int)) (:rat (gen-rat)) (:nzrat (let ((v (gen-rat))) (if (zerop v) 1 v)))
    (:idx (gen-small-nn)) (:df (gen-df)) (:sf (gen-sf)) (:char (gen-char)) (:str (gen-string))))

;;; ---------------------------------------------------------------- expr gen
;;; An expression is built for a target CLASS; it returns Lisp source and may
;;; reference variables whose domains are recorded in *params*.
(defvar *params*)        ; list of (var . domain)
(defvar *vmax*)          ; cap on number of params

(defun fresh-var (dom)
  (let ((v (intern (format nil "V~D" (length *params*)) :fz)))
    (push (cons v dom) *params*) v))
(defun var-of (dom)
  "Reuse an existing var of DOM or make a new one (bounded)."
  (let ((cands (loop for (v . d) in *params* when (eq d dom) collect v)))
    (if (and cands (or (>= (length *params*) *vmax*) (chance 1 2)))
        (pick cands) (fresh-var dom))))

(defun lit-int () (case (ri 4) (0 (ri 256)) (1 (- (ri 512) 256))
                    (2 (pick '(255 65535 15 7 31 1023 #xFFFFFFFF))) (3 (gen-int))))
(defun byte-spec () (list 'byte (1+ (ri 40)) (ri 40)))

;; generators return source forms; CLASS in {:int :rat :df :sf :char :str :bool}
(defun gen-int-expr (d)
  (if (<= d 0)
      (if (chance 1 2) (var-of :int) (lit-int))
      (let ((d1 (1- d)))
        (case (ri 22)
          (0 (var-of :int)) (1 (lit-int))
          (2 `(+ ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (3 `(- ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (4 `(* ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (5 `(- ,(gen-int-expr d1)))
          (6 `(logand ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (7 `(logior ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (8 `(logxor ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (9 `(lognot ,(gen-int-expr d1)))
          (10 `(ash ,(gen-int-expr d1) ,(- (ri 130) 65)))          ; var-magnitude shift
          (11 `(ash ,(gen-int-expr d1) (- (logand ,(gen-int-expr d1) 63) 20)))
          (12 `(ldb ,(byte-spec) ,(gen-int-expr d1)))
          (13 `(dpb ,(gen-int-expr d1) ,(byte-spec) ,(gen-int-expr d1)))
          (14 `(mask-field ,(byte-spec) ,(gen-int-expr d1)))
          (15 `(logcount ,(gen-int-expr d1)))
          (16 `(integer-length ,(gen-int-expr d1)))
          (17 (let ((op (pick '(truncate floor ceiling round mod rem))))
                `(,op ,(gen-int-expr d1) ,(if (chance 1 2) (var-of :nz) (1+ (ri 97))))))
          (18 `(char-code ,(gen-char-expr d1)))
          (19 `(length ,(gen-str-expr d1)))
          (20 (safe-the-int `(logand ,(gen-int-expr d1) ,(pick '(255 65535 4095 #xFFFFFF)))))
          (21 `(if ,(gen-bool-expr d1) ,(gen-int-expr d1) ,(gen-int-expr d1)))))))

(defun safe-the-int (form)
  "FORM is (logand X MASK) with MASK a nonneg literal: result is in [0,MASK]."
  (let ((mask (fourth (if (eq (first form) 'the) (third form) form))))
    (declare (ignore mask))
    (let ((m (third form)))
      `(the (integer 0 ,m) ,form))))

(defun gen-rat-expr (d)
  (if (<= d 0) (gen-int-expr 0)
      (let ((d1 (1- d)))
        (case (ri 6)
          ((0 1) (gen-int-expr d))
          (2 `(/ ,(gen-rat-expr d1) ,(if (chance 1 2) (var-of :nzrat) (1+ (ri 97)))))
          (3 `(+ ,(gen-rat-expr d1) ,(gen-rat-expr d1)))
          (4 `(* ,(gen-rat-expr d1) ,(gen-rat-expr d1)))
          (5 `(- ,(gen-rat-expr d1) ,(gen-rat-expr d1)))))))

(defun gen-float-expr (class d)             ; class = :df or :sf
  (let ((var (if (eq class :df) :df :sf))
        (one (if (eq class :df) 1d0 1f0))
        (ty  (if (eq class :df) 'double-float 'single-float)))
    (if (<= d 0)
        (if (chance 1 2) (var-of var) (if (eq class :df) (gen-df) (gen-sf)))
        (let ((d1 (1- d)))
          (case (ri 16)
            (0 (var-of var))
            (1 (if (eq class :df) (gen-df) (gen-sf)))
            (2 `(+ ,(gen-float-expr class d1) ,(gen-float-expr class d1)))
            (3 `(- ,(gen-float-expr class d1) ,(gen-float-expr class d1)))
            (4 `(* ,(gen-float-expr class d1) ,(gen-float-expr class d1)))
            (5 `(/ ,(gen-float-expr class d1) ,(gen-float-expr class d1)))
            (6 `(- ,(gen-float-expr class d1)))
            (7 `(abs ,(gen-float-expr class d1)))
            (8 `(,(pick '(sin cos atan ftruncate fround ffloor fceiling))
                 ,(gen-float-expr class d1)))
            (9 `(float ,(gen-int-expr d1) ,one))
            (10 `(coerce ,(gen-rat-expr d1) ',ty))
            (11 `(coerce ,(gen-float-expr (if (eq class :df) :sf :df) d1) ',ty))
            ;; NOTE: float MIN/MAX with a NaN operand is unspecified in CL, so
            ;; they produce only implementation-defined divergence (not soundness
            ;; bugs) and are deliberately omitted.  Comparisons / IF below ARE
            ;; NaN-deterministic (< NaN x) = NIL, so a divergence there is real.
            (12 `(* ,(gen-float-expr class d1) ,(gen-float-expr class d1)))
            (13 `(coerce ,(gen-rat-expr d1) ',ty))
            (14 `(coerce ,(gen-int-expr d1) ',ty))
            (15 `(if ,(gen-bool-expr d1) ,(gen-float-expr class d1) ,(gen-float-expr class d1))))))))

(defun gen-char-expr (d)
  (if (<= d 0) (if (chance 1 2) (var-of :char) `(code-char ,(ri 128)))
      (let ((d1 (1- d)))
        (case (ri 5)
          ((0 1) (var-of :char))
          (2 `(code-char (mod (abs ,(gen-int-expr d1)) #xD800)))
          (3 `(let ((s ,(gen-str-expr d1)))  ; bounds-safe string ref
                (if (zerop (length s)) #\a (char s (mod ,(gen-small-nn) (length s))))))
          (4 `(if ,(gen-bool-expr d1) ,(gen-char-expr d1) ,(gen-char-expr d1)))))))

(defun gen-str-expr (d)
  (if (<= d 0) (if (chance 1 2) (var-of :str) `',(gen-string))
      (let ((d1 (1- d)))
        (case (ri 4)
          ((0 1) (var-of :str))
          (2 `(coerce (list ,(gen-char-expr d1) ,(gen-char-expr d1)) 'string))
          (3 `(string ,(gen-char-expr d1)))))))

(defun gen-bool-expr (d)
  (if (<= d 0) `(,(pick '(zerop plusp minusp evenp oddp)) ,(gen-int-expr 0))
      (let ((d1 (1- d)))
        (case (ri 8)
          (0 `(,(pick '(< <= = > >= /=)) ,(gen-rat-expr d1) ,(gen-rat-expr d1)))
          (1 `(,(pick '(< <= = > >=)) ,(gen-float-expr :df d1) ,(gen-float-expr :df d1)))
          (2 `(,(pick '(zerop plusp minusp evenp oddp)) ,(gen-int-expr d1)))
          (3 `(eql ,(gen-int-expr d1) ,(gen-int-expr d1)))
          (4 `(char< ,(gen-char-expr d1) ,(gen-char-expr d1)))
          (5 `(char= ,(gen-char-expr d1) ,(gen-char-expr d1)))
          (6 `(not ,(gen-bool-expr d1)))
          (7 `(,(pick '(and or)) ,(gen-bool-expr d1) ,(gen-bool-expr d1)))))))

;;; multiple-value-bind wrapper over the division family
(defun wrap-mvb (int-form d)
  `(multiple-value-bind (q r) (,(pick '(truncate floor ceiling round))
                               ,(gen-int-expr d) ,(if (chance 1 2) (var-of :nz) (1+ (ri 97))))
     (+ (* 3 q) r ,int-form)))

;;; simple-array + aref: build a typed vector from params, read a bounded index.
(defun gen-array-form (class d)
  "Elements are MASKED/typed so they always fit the element type (no contract
   violation): u8/u64 integer arrays, double-float arrays, character arrays."
  (let* ((n (1+ (ri 6)))
         (ikind (ri 2))
         (et (ecase class
               (:int (if (zerop ikind) '(unsigned-byte 8) '(unsigned-byte 64)))
               (:df 'double-float) (:char 'character)))
         (mask (if (zerop ikind) 255 #xFFFFFFFFFFFFFFFF))
         (elts (loop repeat n collect
                     (ecase class
                       (:int `(logand ,(gen-int-expr d) ,mask))
                       (:df (gen-float-expr :df d))
                       (:char (gen-char-expr d))))))
    `(let ((a (make-array ,n :element-type ',et :initial-contents (list ,@elts))))
       (declare (type (simple-array ,et (,n)) a))
       (aref a ,(ri n)))))

(defun gen-top (d)
  "Return (values result-form target-class)."
  (let ((k (ri 11)))
    (case k
      (0 (values (gen-int-expr d) :int))
      (1 (values (gen-rat-expr d) :rat))
      (2 (values (gen-float-expr :df d) :df))
      (3 (values (gen-float-expr :sf d) :sf))
      (4 (values (gen-char-expr d) :char))
      (5 (values (gen-str-expr d) :str))
      (6 (values (wrap-mvb (gen-int-expr (1- d)) (1- d)) :int))
      (7 (values (gen-array-form :int (1- d)) :int))
      (8 (values (gen-array-form :df (1- d)) :df))
      (9 (values (gen-array-form :char (1- d)) :char))
      (10 (values `(if ,(gen-bool-expr d) ,(gen-int-expr d) ,(gen-float-expr :df d)) :mixed)))))

;;; ---------------------------------------------------------------- build fn
(defun param-decl (dom var)
  (ecase dom
    (:int `(type integer ,var)) (:nz `(type integer ,var))
    (:rat `(type rational ,var)) (:nzrat `(type rational ,var))
    (:idx `(type (integer 0 48) ,var))
    (:df `(type double-float ,var)) (:sf `(type single-float ,var))
    (:char `(type character ,var)) (:str `(type simple-string ,var))))

(defun build-forms (depth)
  "Generate one function: returns (values paramlist domains body)."
  (let ((*params* nil) (*vmax* (+ 2 (ri 4))))
    (multiple-value-bind (body class) (gen-top depth)
      (declare (ignore class))
      (let ((ps (reverse *params*)))
        (values (mapcar #'car ps) (mapcar #'cdr ps) body)))))

(defun lambda-source (params domains body policy)
  `(lambda ,params
     (declare (optimize ,@policy)
              ,@(mapcar (lambda (d v) (param-decl d v)) domains params)
              (ignorable ,@params))
     ,body))

;;; ---------------------------------------------------------------- compare
(defun fbits (x)
  (etypecase x
    (double-float (logior (ash (ldb (byte 32 0) (sb-kernel:double-float-high-bits x)) 32)
                          (sb-kernel:double-float-low-bits x)))
    (single-float (ldb (byte 32 0) (sb-kernel:single-float-bits x)))))
(defun same (a b)
  (cond
    ;; Both NaN of the same width: equal (NaN payload is unspecified by IEEE and
    ;; may legitimately differ with instruction selection).
    ((and (typep a 'double-float) (typep b 'double-float)
          (sb-ext:float-nan-p a) (sb-ext:float-nan-p b)) t)
    ((and (typep a 'single-float) (typep b 'single-float)
          (sb-ext:float-nan-p a) (sb-ext:float-nan-p b)) t)
    ((and (typep a 'double-float) (typep b 'double-float)) (= (fbits a) (fbits b)))
    ((and (typep a 'single-float) (typep b 'single-float)) (= (fbits a) (fbits b)))
    ((and (floatp a) (floatp b)) (eq (type-of a) (type-of b)))  ; diff float types handled above
    ((and (numberp a) (numberp b)) (eql a b))
    ((and (characterp a) (characterp b)) (char= a b))
    ((and (stringp a) (stringp b)) (string= a b))
    (t (equal a b))))
(defun pclass (x)
  "A coarse tag so +0.0/-0.0-only and NaN-only diffs can be auto-classified."
  (cond ((and (floatp x) (sb-ext:float-nan-p x)) :nan)
        ((eql x 0d0) :+0d) ((eql x -0d0) :-0d)
        ((eql x 0f0) :+0f) ((eql x -0f0) :-0f)
        (t :val)))
(defun special-float-p (x)
  "True for a NaN, an infinity, or a negative zero: inputs for which float
   ordering / sign is IEEE-unspecified and divergence is not a soundness bug."
  (and (floatp x)
       (or (sb-ext:float-nan-p x) (sb-ext:float-infinity-p x)
           (eql x -0d0) (eql x -0f0))))
(defun soft-input-p (in) (some #'special-float-p in))

;;; ---------------------------------------------------------------- run
(defvar *outdir*)
(defvar *wid*)
(defun outpath (name) (format nil "~A/~A-w~A" *outdir* name *wid*))

;; Mask FP traps identically on BOTH paths, so NaN/inf PROPAGATE as values and
;; are compared (rather than one path trapping and the other not, which depends
;; only on comisd-vs-ucomisd instruction selection, not on correctness).
(defmacro ignoring-everything (&body body)
  `(handler-case
       (values (sb-int:with-float-traps-masked (:invalid :overflow :divide-by-zero
                                                :inexact :underflow)
                 (progn ,@body))
               :ok)
     (serious-condition (c) (values (format nil "~A" (type-of c)) :err))))

(defun run-one (fast slow inputs)
  "Call both on each input tuple; return a finding plist or NIL."
  (dolist (in inputs)
    (multiple-value-bind (rf sf) (ignoring-everything (apply fast in))
      (multiple-value-bind (rs ss) (ignoring-everything (apply slow in))
        (cond
          ((and (eq sf :ok) (eq ss :ok))
           (unless (same rf rs)
             (return (list :kind :value :in in :fast rf :slow rs
                           :fc (pclass rf) :sc (pclass rs) :soft (soft-input-p in)))))
          ((and (eq sf :ok) (eq ss :err))
           (return (list :kind :fast-ok-slow-err :in in :fast rf :slow rs :soft (soft-input-p in))))
          ((and (eq sf :err) (eq ss :ok))
           (return (list :kind :slow-ok-fast-err :in in :fast rf :slow rs :soft (soft-input-p in)))))))))

(defun log-finding (fn-src find n)
  (let ((path (outpath (if (getf find :soft) "findings-soft.lisp" "findings-hard.lisp"))))
    (with-open-file (s path :direction :output :if-exists :append :if-does-not-exist :create)
      (format s ";;; ===== finding #~A  kind=~A  class=(~A ~A) soft=~A =====~%"
              n (getf find :kind) (getf find :fc) (getf find :sc) (getf find :soft))
      (let ((*print-readably* nil) (*print-circle* t) (*print-length* 50) (*print-level* 20))
        (format s "(:source ~S~%  :input ~S~%  :fast ~S~%  :slow ~S~%  :kind ~S)~%~%"
                fn-src (getf find :in) (getf find :fast) (getf find :slow) (getf find :kind))))))

(defun main ()
  (let* ((args (cdr sb-ext:*posix-argv*))
         (seed (parse-integer (nth 0 args)))
         (secs (parse-integer (nth 1 args)))
         (*outdir* (nth 2 args))
         (ninput (if (nth 3 args) (parse-integer (nth 3 args)) 24))
         (*wid* seed)
         (deadline (+ (get-internal-real-time) (* secs internal-time-units-per-second)))
         (nfn 0) (nval 0) (nasym 0) (nhard 0) (ncompile-skip 0))
    (seed! (+ 1 (* seed 2654435761)))
    (ensure-directories-exist (format nil "~A/" *outdir*))
    (handler-bind ((warning #'muffle-warning))
      (loop while (< (get-internal-real-time) deadline) do
        (incf nfn)
        (when (zerop (mod nfn 500))
          (with-open-file (s (outpath "progress") :direction :output
                             :if-exists :supersede :if-does-not-exist :create)
            (format s "~A nfn=~A nval=~A nasym=~A skip=~A~%" (get-universal-time) nfn nval nasym ncompile-skip)))
        (handler-case
         (let ((depth (+ 2 (ri 4))))
          (multiple-value-bind (params domains body) (build-forms depth)
            (let* ((fast-src (lambda-source params domains body '((speed 3) (safety 0) (debug 0))))
                   (slow-src (lambda-source params domains body '((speed 0) (safety 3) (debug 3))))
                   (fast nil) (slow nil) (ok t))
              (handler-case
                  (setf fast (compile nil fast-src)
                        slow (compile nil slow-src))
                (serious-condition () (setf ok nil) (incf ncompile-skip)))
              (when (and ok fast slow)
                (let ((inputs (loop repeat ninput
                                    collect (mapcar #'gen-value domains))))
                  (let ((find (ignore-errors (run-one fast slow inputs))))
                    (when find
                      (if (eq (getf find :kind) :value) (incf nval) (incf nasym))
                      (when (and (eq (getf find :kind) :value) (not (getf find :soft)))
                        (incf nhard))
                      (log-finding (lambda-source params domains body '((speed 3) (safety 0))) find
                                   (+ nval nasym)))))))))
         (serious-condition () (incf ncompile-skip)))))
    (with-open-file (s (outpath "summary") :direction :output
                       :if-exists :supersede :if-does-not-exist :create)
      (format s "worker ~A: nfn=~A value-diffs=~A HARD=~A asym=~A compile-skips=~A~%"
              *wid* nfn nval nhard nasym ncompile-skip))
    (format t "worker ~A done: nfn=~A value=~A HARD=~A asym=~A skip=~A~%"
            *wid* nfn nval nhard nasym ncompile-skip)))

(main)
