#!/usr/bin/env python3
"""
Expanded Counterexample-Guided Falsification Fuzzer (v2) for:
- Equivalence (`defequiv`), refinement (`defrefinement`), classic & patterned `defcong` (`pequivs`)
- `:outside-inside` rewrite rules + `geneqv` propagation (`rewrite-if`, `rewrite-with-lemma`, RHS keeping `pequiv-info`)
- `:rewrite-quoted-constant` Forms [1], [2], [3] + `synp`/`bind-free` hyps
- `rewrite-lambda-object` with `mbe`/`ec-call`/`declare` and `rewrite-lambda-modep` disabled
- `double-rewrite`
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


def gen_case(seed):
    rng = random.Random(seed)
    use_refinement = rng.random() < 0.7
    use_rqc = rng.random() < 0.85
    use_outside_inside = rng.random() < 0.85
    use_lambda_obj = rng.random() < 0.7
    use_double_rw = rng.random() < 0.6

    forms = [
        '(in-package "ACL2")',
        '(defun eq2 (x y) (equal (mod (nfix x) 2) (mod (nfix y) 2)))',
        '(defequiv eq2)',
        '(defun eq4 (x y) (equal (mod (nfix x) 4) (mod (nfix y) 4)))',
        '(defequiv eq4)',
        '(defrefinement eq4 eq2)' if use_refinement else '',
        '(defun binf (x y) (if (equal x 0) (mod (nfix y) 2) (nfix y)))',
        '(defthm cong-binf-0-pat (implies (eq2 y1 y2) (equal (binf 0 y1) (binf 0 y2))) :rule-classes :congruence)',
        '(defun wrap1 (a b) (cons a b))',
        '(defthm deep-cong-1 (implies (eq2 y1 y2) (equal (binf 0 (car (wrap1 y1 z))) (binf 0 (car (wrap1 y2 z))))) :rule-classes :congruence)',
        '(defun dupf (x y z) (if (equal x y) (mod (nfix z) 2) (nfix z)))',
        '(defthm deep-cong-dup (implies (eq2 z1 z2) (equal (dupf w w z1) (dupf w w z2))) :rule-classes :congruence)',
        '(defun norm2 (x) (mod (nfix x) 2))',
        '(defcong eq2 equal (norm2 x) 1)',
        '(defun box (x) (cons x nil))',
        '(defun zero-alias (x) (if (consp x) 0 0))',
        '(defun tag2 (x) (if (integerp x) (+ x 2) x))',
        '(defthm tag2-eq2 (eq2 (tag2 x) x))',
    ]

    if use_rqc:
        forms.append("(defthm rqc-form1 (eq2 '2 '0) :rule-classes :rewrite-quoted-constant)")
        forms.append("(defthm rqc-form2 (eq2 (norm2 x) x) :rule-classes :rewrite-quoted-constant)")
        if rng.random() < 0.6:
            forms.append("(defthm rqc-form3 (implies (natp x) (eq2 x (mod x 2))) :rule-classes :rewrite-quoted-constant)")
        if rng.random() < 0.5:
            forms.append("(defthm rqc-bind-free (implies (and (bind-free '((k . '0)) (k)) (eq2 k 0) (natp x)) (eq2 x (mod x 2))) :rule-classes :rewrite-quoted-constant)")

    if use_outside_inside:
        forms.append('(defthm oi-car-box (equal (car (box x)) x) :rule-classes ((:rewrite :outside-inside t)))')
        forms.append('(defthm oi-tag2-eq2 (eq2 (car (box (tag2 x))) (car (box x))) :rule-classes ((:rewrite :outside-inside t)))')
        forms.append('(defthm oi-zero (equal (zero-alias x) 0) :rule-classes ((:rewrite :outside-inside t)))')
        forms.append('(defthm oi-if-push (equal (binf (zero-alias a) (if p (tag2 u) v)) (binf 0 (if p u v))) :rule-classes ((:rewrite :outside-inside t)))')

    if use_lambda_obj:
        forms.append('(defun$ id-fn (x) x)')
        if rng.random() < 0.5:
            forms.append('(in-theory (disable (:definition rewrite-lambda-modep)))')
        if rng.random() < 0.5:
            forms.append('(in-theory (disable (:executable-counterpart rewrite-lambda-modep)))')

    if use_double_rw:
        forms.append('(defun hid (x) x)')
        forms.append('(defthm hid-eq2 (eq2 (hid x) x))')

    forms.append('(in-theory (disable binf dupf norm2 wrap1 box tag2 zero-alias))')

    # False conjectures (all concretely falsified!)
    false_goals = [
        '(defthm bad-pat-1 (equal (binf k (tag2 y)) (binf k y)) :rule-classes nil)',
        '(defthm bad-oi-eq4 (eq4 (car (box (tag2 x))) (car (box x))) :rule-classes nil)',
        '(defthm bad-deep-1 (equal (binf 0 (cdr (wrap1 y1 (tag2 z)))) (binf 0 (cdr (wrap1 y1 z)))) :rule-classes nil)',
        '(defthm bad-dup-1 (equal (dupf u v (tag2 z)) (dupf u v z)) :rule-classes nil)',
        "(defthm bad-rqc-eq4 (eq4 '2 '0) :rule-classes nil)",
        '(defthm bad-dr-eq4 (eq4 (double-rewrite (tag2 x)) x) :rule-classes nil)',
        '(defthm bad-oi-if (equal (binf (if p (zero-alias a) 1) (tag2 y)) (binf (if p 0 1) y)) :rule-classes nil)',
        '(defthm bad-lam-eq (equal ((lambda (z) (declare (ignore z)) (tag2 y)) 1) ((lambda (z) (declare (ignore z)) y) 1)) :rule-classes nil)',
        '(defthm bad-nil nil :rule-classes nil)',
    ]
    if use_lambda_obj:
        false_goals.append("(defthm bad-lam-obj (equal (apply$ '(lambda (x) (mbe :logic (tag2 x) :exec x)) (list 0)) 0) :rule-classes nil)")

    picked = rng.sample(false_goals, k=min(6, len(false_goals)))
    for i, g in enumerate(picked):
        forms.append(f"""
(make-event
 (mv-let (erp val state)
   {g}
   (declare (ignore val))
   (value `(value-triple ',(list :goal {i} :res (if erp :failed :PROVED-FALSE))))))
""")
    return "\n".join(f for f in forms if f)


def main():
    n_runs = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    anomalies = []
    for seed in range(1, n_runs + 1):
        script = gen_case(seed)
        rc, out = run_acl2(script)
        bad_lines = []
        for line in out.splitlines():
            if ":PROVED-FALSE" in line or "HARD ACL2 ERROR" in line or "INTERNAL-ERROR" in line or "debugger invoked" in line or "Unhandled" in line:
                bad_lines.append(line.strip())
        if rc != 0 or bad_lines:
            anomalies.append((seed, rc, bad_lines, out[-800:]))
            print(f"[seed={seed}] ANOMALY rc={rc}: {bad_lines}")
    print(f"fuzz2_cong_rqc completed {n_runs} runs; anomalies={len(anomalies)}")
    if anomalies:
        for seed, rc, bad_lines, tail in anomalies[:5]:
            print(f"--- seed {seed} (rc={rc}) ---\n{tail}")


if __name__ == "__main__":
    main()
