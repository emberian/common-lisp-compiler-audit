;;; Classify the SBCL table entries NOT reached by a coverage set, by whether an
;;; ACL2 book can reach them at all.
;;;   sbcl --script classify.lisp SEEN.sexp [SEEN2.sexp ...] > report
;;; SEEN files are lists of key strings ("T:<transform key>", "V:<vop>") as
;;; written by synth/fuzz.lisp, synth/measure.lisp and synth/exhaust.lisp.
;;; The full tables come from coverage/data/acl2-sbcl-tables.sexp (dumped from
;;; the SBCL-hosted ACL2 image).  Classification is by name and signature
;;; patterns, first match wins; it is a reading of the tables, not a proof.
(defun rd (p)
  (loop (handler-case
            (return (with-open-file (s p) (let ((*package* (find-package :cl))) (read s))))
          (sb-int:simple-reader-package-error (c) (make-package (package-error-package c) :use nil)))))

(defparameter *acl2-cl-names*
  ;; CL-package functions that have deftransforms AND are ACL2 functions or macros
  ;; (computed in the ACL2 image; see coverage/data/acl2-cl-names.sexp)
  (with-open-file (s "/Users/ember/dev/compiler-audit/coverage/data/acl2-cl-names.sexp") (read s)))

(defparameter *classes*
  ;; (class reachable-p reason)
  '((cl-function-not-in-acl2 nil "deftransform of a Common Lisp function that is not an ACL2 function or macro (sequence, array, I/O, pathname, transcendental ... functions); an ACL2 definition cannot call it")
    (single-float nil "ACL2 has no single-floats (df is double-float only)")
    (complex-float nil "ACL2 complex numbers are complex rationals; specialised complex-float code never applies")
    (ffi nil "no foreign memory or foreign calls in ACL2 code")
    (simd nil "no SIMD objects in ACL2")
    (concurrency nil "no atomic operations, barriers or interrupts in ACL2 code")
    (safety nil "emitted only when checks or instrumentation are compiled in; ACL2 compiles at safety 0")
    (bignum-runtime nil "used only inside SBCL's own bignum implementation, never in compiled user code")
    (runtime-objects nil "structure instances, closures, code objects, special-variable cells, stack and allocator internals: not expressible in ACL2 definitions")
    (float-internals nil "float decoding, bit access and transcendental kernels: reachable only through ACL2's constrained df-sin, df-exp ..., which have no logical value to compare against; not generated")
    (double-float t "ACL2 df arithmetic (df+ df* df/ df< df-sqrt to-df from-df), inlined in raw Lisp")
    (character t "char-code code-char char< char-upcase ... on declared characters")
    (string t "length, char and string comparisons on declared strings")
    (specialised-array t "stobj array fields: one element type per SBCL specialised vector")
    (sequence-internals t "internal targets of member, assoc, position, concatenate, subseq ... when ACL2 leaves those to the host")
    (integer-and-rational t "integer and rational arithmetic, comparisons, shifts, bit operations, type tests, conses, symbols, calls and moves")))

(defun has (key &rest pats) (some (lambda (p) (search p key)) pats))

