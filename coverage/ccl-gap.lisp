;;; Gap report for CCL compiler-table coverage dumps written by ccl-cov.lisp.
;;;   darm64cl -n --batch --load /Users/ember/dev/compiler-audit/coverage/ccl-gap.lisp
;;; Reads every data/ccl-*.sexp (reached sets are unioned, counts summed) and
;;; lists the unreached entries of each table that integer, list, character or
;;; control-flow code could reach, with the type or operand information the
;;; table carries.  Entries about floats, foreign memory, arrays and strings,
;;; CLOS and the runtime's own plumbing are counted but not listed.
(in-package :cl-user)

(defparameter *dumps*
  (directory "/Users/ember/dev/compiler-audit/coverage/data/ccl-*.sexp"))

(defun rd (p)
  (with-open-file (s p) (let ((*package* (find-package :cl))) (read s))))

;;; Name fragments.  A name is classified by the first rule that matches.
(defparameter *out-of-scope*
  '(("float" "FLOAT" "COMPLEX" "SINGLE" "DOUBLE" "FPR" "FPU" "SQRT")
    ("foreign" "FF-CALL" "C-FRAME" "C-ARG" "MACPTR" "PTR" "MEM-" "%GET-" "%SET-" "IMMEDIATE-GET" "IMMEDIATE-SET"
     "FOREIGN" "EXTERNAL-ENTRY" "EEP." "STACK-BLOCK" "DEREF")
    ("array/string" "MISC" "UVECTOR" "UVREF" "UVSET" "AREF" "ASET" "SVSET" "SVREF" "VECTOR" "ARRAY" "2D-" "3D-"
     "SCHAR" "SBCHAR" "STRING" "BIT-TO" "-BIT" "SBITSET" "TYPECODE-P" "SEARCH" "CONCATENATE" "SEQUENCE")
    ("clos/struct" "SLOT" "CLASS" "INSTANCE" "STRUCT" "STANDARD-OBJECT")
    ("runtime" "TCR" "FRAME-PTR" "LAP-FUNCTION" "SYMPTR" "SYMVECTOR" "MARKER" "DEBUG" "ERR-DISP" "BADARG"
     "PKG" "PACKAGE" "INTERN" "FIND-SYMBOL" "STREAM" "FORMAT" "WRITE" "READ" "LOCK" "PROCLAIM" "ENCODING"
     "SUBTYPEP" "COERCE" "NFP-" "WORD-REF" "FIXNUM-REF" "FIXNUM-SET" "FULLTAG" "%DEFUN" "REQUIRE-SYMBOL"
     "COMPILER-LET" "EVAL-WHEN" "DECLARE" "DBG" "FBIND" "NFUNCTION" "CLOSURE-FORWARD" "TAG-AS-FUNCTION")))

(defparameter *in-scope*
  '(("character" "CHAR")
    ("list" "CONS" "LIST" "CAR" "CDR" "RPLAC" "NTH" "ENDP" "MEMBER" "MEMQ" "MEMEQ" "ASSOC" "ASSQ" "ASSEQ"
     "APPEND" "LAST" "GETF" "ADJOIN" "UNION" "MAPC" "REMOVE-IF" "FIND-IF" "POSITION-IF" "SOME" "EVERY"
     "NOTANY" "NOTEVERY" "REST-ARG")
    ("integer" "FIXNUM" "NATURAL" "INTEGER" "%ILS" "%IASR" "%ILOG" "%I+" "%I-" "%I*" "%I<" "%IZEROP" "%%INEG"
     "LOGTEST" "LOGAND" "LOGIOR" "LOGXOR" "ASH" "LSH" "SHIFT" "POPCOUNT" "BYTE" "REQUIRE-U" "REQUIRE-S"
     "UNBOX" "U8" "U16" "U32" "U64" "S8" "S16" "S32" "S64" "SIGN-EXTEND" "RATIO" "WORD-TO-INT" "INT>0")
    ("control" "MULTIPLE-VALUE" "NTH-VALUE" "VALUES" "CALL" "LEXPR" "NARGS" "-ARGS" "DEFAULT-" "BIND" "INTERRUPT"
     "SETQ" "FREE-REFERENCE" "GLOBAL-" "TYPE-ASSERTED" "INHERITED-ARG" "NEQ" "NULL" "TRUE" "FALSE" "FITVALS"
     "SYMBOLP" "FUNCTIONP" "CONSP" "ATOM" "EQ-BIT" "FUNCALL" "VFRAME" "VCELL" "SYMBOL-REF" "ADJUST-SP"
     "T" "NIL")))

