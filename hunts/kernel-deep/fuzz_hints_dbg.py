#!/usr/bin/env python3
"""
Fuzzer for Hints / Debugging / Parallel / Oracle boundaries:
- override-hints, custom-keyword-hints, computed-hints (:computed-hint-replacement, world/state mutation)
- backtrack hints, :by / :use / :cases / :or
- wormhole-eval, brr, fms / fmt-to-comment-window
- with-prover-step-limit, with-prover-time-limit
- spec-mv-let, plet / pargs / pand / por
- read-acl2-oracle, sys-call+
"""
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


TESTS = [
    ("computed-hint-state-world-mutate", """(in-package "ACL2")
; Try mutating state globals, ld-skip-proofsp, ttag, or w state inside a computed hint or override-hint!
(make-event
 (mv-let (erp val state)
   (defthm try-hint-mutate
     nil
     :hints ((pprogn
              (f-put-global 'ld-skip-proofsp t state)
              (value '(:use ((:theorem t))))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(list :erp erp :skip (f-get-global 'ld-skip-proofsp state))))))

; Also test override-hints mutating state / returning malformed keyword-alist / custom keyword hint!
(add-override-hints '((pprogn (f-put-global 'ld-skip-proofsp t state) (value '(:no-op t)))))
(make-event
 (mv-let (erp val state)
   (defthm try-override-mutate
     nil
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(list :override-erp erp :skip (f-get-global 'ld-skip-proofsp state))))))
"""),

    ("custom-keyword-hint-edge", """(in-package "ACL2")
(add-custom-keyword-hint :my-hint
                         (value (list :computed-hint-replacement t :use val))
                         :checker (value t))
(make-event
 (mv-let (erp val state)
   (defthm test-ckh
     (equal (car (cons x y)) x)
     :hints (("Goal" :my-hint car-cons))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
"""),

    ("computed-hint-chr-malformed", """(in-package "ACL2")
; Test weird :computed-hint-replacement values and :error hints + override-hints
(add-override-hints '((cond ((assoc-keyword :no-op keyword-alist) (value keyword-alist))
                            (t (value (list* :no-op t keyword-alist))))))
(make-event
 (mv-let (erp val state)
   (defthm test-chr-1
     (equal (car (cons x y)) x)
     :hints ((value '(:computed-hint-replacement (123) :in-theory nil)))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
(make-event
 (mv-let (erp val state)
   (defthm test-chr-2
     (equal (car (cons x y)) x)
     :hints ((value '(:computed-hint-replacement ((value '(:use car-cons))) :no-op t)))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
"""),

    ("wormhole-eval-and-brr", """(in-package "ACL2")
; Test wormhole-eval inside theorem / defun / verify-guards / macro
(defun wh-user (x)
  (declare (xargs :guard t))
  (prog2$ (wormhole-eval 'my-wh
                         '(lambda (whs) (declare (ignore whs)) '(:hi))
                         nil)
          x))
(defthm wh-thm (equal (wh-user x) x))
; Try weird wormhole-eval calls (non-quoted lambda, ill-formed lambda, modifying whs)
(make-event
 (mv-let (erp val state)
   (defthm wh-weird
     (equal (wormhole-eval 'my-wh '(lambda () (car 1)) nil) nil)
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
(make-event
 (mv-let (erp val state)
   (value-triple (wormhole-eval 'my-wh '(lambda (whs) whs) nil))
   (declare (ignore val))
   (value `(value-triple ',(if erp :rejected :accepted)))))
"""),

    ("spec-mv-let-and-parallel-macros", """(in-package "ACL2")
(defun sp-test (x)
  (declare (xargs :guard (natp x)))
  (spec-mv-let
   (a b)
   (mv (+ 1 x) (+ 2 x))
   (mv-let (c)
           x
           (if (< c 10) (+ a b) 0))))
(defthm sp-test-thm (natp (sp-test x)))

(defun p-test (x y)
  (declare (xargs :guard t))
  (plet ((a (pargs (cons x y)))
         (b (pand (consp x) (por (consp y) nil))))
    (cons a b)))
(defthm p-test-thm (consp (p-test x y)))
"""),

    ("step-limit-and-time-limit", """(in-package "ACL2")
(make-event
 (mv-let (erp val state)
   (with-prover-step-limit 1
     (defthm step-ok (equal (car (cons x y)) x) :rule-classes nil))
   (declare (ignore val))
   (value `(value-triple ',(list :step1-erp erp)))))

(make-event
 (mv-let (erp val state)
   (with-prover-time-limit 0.001
     (defthm time-ok (equal (car (cons x y)) x) :rule-classes nil))
   (declare (ignore val))
   (value `(value-triple ',(list :time-erp erp)))))

; Try negative / weird / nested step-limit!
(make-event
 (mv-let (erp val state)
   (with-prover-step-limit 100
     (with-prover-step-limit :start
       (defthm step-nested (equal (car (cons x y)) x) :rule-classes nil)))
   (declare (ignore val))
   (value `(value-triple ',(list :nested-erp erp)))))
"""),

    ("oracle-and-sys-call", """(in-package "ACL2")
; Test read-acl2-oracle in logic / theorem / guard / encapsulate / defun
(defun oracle-fn (state)
  (declare (xargs :stobjs state))
  (mv-let (erp val state)
    (read-acl2-oracle state)
    (mv erp val state)))
(defthm oracle-thm
  (implies (state-p state)
           (state-p (mv-nth 2 (oracle-fn state))))
  :rule-classes nil)
; Test sys-call+ with non-existent command or strange args
(make-event
 (mv-let (status out state)
   (sys-call+ "/usr/bin/true" nil state)
   (value `(value-triple ',(list :status status :out out)))))
"""),

    ("fms-fmt-to-comment-window", """(in-package "ACL2")
; Test fms / fmt-to-comment-window with malformed format strings or bad args
(make-event
 (mv-let (erp val state)
   (value-triple (fmt-to-comment-window "~x0 ~y1 ~s2" (list (cons #\\0 'ok)) 0 nil nil))
   (declare (ignore val))
   (value `(value-triple ',(list :fmt-erp erp)))))
"""),
]


def main():
    for name, script in TESTS:
        rc, out = run_acl2(script)
        interesting = any(
            k in out
            for k in (
                "HARD ACL2 ERROR",
                "Implementation error",
                "Unhandled",
                "BUG",
                ":SKIP T",
            )
        ) or rc != 0
        print(f"[{name}] rc={rc} interesting={interesting}")
        if interesting or True:
            # Print compact summary lines
            for line in out.splitlines():
                if any(k in line for k in ("HARD", "Implementation", "Error", "SKIP", "STEP1", "TIME", "NESTED", "FMT", "STATUS", "FAILED", "REJECTED", "ACCEPTED", "Unhandled")):
                    print("  ", line)


if __name__ == "__main__":
    main()
