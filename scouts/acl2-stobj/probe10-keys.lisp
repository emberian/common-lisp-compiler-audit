; Probe 10: hash-table keys under stress.
; (a) mixed-type key set: raw keys (hash iteration -> merge-sort-lexorder)
;     vs logical keys (alist order -> merge-sort-lexorder).
; (b) EQL vs EQUAL for bignum/ratio/complex keys: logical h-get uses
;     hons-assoc-equal (EQUAL); raw uses EQL gethash.

(defstobj kh (h :type (hash-table eql)))

; ---- (a) mixed keys ----
(defun fill-a (kh)
  (declare (xargs :stobjs kh :verify-guards t))
  (let* ((kh (h-put 'beta 1 kh))
         (kh (h-put 3/4 3 kh))
         (kh (h-put #\c 4 kh))
         (kh (h-put 100 5 kh))
         (kh (h-put -5 7 kh))
         (kh (h-put 'alpha 8 kh)))
    kh))

(defun keys-a (kh)
  (declare (xargs :stobjs kh))
  (h-keys kh))

(fill-a kh)
(keys-a kh)   ; raw: sorted; expect (-5 3/4 100 #\C ALPHA BETA)

(defthm keys-a-log
  (equal (keys-a (fill-a (create-kh)))
         '(-5 3/4 100 #\c alpha beta))
  :rule-classes nil)

; ---- (b) eql vs equal for numbers ----
(value-triple (list :bignum-eql (eql 123456789012345678901 123456789012345678901)
                    :ratio-eql (eql 1/3 (/ 1 3))
                    :complex-eql (eql #c(1 2) (complex 1 2))))

(defun big () (ash 1 100))
(defun big2 () (+ (ash 1 99) (ash 1 99)))
(verify-guards big)
(verify-guards big2)

(defun fill-big (kh)
  (declare (xargs :stobjs kh :verify-guards t))
  (let* ((kh (h-put (big) 1 kh))
         (kh (h-put (big2) 2 kh)))
    kh))

(fill-big kh)
(h-count kh)     ; raw: 1 if host eql value-based, 2 if identity-based
(h-get (big) kh) ; raw: 2 if one entry
(h-keys kh)

(defthm big-count-log
  (equal (h-count (fill-big (create-kh))) 1)
  :rule-classes nil)

(defthm big-get-log
  (equal (h-get (big) (fill-big (create-kh))) 2)
  :rule-classes nil)

(defthm big-keys-log
  (equal (h-keys (fill-big (create-kh)))
         (list (big)))
  :rule-classes nil)

(quit)
