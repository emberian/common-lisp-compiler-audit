#!/usr/bin/env python3
"""
Counterexample-guided falsification fuzzer for ACL2 Equivalence / Refinement /
Classic + Patterned Congruence (`pequiv`) / `geneqv` / `:rewrite-quoted-constant`
(Forms 1, 2, 3) / `rewrite-lambda-object` / `double-rewrite`.
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


def gen_case(seed):
    rng = random.Random(seed)
    use_rqc = rng.random() < 0.75
    use_lambda_obj = rng.random() < 0.45
    use_double_rw = rng.random() < 0.4
    use_refinement = rng.random() < 0.6

    # Concretely false goals relative to our model:
    # eq2(x, y) := mod(nfix(x), 2) == mod(nfix(y), 2)
    # eq4(x, y) := mod(nfix(x), 4) == mod(nfix(y), 4)
    # binf(x, y) := if equal(x, 0) then mod(nfix(y), 2) else nfix(y)
    # dupf(x, y, z) := if equal(x, y) then mod(nfix(z), 2) else nfix(z)
    # wrap1(a, b) := cons(a, b)
    # norm2(x) := mod(nfix(x), 2)
    forms = [
        '(in-package "ACL2")',
        '(defun eq2 (x y) (equal (mod (nfix x) 2) (mod (nfix y) 2)))',
        '(defequiv eq2)',
        '(defun eq4 (x y) (equal (mod (nfix x) 4) (mod (nfix y) 4)))',
        '(defequiv eq4)',
        '(defrefinement eq4 eq2)' if use_refinement else '',
        '(defun binf (x y) (if (equal x 0) (mod (nfix y) 2) (nfix y)))',
        # Shallow patterned congruence: only when 1st arg is literally '0!
        '(defthm cong-binf-0-pat (implies (eq2 y1 y2) (equal (binf 0 y1) (binf 0 y2))) :rule-classes :congruence)',
        '(defun wrap1 (a b) (cons a b))',
        # Deep patterned congruence:
        '(defthm deep-cong-1 (implies (eq2 y1 y2) (equal (binf 0 (car (wrap1 y1 z))) (binf 0 (car (wrap1 y2 z))))) :rule-classes :congruence)',
        # Duplicate var patterned congruence:
        '(defun dupf (x y z) (if (equal x y) (mod (nfix z) 2) (nfix z)))',
        '(defthm deep-cong-dup (implies (eq2 z1 z2) (equal (dupf w w z1) (dupf w w z2))) :rule-classes :congruence)',
        # Quoted constants for RQC Form 1, 2, 3
        '(defthm rqc-form1 (eq2 \'2 \'0) :rule-classes :rewrite-quoted-constant)' if use_rqc else '',
        '(defun norm2 (x) (mod (nfix x) 2))',
        '(defthm rqc-form2 (eq2 (norm2 x) x) :rule-classes :rewrite-quoted-constant)' if use_rqc else '',
        '(defthm rqc-form3 (implies (natp x) (eq2 x (mod x 2))) :rule-classes :rewrite-quoted-constant)' if use_rqc and rng.random() < 0.5 else '',
        # Classic cong on norm2: eq2 -> equal
        '(defcong eq2 equal (norm2 x) 1)',
        # Rewrite rules that can interact with pequiv-info on RHS / IF / double-rewrite
        '(defun zero-alias (x) (if (consp x) 0 0))',
        '(defun flip-if (p a b) (if p a b))',
        '(defthm rw-zero (equal (zero-alias x) 0))',
        '(defun id-fn (x) x)',
        '(defwarrant id-fn)' if use_lambda_obj else '',
    ]
    if use_lambda_obj:
        mode = rng.choice([
            '',
            '(in-theory (disable (:definition rewrite-lambda-modep)))',
            '(in-theory (disable (:executable-counterpart rewrite-lambda-modep)))',
        ])
        forms.append(mode)

    forms.append('(in-theory (disable binf dupf norm2 wrap1 zero-alias flip-if))')

    # False conjectures (verified false at concrete witnesses like k=1, a=1, b=2, p=t):
    false_goals = [
        # (binf 1 2) = 2 != 0 = (binf 1 0)
        '(defthm should-fail-1 (equal (binf k 2) (binf k 0)) :rule-classes nil)',
        # (dupf 1 2 2) = 2 != 0 = (dupf 1 2 0)
        '(defthm should-fail-2 (equal (dupf a b 2) (dupf a b 0)) :rule-classes nil)',
        # (binf 1 '2) = 2 != 0 = (binf 1 '0)
        '(defthm should-fail-3 (equal (binf 1 \'2) (binf 1 \'0)) :rule-classes nil)',
        # (if t (binf 1 2) ...) = 2 != 0
        '(defthm should-fail-4 (equal (if p (binf 1 2) (binf 0 2)) (if p (binf 1 0) (binf 0 0))) :rule-classes nil)',
        # (binf (if t 0 1) 2) vs (binf (if t 0 1) 0) -> when p=nil, (binf 1 2)=2 != 0!
        '(defthm should-fail-5 (equal (binf (if p 0 1) 2) (binf (if p 0 1) 0)) :rule-classes nil)',
        # (dupf 1 2 (double-rewrite '2)) vs (dupf 1 2 '0)
        '(defthm should-fail-6 (equal (dupf a b (double-rewrite \'2)) (dupf a b \'0)) :rule-classes nil)' if use_double_rw else '',
        # (binf 1 (car (wrap1 '2 z))) vs (binf 1 (car (wrap1 '0 z)))
        '(defthm should-fail-7 (equal (binf 1 (car (wrap1 \'2 z))) (binf 1 (car (wrap1 \'0 z)))) :rule-classes nil)',
        # What if zero-alias rewrites to 0 on LHS/RHS? (binf (zero-alias u) 2) IS equal to (binf (zero-alias u) 0) when rw-zero is enabled,
        # whereas (binf (if p (zero-alias u) 1) 2) != (binf (if p (zero-alias u) 1) 0) at p=nil!
        '(defthm should-fail-8 (equal (binf (if p (zero-alias u) 1) \'2) (binf (if p (zero-alias u) 1) \'0)) :rule-classes nil)',
        # Direct NIL
        '(defthm nil-proved nil :rule-classes nil)',
    ]

    # Also test random congruence chains & custom lambda RQC/rewrites
    body = "\n".join(x for x in forms if x) + "\n"
    for fg in false_goals:
        if not fg:
            continue
        m_name = fg.split()[1]
        body += (
            f"(make-event (mv-let (erp val state) {fg} (declare (ignore val)) "
            f"(value `(value-triple ',(if erp :ok-rejected :BUG-ACCEPTED-{m_name})))))\n"
        )
    return body


def main():
    bugs = []
    n_runs = 15
    for seed in range(1, n_runs + 1):
        script = gen_case(seed)
        rc, out = run_acl2(script)
        if ":BUG-ACCEPTED-" in out or "HARD ACL2 ERROR" in out or "Implementation error" in out or "Unhandled" in out or rc != 0:
            print(f"[seed={seed}] ANOMALY rc={rc}")
            for line in out.splitlines():
                if any(k in line for k in ("BUG-ACCEPTED", "HARD ACL2 ERROR", "Implementation error", "Unhandled", "Error:")):
                    print("  ", line)
            bugs.append((seed, rc, out))
    print(f"Completed {n_runs} runs; anomalies={len(bugs)}")


if __name__ == "__main__":
    main()