(defun key-name (key)
  (let* ((start (if (eql 0 (search "T:(" key)) 3 2))
         (end (or (position #\Space key :start start) (length key))))
    (subseq key start end)))

(defun classify (key)
  (let* ((name (key-name key)) (tp (eql 0 (search "T:" key)))
         (clp (and tp (not (find #\: name)))))
    (cond ((has key "SINGLE-FLOAT" "/SINGLE" "SINGLE-") 'single-float)
          ((has name "SINGLE") 'single-float)
          ((and clp (not (member name *acl2-cl-names* :test #'string=))) 'cl-function-not-in-acl2)
          ((or (has name "COMPLEX-DOUBLE" "COMPLEX-FLOAT" "COMPLEX-REAL" "REAL-COMPLEX" "/COMPLEX"
                    "COMPLEX-RATIONAL-P" "COMPLEX-VECTOR")
               (and tp (has key "(COMPLEX DOUBLE" "(COMPLEX FLOAT" "(COMPLEX SINGLE" "COMPLEX-DOUBLE")))
           'complex-float)
          ((has name "SAP" "ALIEN" "FOREIGN" "CALL-OUT" "C-STRING" "DEPORT" "NATURALIZE") 'ffi)
          ((has name "SIMD" "NEON") 'simd)
          ((has name "CAS" "ATOMIC" "BARRIER" "SPIN-LOOP" "COMPARE-AND-SWAP" "PENDING-INTERRUPT")
           'concurrency)
          ((has name "OVERFLOW" "CHECK-BOUND" "ERROR" "FAILURE" "STEP-INSTRUMENT" "MARK-COVERED"
                "FAILED-AVER" "ILLEGAL-MOVE" "HALT" "CHECK-RANGE" "TYPE-CONSTRAINT" "IN-BOUNDS")
           'safety)
          ((has name "BIGNUM-" "HALF-BIGNUM" "SIGNIFY-DIGIT" "BIGNUM-LOOP" "ADD-W/CARRY" "SUB-W/BORROW"
                "SHIFT-TOWARDS" "DIGIT-ASHL" "DIGIT-LSHR" "DIGIT-0")
           'bignum-runtime)
          ((has name "INSTANCE" "LAYOUT" "STRUCTURE" "CLOSURE" "FUNCALLABLE" "FDEFN" "CODE-" "WEAK"
                "CLASSOID" "SLOT" "PCL" "WIDETAG" "HEADER" "LISP-OBJ" "STACK" "NSP" "ARENA" "TLS"
                "UNWIND" "FLOATING-POINT-MODES" "CURRENT-" "GLOBAL-VALUE" "BOUNDP" "SIMPLE-FUN"
                "COMPUTE-FUN" "POINTER" "REBIND" "COMPILER-BARRIER" "COERCE-TO-POLICY" "FUNCTIONP"
                "SET-ARRAY-DIMENSION" "FILL-POINTER" "ARRAY-STORAGE" "GET-NEXT" "TOUCH-OBJECT"
                "%REST-" "MORE-ARG" "UWP-" "EMIT-LABEL" "PSEUDO-ATOMIC" "RETURN-PASS" "PRINT"
                "STRUCT-RETURN" "RAW-BITS" "REF-128" "CELL-" "HASHED-RETURN" "SYMBOL-HASH" "NAME-HASH"
                "PACKAGE-ID" "DESCRIPTOR-HASH" "DATA-NIL" "UNBOXED-CALL" "SYS-ALLOCATE" "VAR-ALLOC"
                "ALLOCATE-VECTOR-ON" "ALLOC-NUMBER" "ALLOC-TLS" "DEALLOC" "SET-SYMBOL" "SET-NSP"
                "FAST-SYMBOL" "FORMAT-" "PRINC-" "FIND-CLASSOID" "HASH-AS-IF" "BASH-COPY" "BYTE-BLT"
                "VALUES-LIST" "VECTOR-SAP" "SET-FDEFN" "MAKE-ARRAY-HEADER" "%MAKE-SIMPLE-ARRAY"
                "%MAKE-ARRAY" "%VECTOR-WIDETAG" "ARRAY-UNDERLYING" "%MAKE-LIST" "LISTIFY-REST"
                "%DATA-VECTOR-P" "%OTHER-POINTER")
           'runtime-objects)
          ((has name "SCALE-FLOAT" "DECODE-FLOAT" "FLOAT-SIGN" "ROUND-DOUBLE" "DOUBLE-FLOAT-BITS"
                "DOUBLE-FLOAT-HIGH-BITS" "DOUBLE-FLOAT-LOW-BITS" "MAKE-DOUBLE-FLOAT" "%MAKE-DOUBLE-FLOAT"
                "UNARY-CEILING" "UNARY-FLOOR" "UNARY-ROUND" "TO-BIGNUM-DIV" "FLOATP" "FLOAT-P")
           'float-internals)
          ((or (has name "DOUBLE" "FLOAT" "FSQRTD")
               (and tp (has key "DOUBLE-FLOAT" "FLOAT" "(REAL" " REAL")))
           'double-float)
          ((has name "DATA-VECTOR" "SIMPLE-ARRAY" "AREF" "BIT-VECTOR" "SIMPLE-VECTOR" "ARRAY" "SVREF"
                "WITH-ARRAY-DATA" "VECTOR-")
           'specialised-array)
          ((has name "STRING" "CONCATENATE") 'string)
          ((has name "CHAR") 'character)
          ((has name "%MEMBER" "%ASSOC" "%RASSOC" "%ADJOIN" "%FIND-POSITION" "LIST-COPY" "SEQUENCEP"
                "%SETELT" "%MAP" "QUICKFILL" "VECTOR-TO-LIST" "APPEND2" "Append" "List" "Vector"
                "%CHECK-VECTOR" "EXTENDED-SEQUENCE")
           'sequence-internals)
          (t 'integer-and-rational))))

(let* ((tables (rd "/Users/ember/dev/compiler-audit/coverage/data/acl2-sbcl-tables.sexp"))
       (*package* (find-package :cl)) (*print-pretty* nil)
       (all (append (mapcar (lambda (k) (format nil "T:~S" k)) (getf tables :all-transforms))
                    (mapcar (lambda (k) (format nil "V:~S" k)) (getf tables :all-vops))))
       (seen (make-hash-table :test 'equal)))
  (dolist (f (cdr sb-ext:*posix-argv*))
    (dolist (k (with-open-file (s f) (read s))) (setf (gethash k seen) t)))
  (let ((ht (count-if (lambda (k) (and (eql 0 (search "T:" k)) (gethash k seen))) all))
        (hv (count-if (lambda (k) (and (eql 0 (search "V:" k)) (gethash k seen))) all)))
    (format t "reached: ~D of ~D transforms, ~D of ~D VOPs~%~%" ht
            (count-if (lambda (k) (eql 0 (search "T:" k))) all) hv
            (count-if (lambda (k) (eql 0 (search "V:" k))) all)))
  (format t "~28A ~9A ~7A ~7A ~7A ~7A~%" "class" "reachable" "T-all" "T-unhit" "V-all" "V-unhit")
  (let ((ru 0) (uu 0))
    (dolist (c *classes*)
      (let* ((mine (remove-if-not (lambda (k) (eq (classify k) (first c))) all))
             (ts (remove-if-not (lambda (k) (eql 0 (search "T:" k))) mine))
             (vs (remove-if-not (lambda (k) (eql 0 (search "V:" k))) mine))
             (tu (count-if-not (lambda (k) (gethash k seen)) ts))
             (vu (count-if-not (lambda (k) (gethash k seen)) vs)))
        (if (second c) (incf ru (+ tu vu)) (incf uu (+ tu vu)))
        (format t "~28A ~9A ~7D ~7D ~7D ~7D~%" (string-downcase (first c)) (if (second c) "yes" "no")
                (length ts) tu (length vs) vu)))
    (format t "~%unreached entries in classes an ACL2 book cannot reach: ~D~%" uu)
    (format t "unreached entries in classes it can reach: ~D~%~%" ru))
  (dolist (c *classes*)
    (unless (second c) (format t "~(~A~): ~A~%" (first c) (third c))))
  (format t "~%Unreached, reachable classes:~%")
  (dolist (c *classes*)
    (when (second c)
      (format t "~%[~(~A~)] ~A~%" (first c) (third c))
      (dolist (k (sort (remove-if (lambda (k) (or (gethash k seen) (not (eq (classify k) (first c))))) all)
                       #'string<))
        (format t "  ~A~%" (subseq k 0 (min 150 (length k))))))))
