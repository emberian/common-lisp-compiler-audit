; XDS-S1 + XDS-R1: Plain FOR loop$ / lambda$ with compound of-type (member / real / complex / (or))
; produces a LAMBDA object failing syntactically-plausible-lambda-objectp (translate.lisp:3845, 4140
; vs axioms.lisp:11687, 11784, 11859, 11884), causing special-loop$-scion-callp (history-management.lisp:13269)
; and collect-certain-lambda-objects (translate.lisp:20585) to return NIL and silently drop BOTH
; Special Conjecture (a)/(b) AND the loop$ body's own guard obligations.

;; 1. Direct lambda$ sibling (XDS-R1): body guard (car y) on symbol is skipped at verify-guards,
;;    and calling a valid lambda$ crashes with HARD ACL2 ERROR in APPLY$-LAMBDA!
(defun bogus-body-lambda-member (x)
  (declare (xargs :guard t))
  (apply$ (lambda$ (y)
            (declare (type (member :a :b) y))
            (car y))
          (list x)))
(cw "@LAMBDA-BOGUS-BODY-CLASS ~x0~%" (symbol-class 'bogus-body-lambda-member (w state)))

(defun valid-lambda-member (x)
  (declare (xargs :guard t))
  (apply$ (lambda$ (y)
            (declare (type (member :a :b) y))
            (list y))
          (list x)))
(make-event
 (mv-let (erp val state)
   (trans-eval '(valid-lambda-member :a) 'repro state t)
   (declare (ignore val))
   (prog2$ (cw "@LAMBDA-VALID-CALL-ERP ~x0~%" erp)
           (value '(value-triple :ok)))))

;; 2. Plain FOR loop$ soundness bug (XDS-S1): pure cons + eq + loop$ proof of NIL (zero :df, zero books)!
(defun loop-member-nil (x)
  (declare (xargs :guard t))
  (let ((lst (list (cons x x))))
    (car (loop$ for z of-type (member :a :b) in lst
                collect (eq z '(0 . 0))))))

(cw "@LOOP-CLASS ~x0~%" (symbol-class 'loop-member-nil (w state)))
(cw "@RAW-EVAL ~x0~%" (loop-member-nil 0))

(defthm loop-member-nil-logic
  (equal (loop-member-nil 0) t)
  :hints (("Goal" :in-theory (disable loop-member-nil))))

(memoize 'loop-member-nil)
(make-event (let ((ign (loop-member-nil 0)))
              (declare (ignore ign))
              '(value-triple :warmed)))

(defthm nil-proved
  nil
  :hints (("Goal" :use loop-member-nil-logic
                  :in-theory (disable loop-member-nil loop-member-nil-logic)))
  :rule-classes nil)

(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@END~%")
:q
