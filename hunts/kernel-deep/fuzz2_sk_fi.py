#!/usr/bin/env python3
"""
Expanded Fuzzer (v2) for Witness Skolemization (`defchoose`, `defun-sk`),
`:functional-instance`, `apply$`/`loop$`, `defevaluator`, stobjs, multiple values,
`:non-executable`, `:program` mode, and `proved-functional-instances-alist`.
"""
import random
import subprocess
import sys

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


def run_targeted_probes():
    cases = {
        "defchoose-multi-strengthen-fi": """
(in-package "ACL2")
(defchoose ch-m (a b) (x y)
  (and (equal a x) (equal b y))
  :strengthen t)
(encapsulate
  (((ep * *) => (mv * *)))
  (local (defun ep (x y) (mv x y)))
  (defthm ep-ok (implies (equal u x) (mv-let (a b) (ep u y) (and (equal a u) (equal b y))))))
;; Try instantiating ep with ch-m? Note ch-m returns mv of 2!
(defthm test-ch-fi
  (implies (equal (ch-m x y) (mv a b))
           (equal (car (ch-m x y)) (car (mv a b))))
  :hints (("Goal" :use ((:functional-instance ep-ok (ep ch-m) (u x)))))
  :rule-classes nil)
""",
        "defun-sk-constrain-custom-rw": """
(in-package "ACL2")
(defun-sk ex-p (x)
  (exists (y) (equal (car y) x))
  :rewrite :direct
  :constrain t)
(defthm test-sk-false
  (ex-p x)
  :rule-classes nil)
""",
        "defun-sk-nx-and-fi": """
(in-package "ACL2")
(defun-sk fa-p (x)
  (forall (y) (implies (consp y) (equal (car (cons x y)) x))))
(encapsulate
  (((epred *) => *))
  (local (defun epred (x) (declare (ignore x)) t))
  (defthm epred-t (epred x) :rule-classes nil))
(defthm fa-via-fi
  (implies (consp y) (fa-p x))
  :hints (("Goal" :use ((:functional-instance epred-t (epred fa-p)))))
  :rule-classes nil)
""",
        "defevaluator-fi-apply": """
(in-package "ACL2")
(defevaluator myev myev-lst ((cons a b) (car x)))
(encapsulate
  (((ee * *) => *))
  (local (defun ee (x a) (declare (ignore x a)) nil))
  (defthm ee-prop (equal (ee x a) (ee x a)) :rule-classes nil))
(defthm test-ev-fi
  (equal (car (cons x y)) x)
  :hints (("Goal" :use ((:instance (:functional-instance ee-prop (ee myev)) (x '(cons '1 '2)) (a nil)))))
  :rule-classes nil)
""",
        "proved-fi-alist-encap-local": """
(in-package "ACL2")
(encapsulate
  (((ef1 *) => *))
  (local (defun ef1 (x) x))
  (defthm ef1-id (equal (ef1 x) x) :rule-classes nil))
(defun id1 (x) x)
;; Prove functional instance locally inside encapsulate, then see if constraint leaks outside!
(encapsulate ()
  (local (defthm local-fi
           (equal (id1 x) x)
           :hints (("Goal" :use ((:functional-instance ef1-id (ef1 id1)))))
           :rule-classes nil)))
;; Now try with a DIFFERENT function that fails the constraint (not1 x) != x,
;; or check if proved-functional-instances-alist leaked!
(defun not1 (x) (not x))
(defthm test-not-leaked
  nil
  :hints (("Goal" :use ((:functional-instance ef1-id (ef1 not1)))))
  :rule-classes nil)
""",
        "prog-fn-fi-exec-crash": """
(in-package "ACL2")
(encapsulate
  (((efp *) => *))
  (local (defun efp (x) x))
  (defthm efp-id (equal (efp x) (efp x)) :rule-classes nil))
(defun prog-id (x) (declare (xargs :mode :program)) x)
(defthm test-prog-fi
  (equal (car (cons a b)) a)
  :hints (("Goal" :use ((:instance (:functional-instance efp-id (efp prog-id)) (x 0)))))
  :rule-classes nil)
""",
        "prog-fn-fi-noprep-eval": """
(in-package "ACL2")
(encapsulate
  (((efp2 *) => *))
  (local (defun efp2 (x) (integerp x)))
  (defthm efp2-prop (implies (integerp (efp2 x)) (equal (efp2 x) (efp2 x))) :rule-classes nil))
(defun prog-crash (x)
  (declare (xargs :mode :program))
  (car (cons x (car 1))))
(defthm test-prog-noprep
  (equal (car (cons a b)) a)
  :hints (("Goal"
           :do-not '(preprocess)
           :use ((:instance (:functional-instance efp2-prop (efp2 prog-crash)) (x 0)))))
  :rule-classes nil)
""",
        "apply-warrant-fi": """
(in-package "ACL2")
(defun$ sq (x) (* x x))
(encapsulate
  (((ew *) => *))
  (local (defun ew (x) x))
  (defthm ew-prop (implies (natp x) (natp (ew x))) :rule-classes nil))
(defthm test-apply-fi
  (implies (natp x) (natp (apply$ 'sq (list x))))
  :hints (("Goal" :use ((:functional-instance ew-prop (ew (lambda (z) (apply$ 'sq (list z))))))))
  :rule-classes nil)
""",
    }
    results = []
    for name, body in cases.items():
        rc, out = run_acl2(body)
        interesting = (
            rc != 0
            or "HARD ACL2 ERROR" in out
            or "INTERNAL-ERROR" in out
            or "debugger invoked" in out
            or ("TEST-NOT-LEAKED" in out and "Proof succeeded" in out)
            or ("TEST-SK-FALSE" in out and "Proof succeeded" in out)
        )
        results.append((name, rc, interesting, out[-500:]))
    return results


