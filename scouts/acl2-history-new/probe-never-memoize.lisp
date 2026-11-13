(in-package "ACL2")
; NOTE-7-0 logic/raw return agreement for never-memoize-fn.
(defun some-new-name (x) x)
(verify-guards some-new-name)
(assert-event (equal (never-memoize-fn 'some-new-name) nil))
(defthm never-memoize-fn-is-nil
  (equal (never-memoize-fn fn) nil))
; The raw call above returned NIL while also marking the symbol; memoization of
; that symbol should now be refused rather than changing the logical value.
(memoize 'some-new-name)
(quit)
