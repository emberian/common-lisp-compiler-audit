(in-package "ACL2")

(defevaluator ev-cp ev-cp-lst ((if x y z) (not x)))

(defstobj st (fld :type integer :initially 0))

(defun read-st (st)
  (declare (xargs :stobjs st :guard t))
  (fld st))

(memoize 'read-st)

(defun conflict-fn () 2)

;; Failed include-book: loads st_lst_helper_book compiled file (running (defg <st-lst> nil)!),
;; then fails on conflicting (defun conflict-fn () 1) and rolls back!
(mv-let (erp val state)
  (ld '((include-book "st_lst_helper_book"))
      :ld-error-action :return!)
  (declare (ignore val))
  (prog2$ (cw "@AFTER-FAILED-INCLUDE erp=~x0~%" erp)
          state))

(defun leak-cp (clause hint st)
  (declare (xargs :stobjs st :guard t)
           (ignore hint))
  (let* ((st (update-fld 0 st))
         (v0 (read-st st))
         (st (update-fld 1 st))
         (v1 (read-st st))
         (actual (fld st)))
    (prog2$ (cw "@CP v0=~x0 v1=~x1 actual=~x2~%" v0 v1 actual)
            (if (equal v1 actual)
                (mv nil (list clause) st)
              (mv nil nil st)))))

(defthm leak-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (ev-cp (conjoin-clauses (clauses-result (leak-cp clause hint st))) a))
           (ev-cp (disjoin clause) a))
  :rule-classes :clause-processor)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (leak-cp clause nil st)))
  :rule-classes nil)

(make-event
 (let ((w (w state)))
   (prog2$ (cw "@RESULT host=~x0 defined=~x1 formula=~x2 ttag=~x3 ttags-seen=~x4~%"
               (@ host-lisp)
               (not (eq (getpropc 'nil-proved 'theorem :none w) :none))
               (getpropc 'nil-proved 'theorem :none w)
               (ttag w)
               (global-val 'ttags-seen w))
           '(value-triple :done))))
