; XDS-R2 + XDS-R3:
;   XDS-R2: FOR loop$ with empty type of-type (integer 1 0) admits and guard-verifies on SBCL 2.6.10,
;           but aborts from raw Lisp during defun compilation on CCL 1.14 (ANSI-LOOP CHARACTER bug).
;   XDS-R3: DO loop$ :guard mentioning an outer variable absent from measure/do-body/finally fails
;           translation because translate11-loop$ (translate.lisp:24957-24964) omits translated-do-body-guard
;           and translated-fin-body-guard when collecting free variables into `vars`.

;; XDS-R3 (both hosts): outer variable `bound` appears only in DO :guard
(defun do-guard-free-var-bug (bound)
  (declare (xargs :guard (natp bound) :verify-guards nil))
  (loop$ with x = 0
         do :measure (acl2-count 0)
            :guard (<= x bound)
            (return x)))
(cw "@DO-GUARD-FREE-VAR-CLASS ~x0~%" (symbol-class 'do-guard-free-var-bug (w state)))

;; XDS-R2 (admits & verifies on SBCL, aborts from raw Lisp on CCL 1.14):
(defun empty-type-loop (lst)
  (declare (xargs :guard (null lst)))
  (loop$ for x of-type (integer 1 0) in lst collect x))

(cw "@EMPTY-TYPE-LOOP-CLASS ~x0~%" (symbol-class 'empty-type-loop (w state)))
(cw "@EMPTY-TYPE-LOOP-EVAL ~x0~%" (empty-type-loop nil))
(cw "@END~%")
:q
