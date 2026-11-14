;; ACL2S-1: defdata-attach / register-type :skip-checks t bypasses guard verification
;; and triggers a raw Lisp memory fault inside a guard-verified :logic call
;; without the user supplying defttag or :skip-checks.

(defpkg "FTY" *acl2-exports*)
(ld "std/package.lsp" :dir :system)
(ld "data-structures/portcullis.acl2" :dir :system)
(ld "coi/symbol-fns/portcullis.acl2" :dir :system)
(ld "acl2s/package.lsp" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(include-book "acl2s/ccg/ccg" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defdata/top" :dir :system :ttags :all :uncertified-okp t)

(in-package "ACL2S")

;; Un-guard-verified function whose guard claims (natp n) while taking (car n)
(defun evil-nat-enum (n)
  (declare (xargs :guard (natp n) :verify-guards nil))
  (car n))

;; defdata-attach internally opens (defttag :defdata-attach) and executes
;; (defattach (nth-nat evil-nat-enum) :skip-checks t), bypassing guard check.
(defdata-attach nat :enumerator evil-nat-enum)

;; Guard-verified caller passes ACL2's guard verification trivially
(defun verified-nat-caller (n)
  (declare (xargs :guard (natp n) :verify-guards t))
  (nth-nat n))

;; Invoking verified-nat-caller with a valid natp triggers raw Lisp memory fault!
(verified-nat-caller 3)
