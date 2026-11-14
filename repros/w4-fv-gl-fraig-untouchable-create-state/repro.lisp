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
(ld "centaur/vl/portcullis.acl2" :dir :system)
(ld "centaur/aignet/portcullis.acl2" :dir :system)
(ld "centaur/satlink/portcullis.acl2" :dir :system)
(defpkg "LRAT" *acl2-exports*)
(ld "centaur/aig/portcullis.acl2" :dir :system)
(ld "centaur/gl/portcullis.acl2" :dir :system)

;; books/centaur/gl/bfr-fraig-satlink.lisp:41-42 executes non-local
;; (defttag aig-fraig->cnf) (remove-untouchable acl2::create-state t)
;; leaving create-state unlocked even after (defttag nil).
(defttag aig-fraig->cnf)
(remove-untouchable acl2::create-state t)
(defttag nil)

(encapsulate ()
  (local
   (defun w4-read-state-global ()
     (declare (xargs :verify-guards nil))
     (acl2::with-local-state
       (mv-let (v state)
         (mv (if (acl2::boundp-global 'w4-test-var state)
                 (acl2::f-get-global 'w4-test-var state)
               nil)
             state)
         v))))
  (local (make-event (er-progn (acl2::assign w4-test-var 1) (acl2::value '(value-triple :s1)))))
  (local
   (defthm w4-state-eq-1
     (equal (w4-read-state-global) 1)
     :hints (("Goal" :in-theory (acl2::executable-counterpart-theory :here)))
     :rule-classes nil))
  (local (make-event (er-progn (acl2::assign w4-test-var 2) (acl2::value '(value-triple :s2)))))
  (local
   (defthm w4-state-eq-2
     (equal (w4-read-state-global) 2)
     :hints (("Goal" :in-theory (acl2::executable-counterpart-theory :here)))
     :rule-classes nil))
  (local
   (defthm w4-fraig-create-state-contradiction
     nil
     :hints (("Goal" :use (w4-state-eq-1 w4-state-eq-2)))
     :rule-classes nil))
  (defconst *w4-gl-fraig-proved-nil* t))

(value-triple (list :GL-FRAIG-CREATE-STATE-NIL (acl2::logical-namep '*w4-gl-fraig-proved-nil* (w state))))
