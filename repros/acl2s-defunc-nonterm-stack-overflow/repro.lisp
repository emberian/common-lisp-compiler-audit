;; ACL2S-4: defunc/definec admits unverified non-terminating definitions via
;; (skip-proofs ,defun) inside test?-phase before running test-body-contracts / test?,
;; causing a fatal raw Lisp control-stack overflow before ACL2s's timeout handler fires.

(defpkg "FTY" *acl2-exports*)
(ld "std/package.lsp" :dir :system)
(ld "hacking/hacker-pkg.lsp" :dir :system)
(ld "hacking/rewrite-code-pkg.lsp" :dir :system)
(ld "data-structures/portcullis.acl2" :dir :system)
(ld "coi/symbol-fns/portcullis.acl2" :dir :system)
(ld "acl2s/package.lsp" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(include-book "acl2s/ccg/ccg" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defdata/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/cgen/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defunc" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/definec" :dir :system :ttags :all :uncertified-okp t)
(in-package "ACL2S")

(definec nt-crash (x :nat) :nat
  (1+ (nt-crash x)))