(defun cl-accessor-p (n)                ; CAAR .. CDDDDR
  (and (<= 3 (length n) 6) (char= (char n 0) #\C) (char= (char n (1- (length n))) #\R)
       (every (lambda (c) (find c "AD")) (subseq n 1 (1- (length n))))))

(defun classify (name)
  "Class of a table entry name: (values class in-scope-p)."
  (let ((n (string name)))
    (flet ((hit (rules)
             (loop for (class . frags) in rules
                   when (some (lambda (f) (if (member f '("T" "NIL") :test #'string=)
                                              (string= n f)
                                              (search f n)))
                              frags)
                     return class)))
      (cond ((cl-accessor-p n) (values "list" t))
            ((hit *out-of-scope*) (values (hit *out-of-scope*) nil))
            ((hit *in-scope*) (values (hit *in-scope*) t))
            (t (values "other" nil))))))

(defun spec-class (specs)
  "Operand classes mentioned by a vinsn's vreg specs."
  (remove-duplicates (loop for s in specs when (consp s) collect (second s))))

(defun float-specs-p (v)
  (intersection (append (spec-class (second v)) (spec-class (third v)))
                '(:double-float :single-float :complex-double-float :complex-single-float)))

(defun merged ()
  (let ((ds (mapcar #'rd *dumps*)))
    (unless ds (error "no dumps under coverage/data/ccl-*.sexp"))
    (flet ((u (k) (remove-duplicates (loop for d in ds append (getf d k)) :test #'equal))
           (counts (k)
             (let ((h (make-hash-table :test 'equal)))
               (dolist (d ds) (loop for (name . c) in (getf (getf d :counts) k) do (incf (gethash name h 0) c)))
               h)))
      (append
             (list :n (length ds)
                   :count-cm (counts :cm-won) :count-nx1 (counts :nx1) :count-rewrite (counts :rewrite)
                   :count-p2 (counts :p2) :count-vinsns (counts :vinsns) :count-folded (counts :folded))
             (loop for k in '(:compiler-macros :compiler-macros-tried :constant-folded :nx1 :ops-seen
                              :rewrite :p2 :vinsns)
                   append (list k (u k)))
             ;; the tables themselves are the same in every dump of one image
             (loop for k in '(:all-compiler-macros :all-constant-fold :all-synonyms :all-nx1 :all-acode-ops
                              :all-rewrite :all-p2 :all-vinsns)
                   append (list k (getf (first ds) k)))))))

(defun report-table (title all hit &key (key #'identity) (show #'identity) relevant-p)
  "List the unreached in-scope entries of one table, grouped by class."
  (let* ((un (remove-if (lambda (e) (member (funcall key e) hit :test #'equal)) all))
         (groups (make-hash-table :test 'equal)) (skipped (make-hash-table :test 'equal)))
    (dolist (e un)
      (multiple-value-bind (class in) (classify (funcall key e))
        (when (and in relevant-p (not (funcall relevant-p e))) (setq in nil class "float"))
        (push e (gethash class (if in groups skipped)))))
    (format t "~%== ~A: table ~D, reached ~D, unreached ~D~%" title (length all) (- (length all) (length un))
            (length un))
    (dolist (class '("integer" "list" "character" "control"))
      (let ((es (sort (copy-list (gethash class groups)) #'string< :key (lambda (e) (string (funcall key e))))))
        (when es
          (format t "  -- ~A (~D)~%" class (length es))
          (dolist (e es) (format t "     ~A~%" (funcall show e))))))
    (format t "  not listed:~{ ~A~}~%"
            (loop for class being the hash-keys of skipped using (hash-value es)
                  collect (format nil "~A ~D" class (length es))))))

(defun rare (title h &optional (limit 5))
  (let ((es (sort (loop for k being the hash-keys of h using (hash-value c)
                        when (<= c limit) collect (cons k c))
                  #'< :key #'cdr)))
    (format t "~%== ~A reached at most ~D times (~D entries):~%   ~{~A~^ ~}~%" title limit (length es)
            (mapcar (lambda (e) (format nil "~A:~D" (car e) (cdr e))) es))))

(let* ((d (merged))
       (*package* (find-package :ccl)) (*print-pretty* nil) (*print-right-margin* 200))
  (format t "CCL compiler-table gap, ~D dump~:P: ~{~A~^, ~}~%" (getf d :n) (mapcar #'file-namestring *dumps*))
  (format t "reached/total: compiler-macros ~D/~D  constant-fold ~D/~D  nx1 ~D/~D  rewrite ~D/~D  p2 ~D/~D  vinsns ~D/~D~%"
          (length (getf d :compiler-macros)) (length (getf d :all-compiler-macros))
          (length (getf d :constant-folded)) (length (getf d :all-constant-fold))
          (length (getf d :nx1)) (length (getf d :all-nx1))
          (length (getf d :rewrite)) (length (getf d :all-rewrite))
          (length (getf d :p2)) (length (getf d :all-p2))
          (length (getf d :vinsns)) (length (getf d :all-vinsns)))
  (report-table "compiler macros (optimizers.lisp), expander never returned a new form"
                (getf d :all-compiler-macros) (getf d :compiler-macros)
                :show (lambda (e) (format nil "~S~:[~;   (expander ran, declined)~]" e
                                          (member e (getf d :compiler-macros-tried) :test #'equal))))
  (report-table "constant folding (nx-constant-fold), never folded"
                (getf d :all-constant-fold) (getf d :constant-folded))
  (report-table "nx1 handlers (defnx1), symbol -> handler"
                (getf d :all-nx1) (getf d :nx1) :key #'first
                :show (lambda (e) (format nil "~24S ~S" (first e) (second e))))
  (report-table "acode-rewrite handlers (def-acode-rewrite), operator -> handler"
                (getf d :all-rewrite) (getf d :rewrite) :key #'first
                :show (lambda (e) (format nil "~24S ~S" (first e) (second e))))
  (report-table "arm64 p2 handlers (defarm642), operator : result type"
                (getf d :all-p2) (getf d :p2) :key #'first
                :show (lambda (e)
                        (format nil "~24S ~28S ~S~:[~;   (operator seen by the rewriter, handler never ran)~]"
                                (first e) (third e) (second e) (member (first e) (getf d :ops-seen)))))
  (let ((no-p2 (remove-if (lambda (o) (member (first o) (getf d :all-p2) :key #'first)) (getf d :all-acode-ops))))
    (format t "~%== acode operators with no arm64 p2 handler (~D): ~{~S~^ ~}~%" (length no-p2)
            (mapcar #'first no-p2)))
  (report-table "arm64 vinsn templates (define-arm64-vinsn), name results args temps"
                (getf d :all-vinsns) (getf d :vinsns) :key #'first
                :relevant-p (lambda (e) (not (float-specs-p e)))
                :show (lambda (e) (format nil "~30S -> ~S  <- ~S~@[  temps ~S~]~@[  ~S~]" (first e)
                                          (mapcar #'second (second e)) (mapcar #'second (third e))
                                          (mapcar #'second (fourth e)) (fifth e))))
  (format t "~%== synonyms (nx-transform, not instrumented): ~S~%" (getf d :all-synonyms))
  (rare "p2 handlers" (getf d :count-p2))
  (rare "vinsn templates" (getf d :count-vinsns))
  (rare "acode-rewrite handlers" (getf d :count-rewrite))
  (rare "compiler macros" (getf d :count-cm)))
(ccl:quit 0)
