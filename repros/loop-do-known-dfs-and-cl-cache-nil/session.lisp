; XDS-S5a, XDS-S5b, XDS-S5c: Three DO loop$ + double-float soundness bugs:
;   S5a (translate-with-var-tuples, translate.lisp:24397): adds var to known-dfs BEFORE translating init-form.
;   S5b (translate-with-var-tuples, translate.lisp:24397): fails to remove shadowed var from known-dfs when spec != double-float.
;   S5c (translate11-do-clause, translate.lisp:23790): passes stobjs-out=t on already-translated binary-df+ term,
;       and verify-guards compiles that LAMBDA into *cl-cache* at (safety 0), feeding boxed alist entries into binary-df+.

(defthm ev$-on-quoted-cons
  (implies (and (syntaxp (quotep x)) (tamep x) (consp x)
                (not (equal (car x) 'quote)) (not (equal (car x) 'if))
                (not (equal (car x) 'apply$)) (not (equal (car x) 'ev$)))
           (equal (ev$ x a) (apply$ (car x) (ev$-list (cdr x) a))))
  :hints (("Goal" :expand ((ev$ x a)))))

(defthm ev$-on-quoted-var-or-quote
  (and (implies (and (syntaxp (quotep x)) (tamep x) (symbolp x))
                (equal (ev$ x a) (cdr (assoc-equal x a))))
       (implies (and (syntaxp (quotep x)) (tamep x) (consp x) (equal (car x) 'quote))
                (equal (ev$ x a) (cadr x))))
  :hints (("Goal" :expand ((ev$ x a)))))

(defthm dfp-df+-0
  (implies (dfp y) (dfp (binary-df+ y 0))))

;; S5c: Completely well-typed, non-shadowed DO loop$ poisons *cl-cache* upon verify-guards!
(defun legal-do-df-unverified ()
  (declare (xargs :verify-guards nil))
  (loop$ with z of-type double-float = (to-df (expt 2 100))
         do :measure (acl2-count 0)
         (return (from-df (df+ z (to-df 0))))))

(cw "@S5C-BEFORE-VG ~x0~%" (legal-do-df-unverified))

(defun legal-do-df-verified ()
  (declare (xargs :guard t
                  :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (loop$ with z of-type double-float = (to-df (expt 2 100))
         do :measure (acl2-count 0)
         (return (from-df (df+ z (to-df 0))))))

(cw "@S5C-AFTER-VG  ~x0~%" (legal-do-df-unverified))

;; S5b: Untyped WITH x = (expt 2 100) fails to remove outer :df x from known-dfs
(defun do-df-unremoved (x)
  (declare (type double-float x)
           (xargs :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (prog2$ (from-df x)
          (loop$ with x = (expt 2 100)
                 with y of-type double-float = x
                 do :measure (acl2-count 0)
                 (return (from-df (df+ y (to-df 0)))))))

(cw "@S5B-RAW-EVAL  ~x0~%" (do-df-unremoved (to-df 0)))

;; S5a: Premature known-dfs addition on WITH v OF-TYPE DOUBLE-FLOAT = v -> full proof of NIL!
(defun do-df-premature (k)
  (declare (xargs :guard (equal k 100)
                  :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (let ((v (expt 2 k)))
    (loop$ with v of-type double-float = v
           do :measure (acl2-count 0)
           (return (from-df (df+ v (to-df 0)))))))

(cw "@S5A-RAW-EVAL  ~x0~%" (do-df-premature 100))

(defthm do-df-premature-logic
  (equal (do-df-premature 100) (expt 2 100))
  :hints (("Goal" :in-theory (e/d (do$ apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim return-last)
                                  ((do-df-premature) (:e do-df-premature) ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe)))))

(memoize 'do-df-premature)
(make-event (let ((ign (do-df-premature 100)))
              (declare (ignore ign))
              '(value-triple :warmed)))

(defthm nil-proved
  nil
  :hints (("Goal" :use do-df-premature-logic
                  :in-theory (disable do-df-premature do-df-premature-logic)))
  :rule-classes nil)

(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@END~%")
:q
