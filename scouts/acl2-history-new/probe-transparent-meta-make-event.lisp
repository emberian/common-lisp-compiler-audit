(in-package "ACL2")
; NOTE-8-6 transparent metafunction exported from signed encapsulate.
(defstub f () t)
(defevaluator evl evl-list ((f)))
(encapsulate
  ((my-meta-fn (x) x))
  (local (defun my-meta-fn (x)
           (if (equal x '(f)) (list 'quote (f)) x)))
  (defthm my-meta-fn-correct
    (equal (evl x a) (evl (my-meta-fn x) a))
    :rule-classes ((:meta :trigger-fns (f)))))
; Newer make-event route to the same signed-encapsulate check.
(make-event
 '(encapsulate
   ((my-meta-fn-me (x) x))
   (local (defun my-meta-fn-me (x)
            (if (equal x '(f)) (list 'quote (f)) x)))
   (defthm my-meta-fn-me-correct
     (equal (evl x a) (evl (my-meta-fn-me x) a))
     :rule-classes ((:meta :trigger-fns (f))))))
(quit)
