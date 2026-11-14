(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(defpkg "FTY" (union-eq *acl2-exports* *common-lisp-symbols-from-main-lisp-package*))
(include-book "misc/defattach-bang" :dir :system :ttags nil)
(include-book "std/util/defenum" :dir :system :ttags nil)
(include-book "tools/rewrite-dollar" :dir :system :ttags nil)
(include-book "tools/def-functional-instance" :dir :system :ttags nil)

;; 1. misc/defattach-bang: defattach! drops :stobjs in fn$GUARD-VERIFIED
(defstobj st0 s0)
(encapsulate
  (((stub-st st0) => *))
  (local (defun stub-st (st0) (declare (xargs :stobjs st0)) (s0 st0))))
(defun impl-st (st0) (declare (xargs :stobjs st0 :verify-guards nil)) (s0 st0))
(defattach! stub-st impl-st)

;; 2. std/util/defenum:
;; (a) :member t on string members fails guard verification
(std::defenum str-enum-p ("a" "b") :member t)
;; (b) :default outside enum fails RETURN-TYPE-OF-*
(std::defenum bad-default-p (:a :b) :default :not-a-member)

;; 3. tools/rewrite-dollar: rewrite$-translate-hints passes 13 args to 12-arg fn
(rewrite$-translate-hints 'rewrite$)

;; 4. tools/def-functional-instance: sublis rewrites quoted 'f-stub -> 'g-impl
(encapsulate
  (((f-stub *) => *))
  (local (defun f-stub (x) (equal x 'f-stub)))
  (defthm old-thm (f-stub 'f-stub) :rule-classes nil))
(defun g-impl (x) (equal x 'f-stub))
(def-functional-instance new-thm old-thm ((f-stub g-impl)))

(quit)
