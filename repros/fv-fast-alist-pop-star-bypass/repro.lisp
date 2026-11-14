;; Reproducer for fast-alist-pop* invariant-risk omission
;; Source: books/centaur/misc/fast-alist-pop.lisp:105 & fast-alist-pop-raw.lsp:145-153
(in-package "ACL2")

(include-book "centaur/misc/fast-alist-pop" :dir :system :uncertified-okp t :ttags :all)

(value-triple
 (cw "~%@CHECK fast-alist-pop-inv=~x0 fast-alist-pop*-inv=~x1~%"
     (getprop 'fast-alist-pop 'invariant-risk nil 'current-acl2-world (w state))
     (getprop 'fast-alist-pop* 'invariant-risk nil 'current-acl2-world (w state))))

(defconst *alist1* (hons-acons 'a 2 nil))
(defconst *alist2* (hons-acons 'a 1 *alist1*))

;; Program-mode wrapper calling fast-alist-pop* without invariant-risk protection
(defun pop-corruptor (x)
  (declare (xargs :mode :program))
  (fast-alist-pop* nil x))

;; Corrupt *alist1*'s backing hash table during event expansion
(make-event
 (let ((ignored (pop-corruptor *alist2*)))
   (declare (ignore ignored))
   '(value-triple :corrupted)))

;; Execution via backing hash table reports NIL
(defthmd lemma-exec
  (equal (hons-get 'a *alist1*) nil)
  :hints (("Goal" :in-theory (executable-counterpart-theory :here))))

;; Logical definition via hons-assoc-equal reports (A . 2)
(defthmd lemma-logic
  (equal (hons-get 'a *alist1*) '(a . 2))
  :hints (("Goal" :in-theory (e/d (hons-get hons-assoc-equal) ((:e hons-get))))))

;; Contradiction: prove NIL
(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance lemma-exec) (:instance lemma-logic)))))
