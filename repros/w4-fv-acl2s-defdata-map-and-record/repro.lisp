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
(in-package "ACL2S")

;; 1. books/acl2s/defdata/map.lisp:160,199 ?valpred copy-paste bug:
;;    Mutual-recursive map checks keybody instead of valbody in M, failing on valpred lookup.
(defdata
  (kmap (map k v))
  (k nat)
  (v (oneof nil kmap)))

;; 2. books/acl2s/defdata/record.lisp: cross-package field names collide on VAR-RPKG-A in LET
(defdata cross-rec (record (acl2::a . nat) (acl2s::a . integer)))
