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
(include-book "acl2s/match" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defunc" :dir :system :ttags :all :uncertified-okp t)
(in-package "ACL2S")

;; 1. Silent :logic-mode outer-variable capture in !a (match.lisp:195-204,255):
;;    '(1 . 42) has car=1, cdr=42; pattern (a . !a) should fail, but !a checks outer a=42!
(defun match-bang-capture (x a)
  (declare (xargs :guard t))
  (match x
    ((a . !a) (list a))
    (& nil)))

(defthm match-bang-capture-miscompiled
  (equal (match-bang-capture '(1 . 42) 42) '(1)))

(value-triple (list :MATCH-BANG-CAPTURE (match-bang-capture '(1 . 42) 42)))

;; 2. Bare ! pattern slices empty symbol name "" -> unbound || (match.lisp:199)
(value-triple (list :BARE-BANG-EXPANSION (macroexpand1 '(match x (! 'ok) (& 'bad)) 'w4)))

;; 3. Unguarded defmacro match -> (safety 0) match-fun crash on malformed clause (1 . 2) (match.lisp:306-317)
(defunc match-malformed-crash (x)
  :input-contract (natp x)
  :output-contract (natp (match-malformed-crash x))
  (match x (1 . 2)))
