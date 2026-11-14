;; ACL2S-3: CCG crashes with HARD ACL2 ERROR in CHOKE-ON-LOOP$-RECURSION when
;; admitting any valid :loop$-recursion t function under :ccg termination mode,
;; even when an explicit valid :measure is provided.

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

(in-package "ACL2")
(set-termination-method :ccg)

(defun ccg-loop-rec (n)
  (declare (xargs :mode :logic
                  :loop$-recursion t
                  :measure (nfix n)))
  (if (zp n)
      0
    (loop$ for i in (list (1- n)) sum (ccg-loop-rec i))))
