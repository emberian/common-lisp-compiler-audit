(defpkg "SHELLPOOL" nil)
(defttag :w4-shellpool)
(progn!
 (set-raw-mode t)
 (cl:eval (cl:read-from-string "
   (cl:progn
     (cl:export '(shellpool::start shellpool::ensure shellpool::run shellpool::run&) \"SHELLPOOL\")
     (cl:defun shellpool::start (cl:&optional n) (cl:declare (cl:ignore n)) cl:nil)
     (cl:defun shellpool::ensure (cl:&optional n) (cl:declare (cl:ignore n)) cl:nil)
     (cl:defun shellpool::run& (cmd) (cl:declare (cl:ignore cmd)) cl:nil)
     (cl:defun shellpool::run (cmd cl:&key each-line) (cl:declare (cl:ignore cmd each-line)) 0))")))
(defttag nil)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(ld "std/portcullis.acl2" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(ld "oslib/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/satlink/portcullis.acl2" :dir :system)
(ld "centaur/ipasir/portcullis.acl2" :dir :system)
(include-book "centaur/satlink/dimacs-lits" :dir :system :uncertified-okp t)
(include-book "centaur/satlink/cnf" :dir :system :uncertified-okp t)
(include-book "centaur/satlink/dimacs" :dir :system :uncertified-okp t)
(include-book "centaur/ipasir/ipasir-logic" :dir :system :uncertified-okp t)

;; 1. (make-lit 2147483647 1) is a valid satlink::litp, maps to Dimacs -2147483648 (INT32_MIN),
;;    whose negation +2147483648 overflows signed int32_t (UB in C ipasir_val / ipasir-interface-raw.lsp:375).
(value-triple
 (list :LIT-NEG-LITP (satlink::litp (satlink::make-lit 2147483647 1))
       :DIMACS-NEG (satlink::satlink-to-dimacs-lit (satlink::make-lit 2147483647 1))
       :DIMACS-NEG-S32 (signed-byte-p 32 (satlink::satlink-to-dimacs-lit (satlink::make-lit 2147483647 1)))
       :NEGATED-OVERFLOWS-S32 (not (signed-byte-p 32 (- (satlink::satlink-to-dimacs-lit (satlink::make-lit 2147483647 1)))))))

;; 2. (make-lit 2147483647 0) maps to +2147483648, which is NOT (signed-byte-p 32 ...) at all!
(value-triple
 (list :DIMACS-POS (satlink::satlink-to-dimacs-lit (satlink::make-lit 2147483647 0))
       :DIMACS-POS-S32 (signed-byte-p 32 (satlink::satlink-to-dimacs-lit (satlink::make-lit 2147483647 0)))))

;; 3. ipasir-add-lit$a / ipasir-assume$a accept >= 2^32 literals without 32-bit guard
(defun w4-ipasir-test (state)
  (declare (xargs :mode :program :stobjs state))
  (b* (((mv s state) (ipasir::ipasir-init$a nil state))
       (s (ipasir::ipasir-add-lit$a s 4294967295))
       (s (ipasir::ipasir-assume$a s (satlink::make-lit (expt 2 40) 0))))
    (mv (list :ADD-INTMIN-STATUS (consp s)) state)))
(mv-let (res state) (w4-ipasir-test state)
  (declare (ignore state))
  res)
