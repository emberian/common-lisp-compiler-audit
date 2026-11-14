#!/usr/bin/env python3
"""
Fuzzer for defchoose, defun-sk, :functional-instance, apply$/loop$/defwarrant,
defevaluator, stobjs, mv, :program-mode functions, and proved-functional-instances-alist.
"""
import random
import subprocess

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "45s"]


def run_acl2(script_text):
    p = subprocess.run(
        TIMEOUT_CMD + [ACL2_SBCL],
        input=script_text,
        text=True,
        capture_output=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


def build_targeted_tests():
    """Targeted structural edge cases + randomized :functional-instance / defun-sk / defchoose probes."""
    cases = []

    # Case 1: defun-sk with custom :rewrite, :strengthen t, multi-bound-vars, non-exec, stobj, dfs
    cases.append(("defun-sk-stobj-fi", """(in-package "ACL2")
(defstobj st (fld :type integer :initially 0))
(defun-sk sk-st (st x)
  (declare (xargs :stobjs st :verify-guards nil))
  (exists w (equal (fld st) (+ w (nfix x)))))
; Now instantiate sk-st or sk-st-witness via :functional-instance!
(defthm sk-st-trivial (equal (sk-st st x) (sk-st st x)) :rule-classes nil)
(defun dummy-2 (a b) (declare (ignore a b)) 0)
(make-event
 (mv-let (erp val state)
   (defthm try-fi-sk-st
     (equal (car (cons u v)) u)
     :hints (("Goal" :use ((:instance (:functional-instance sk-st-trivial (sk-st dummy-2) (sk-st-witness dummy-2)) (st 0) (x 1)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
"""))

    # Case 2: proved-functional-instances-alist across local / non-local / encapsulate / capture renaming
    cases.append(("proved-fi-alist-encap", """(in-package "ACL2")
(encapsulate
  (((f1 *) => *) ((f2 *) => *))
  (local (defun f1 (x) x))
  (local (defun f2 (x) x))
  (defthm f1-f2 (equal (f1 x) (f2 x)) :rule-classes nil))
(defun g1 (x) (declare (ignore x)) 1)
(defun g2 (x) (declare (ignore x)) 2)
(encapsulate ()
  (local (defaxiom g1-eq-g2 (equal (g1 x) (g2 x))))
  (defthm inside-encap
    (equal (car (cons a b)) a)
    :hints (("Goal" :use ((:functional-instance f1-f2 (f1 g1) (f2 g2)))))
    :rule-classes nil))
; Now outside encapsulate, try using (:functional-instance f1-f2 (f1 g1) (f2 g2)) again!
; Does proved-functional-instances-alist leak the local proof?
(make-event
 (mv-let (erp val state)
   (defthm outside-nil
     nil
     :hints (("Goal" :use ((:instance (:functional-instance f1-f2 (f1 g1) (f2 g2)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 3: proved-functional-instances-alist with local defun vs non-local theorem
    cases.append(("proved-fi-alist-local-fn", """(in-package "ACL2")
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-pos (natp (ef x)) :rule-classes nil))
(encapsulate ()
  (local (defun h (x) (declare (ignore x)) 0))
  (local (defthm use-h (equal (car (cons a b)) a)
           :hints (("Goal" :use ((:functional-instance ef-pos (ef h)))))
           :rule-classes nil)))
(defun h (x) (declare (ignore x)) -1)
(make-event
 (mv-let (erp val state)
   (defthm test-h-reuse
     nil
     :hints (("Goal" :use ((:instance (:functional-instance ef-pos (ef h)) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 4: defchoose with :strengthen t + functional-instance
    cases.append(("defchoose-strengthen-fi", """(in-package "ACL2")
(defun rel (w x) (and (natp w) (equal (* 2 w) (nfix x))))
(defchoose ch (w) (x) (rel w x) :strengthen t)
(defthm ch-prop
  (implies (rel w x) (rel (ch x) x))
  :hints (("Goal" :use ch))
  :rule-classes nil)
; Instantiate rel with a DIFFERENT relation where ch is instantiated by a lambda!
(make-event
 (mv-let (erp val state)
   (defthm bad-ch-fi
     nil
     :hints (("Goal" :use ((:instance (:functional-instance ch-prop
                                        (rel (lambda (w x) (equal w x)))
                                        (ch (lambda (x) 0)))
                                      (w 1) (x 1)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 5: defwarrant / apply$ / badge-userfn / apply$-userfn in :functional-instance
    cases.append(("apply-warrant-fi", """(in-package "ACL2")
(defun my-id (x) x)
(defwarrant my-id)
(defthm warrant-thm
  (implies (apply$-warrant-my-id)
           (equal (apply$ 'my-id (list x)) x))
  :rule-classes nil)
(defun evil-fn (x) (declare (ignore x)) 999)
; Can we functionally instantiate my-id or apply$-warrant-my-id-witness or apply$-userfn?
(make-event
 (mv-let (erp val state)
   (defthm test-warrant-fi
     nil
     :hints (("Goal" :use ((:instance (:functional-instance warrant-thm
                                        (my-id evil-fn))
                                      (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
(make-event
 (mv-let (erp val state)
   (defthm test-warrant-witness-fi
     nil
     :hints (("Goal" :use ((:instance (:functional-instance warrant-thm
                                        (apply$-warrant-my-id-witness (lambda () (list 0)))
                                        (apply$-warrant-my-id (lambda () t))
                                        (my-id evil-fn))
                                      (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 6: defevaluator in :functional-instance
    cases.append(("defevaluator-fi", """(in-package "ACL2")
(defevaluator my-ev my-ev-lst ((cons a b) (car x)))
(defthm my-ev-cons
  (equal (my-ev (list 'cons a b) env)
         (cons (my-ev a env) (my-ev b env)))
  :rule-classes nil)
(defun fake-ev (x env) (declare (ignore x env)) 0)
(defun fake-ev-lst (xs env) (declare (ignore xs env)) nil)
(make-event
 (mv-let (erp val state)
   (defthm test-ev-fi
     nil
     :hints (("Goal" :use ((:instance (:functional-instance my-ev-cons
                                        (my-ev fake-ev)
                                        (my-ev-lst fake-ev-lst))
                                      (a '1) (b '2) (env nil)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 7: :program mode fn2 in :functional-instance with executable-counterpart / rewriting
    cases.append(("prog-fn-fi-exec", """(in-package "ACL2")
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) (ef x)) :rule-classes nil))
(defun prog-boom (x)
  (declare (xargs :mode :program))
  (+ 1 x))
(defthm hit-prog
  (equal (car (cons a b)) a)
  :hints (("Goal" :use ((:instance (:functional-instance ef-id (ef prog-boom)) (x 0)))))
  :rule-classes nil)
"""))

    # Case 8: :functional-instance with stobj-taking or mv-returning fn2 where constraint uses fn2 in expression
    cases.append(("stobj-mv-expr-fi", """(in-package "ACL2")
(defstobj myst (fld :type integer :initially 0))
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-zero-ok (implies (equal (ef x) 0) (equal (ef x) 0)) :rule-classes nil))
(defun st-fn (myst)
  (declare (xargs :stobjs myst))
  (fld myst))
(defun mv-fn (x)
  (mv x (+ 1 x)))
; Also try instantiating with a function returning (mv * *) inside a rewrite / mbe / stobj!
(defthm test-mv-in-expr
  (equal (car (cons a b)) a)
  :hints (("Goal" :use ((:instance (:functional-instance ef-zero-ok (ef mv-fn)) (x 0)))))
  :rule-classes nil)
(defthm test-st-in-expr
  (equal (car (cons a b)) a)
  :hints (("Goal" :use ((:instance (:functional-instance ef-zero-ok (ef st-fn)) (x 0)))))
  :rule-classes nil)
"""))

    # Case 9: :functional-instance with lambda capture in defchoose / multi-formal / shadowing
    cases.append(("capture-defchoose-nested-fi", """(in-package "ACL2")
(defun r (a b a-renamed0) (and (natp a) (equal a (+ b a-renamed0))))
(defchoose ch (a) (b a-renamed0) (r a b a-renamed0))
(defthm ch-ok (implies (r a b a-renamed0) (r (ch b a-renamed0) b a-renamed0))
  :hints (("Goal" :use ch)) :rule-classes nil)
(make-event
 (mv-let (erp val state)
   (defthm test-cap
     nil
     :hints (("Goal" :use ((:instance (:functional-instance ch-ok
                                        (r (lambda (p q z) (if (equal p q) t (equal z freevar))))
                                        (ch (lambda (x y) (declare (ignore x y)) 0)))
                                      (a 0) (b 1) (a-renamed0 2) (freevar 9)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    # Case 10: defun-sk with :constrain t and :functional-instance
    cases.append(("defun-sk-constrain-fi", """(in-package "ACL2")
(defun p (x y) (equal x y))
(defun-sk all-p (x)
  (forall y (p x y))
  :constrain t
  :rewrite :direct)
(make-event
 (mv-let (erp val state)
   (defthm test-sk-constrain-fi
     nil
     :hints (("Goal" :use ((:instance (:functional-instance all-p-necc
                                        (p (lambda (a b) (declare (ignore a b)) nil))
                                        (all-p (lambda (x) (declare (ignore x)) t))
                                        (all-p-witness (lambda (x) x)))
                                      (x 0) (y 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected-ok :BUG-PROVED-NIL)))))
"""))

    return cases


def main():
    for name, script in build_targeted_tests():
        rc, out = run_acl2(script)
        interesting = any(
            k in out
            for k in (
                "BUG-PROVED-NIL",
                "HARD ACL2 ERROR",
                "Implementation error",
                "Unhandled",
                "Raw Lisp",
            )
        ) or rc != 0
        print(f"[{name}] rc={rc} interesting={interesting}")
        if interesting:
            for line in out.splitlines():
                if any(k in line for k in ("BUG", "HARD", "Implementation", "Error", "FAILED", "NIL")):
                    print("  ", line)


if __name__ == "__main__":
    main()
