#!/usr/bin/env python3
"""
Expanded Fuzzer (v2) for Hint / Debugging / Parallel / Oracle Boundaries:
- `override-hints`, `custom-keyword-hints`, `backtrack` hints, `computed-hints`
- `brr` + `wormhole-eval` + `brr@` + rewrite loops
- `spec-mv-let`, `plet`, `pargs`, `pand`, `por`
- `with-prover-step-limit` (`:start`, nested `encapsulate`), `with-prover-time-limit`
- `fms`, `fmt-to-comment-window`, `sys-call+`, `read-acl2-oracle`
"""
import subprocess

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]


def run_acl2(script_text):
    p = subprocess.run(
        TIMEOUT_CMD + [ACL2_SBCL],
        input=script_text,
        text=True,
        capture_output=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


CASES = {
    "override-hints-custom-kw-backtrack": """
(in-package "ACL2")
(defun my-kw-hint-fn (val) (declare (xargs :mode :program)) (list :no-thanks t))
(add-custom-keyword-hint :my-kw (my-kw-hint-fn val))
(add-override-hints! '((list* :backtrack '(progn (value-triple :bt) nil) keyword-alist)))
(thm (equal (car (cons x y)) x)
     :hints (("Goal" :my-kw 1)))
""",
    "computed-hint-state-world-mutation": """
(in-package "ACL2")
;; Try mutating touchable globals or world inside computed hint via xtrans-eval
(thm (equal x x)
     :hints ((let ((g (f-get-global 'in-prove-flg state)))
               (declare (ignore g))
               (pprogn (f-put-global 'default-backtrack-hint '(:no-thanks t) state)
                       (value nil)))))
(value-triple (list :bt-hint (@ default-backtrack-hint)))
""",
    "brr-wormhole-loop": """
(in-package "ACL2")
(defun loopf (x) x)
(defthm loop-rw (equal (loopf x) (loopf (car (cons x x)))))
(brr t)
(wormhole-eval 'brr '(lambda (whs) (declare (ignore whs)) nil) nil)
(make-event
 (mv-let (erp val state)
   (with-prover-step-limit 200
     (thm (equal (loopf x) x)))
   (declare (ignore val))
   (value `(value-triple ',(if erp :step-limited :proved)))))
""",
    "parallel-spec-mv-let-plet-pand-por": """
(in-package "ACL2")
(defun ptest (x y)
  (declare (xargs :guard (and (natp x) (natp y))))
  (spec-mv-let
   (a b) (mv (+ x 1) (+ y 1))
   (if (pand (integerp a) (por (equal b 1) (> b 1)))
       (plet ((u (+ a 2)) (v (+ b 3)))
         (pargs (mv (+ u v) (- u v))))
       (mv 0 0))))
(thm (equal (mv-nth 0 (ptest 1 2)) 10))
(verify-guards ptest)
""",
    "step-limit-nested-encap-start": """
(in-package "ACL2")
(with-prover-step-limit 50
  (encapsulate ()
    (defthm t1 (equal (car (cons x y)) x))
    (with-prover-step-limit :start
      (defthm t2 (equal (cdr (cons x y)) y)))))
""",
    "time-limit-fractional-rational": """
(in-package "ACL2")
(with-prover-time-limit 1/10000
  (thm (equal (append (append x y) z) (append x (append y z)))))
""",
    "fms-unbound-fmt-var": """
(in-package "ACL2")
(fms "~y1" nil *standard-co* state nil)
""",
    "fmt-to-comment-window-unbound": """
(in-package "ACL2")
(fmt-to-comment-window "~x0 ~y1" '((#\0 . 42)) 0 nil nil)
""",
    "oracle-and-syscall-guard": """
(in-package "ACL2")
(defun try-oracle (state)
  (declare (xargs :stobjs state))
  (mv-let (erp val state)
    (read-acl2-oracle state)
    (mv erp val state)))
(defun try-syscall (state)
  (declare (xargs :stobjs state))
  (sys-call+ "echo" '("hi") state))
(thm (implies (state-p state)
              (equal (mv-nth 0 (try-oracle state))
                     (mv-nth 0 (read-acl2-oracle state)))))
""",
}


def main():
    for name, script in CASES.items():
        rc, out = run_acl2(script)
        interesting = (
            rc != 0
            or "HARD ACL2 ERROR" in out
            or "INTERNAL-ERROR" in out
            or "debugger invoked" in out
            or "Unhandled" in out
            or ("bt-hint" in out.lower() and ":NO-THANKS" in out)
        )
        print(f"[{name}] rc={rc} interesting={interesting}")
        if interesting or "FAILED" in out or "Error" in out:
            print("  " + "\n  ".join(out.strip().splitlines()[-12:]))


if __name__ == "__main__":
    main()
