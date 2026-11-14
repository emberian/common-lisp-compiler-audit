;; Probe xtrans-eval unprotected globals and :functional-instance edge cases

;; 1. Computed hint trying to mutate ttags-allowed / acl2-raw-mode-p / writes-okp
(thm (equal x x)
     :hints ((progn
               (pprogn (f-put-global 'ttags-allowed :all state)
                       (f-put-global 'acl2-raw-mode-p t state))
               nil)))

;; Check if ttags-allowed or acl2-raw-mode-p changed outside computed hint
(value-triple (list :after-hint-ttags (@ ttags-allowed)
                    :raw-mode (@ acl2-raw-mode-p)))

;; 2. Override-hint mutating ttags-allowed
(add-override-hints!
 '((pprogn (f-put-global 'ttags-allowed :all state)
           (value nil))))

(thm (equal (cons x y) (cons x y)))
(value-triple (list :after-override-ttags (@ ttags-allowed)))

;; 3. :functional-instance with :program-mode function and :do-not '(preprocess)
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) x)))

(defun prog-id (x)
  (declare (xargs :mode :program))
  x)

;; 3a. Normal clause with :do-not '(preprocess)
(thm (equal (prog-id x) x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-id))))))

;; 3b. Prove NIL or crash via prog-id with inconsistent/non-terminating definition?
(defun prog-bad (x)
  (declare (xargs :mode :program))
  (not (prog-bad x)))

(thm (equal (prog-bad x) x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance ef-id (ef prog-bad))))))

;; 3c. What if prog-bad is used in :guard-hints?
(defun f-guard (x)
  (declare (xargs :guard t :verify-guards nil))
  x)

(verify-guards f-guard
  :hints (("Goal"
           :do-not '(preprocess)
           :use ((:functional-instance ef-id (ef prog-bad))))))

;; 4. :functional-instance with stobjs-in / stobjs-out mismatch!
(defstobj st1 (fld1 :initially 0))

(encapsulate
  (((es *) => *))
  (local (defun es (x) x))
  (defthm es-prop (equal (es x) x)))

(defun st-fn (st1)
  (declare (xargs :stobjs st1))
  (fld1 st1))

(thm (equal (st-fn x) x)
     :hints (("Goal"
              :do-not '(preprocess)
              :use ((:functional-instance es-prop (es st-fn))))))

;; 4b. Stobj single-threadedness violation via FI? (es returns *, st-fn2 updates st1 and returns st1)
(defun st-fn2 (st1)
  (declare (xargs :stobjs st1))
  (update-fld1 42 st1))

(thm (equal (st-fn2 x) x)
     :hints (("Goal"
              :use ((:functional-instance es-prop (es st-fn2))))))

;; 5. Multiple-value (mv) mismatch in :functional-instance!
(defun mv-fn (x)
  (mv x x))

(thm (equal (mv-fn x) x)
     :hints (("Goal"
              :use ((:functional-instance es-prop (es mv-fn))))))

;; 5b. Vice versa: encapsulated mv function instantiated by single-value fn
(encapsulate
  (((emv *) => (mv * *)))
  (local (defun emv (x) (mv x x)))
  (defthm emv-prop (equal (mv-nth 0 (emv x)) x)))

(defun sv-fn (x) x)

(thm (equal (mv-nth 0 (sv-fn x)) x)
     :hints (("Goal"
              :use ((:functional-instance emv-prop (emv sv-fn))))))