def run_random_fi_fuzz(n_runs=25):
    anomalies = []
    for seed in range(1, n_runs + 1):
        rng = random.Random(seed)
        # Random combinations of defchoose/defun-sk/stobj/mv/prog/nx in functional-instance
        use_prog = rng.random() < 0.25
        use_nx = rng.random() < 0.4
        use_noprep = rng.random() < 0.5
        target_fn = "prog-f" if use_prog else ("nx-f" if use_nx else "bad-f")
        script = f"""
(in-package "ACL2")
(defchoose ch (w) (x) (equal (car w) x))
(defun-sk sk (x) (exists (y) (equal (car y) (ch x))))
(encapsulate
  (((ef *) => *))
  (local (defun ef (x) (declare (ignore x)) nil))
  (defthm ef-false-if-nil (equal (ef x) (ch x)) :rule-classes nil))
(defun bad-f (x) (cons x x))
(defun-nx nx-f (x) (cons x x))
(defun prog-f (x) (declare (xargs :mode :program)) (cons x x))
(make-event
 (mv-let (erp val state)
   (defthm fuzz-false-goal
     nil
     :hints (("Goal"
              {" :do-not '(preprocess)" if use_noprep else ""}
              :use ((:instance (:functional-instance ef-false-if-nil (ef {target_fn})) (x 0)))))
     :rule-classes nil)
   (declare (ignore val))
   (value `(value-triple ',(if erp :failed :PROVED-NIL)))))
"""
        rc, out = run_acl2(script)
        if rc != 0 or ":PROVED-NIL" in out or ("HARD ACL2 ERROR" in out and not use_prog):
            anomalies.append((seed, target_fn, use_noprep, rc, out[-400:]))
    return anomalies


def main():
    print("=== Targeted Skolem / FI Probes ===")
    for name, rc, interesting, tail in run_targeted_probes():
        print(f"[{name}] rc={rc} interesting={interesting}")
        if interesting:
            print(tail)
    print("\n=== Random FI Fuzz (25 runs) ===")
    anoms = run_random_fi_fuzz(25)
    print(f"anomalies={len(anoms)}")
    for a in anoms[:5]:
        print(a)


if __name__ == "__main__":
    main()
