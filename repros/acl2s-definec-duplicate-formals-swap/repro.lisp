;; ACL2S-2: definec silently accepts duplicate parameter names via remove-duplicates,
;; reordering arguments, dropping earlier types from formals, and fusing
;; contradictory contracts to pass guard verification on unsound :exec bodies.

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

;; Bug 2a: duplicate formal `x` causes (remove-duplicates '(x y x)) => (Y X),
;; swapping positional argument order relative to the declaration signature!
(definec sub-dup (x :int y :int x :pos) :int
  (- x y))

;; Inspect stored formals (expect (Y X)) and evaluation (expect -9 instead of 9)
(value-triple (list :FORMALS (acl2::formals 'sub-dup (w state))))
(value-triple (list :EVAL-SUB-DUP (sub-dup 10 1)))

;; Bug 2b: contradictory duplicate types (natp x) and (stringp x) make the
;; generated guard false, proving guard verification for an unsound :exec (car x)!
(definec bad-mbe (x :nat y :nat x :string) :nat
  (mbe :logic (+ x y) :exec (car x)))

(value-triple (list :BAD-MBE-CLASS (acl2::symbol-class 'bad-mbe (w state))))
(value-triple :ACL2S-REPRO-2-VERIFIED)
