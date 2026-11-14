#!/usr/bin/env python3
import os, shutil, subprocess, tempfile

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]

def run_acl2(cwd, script_text):
    p = subprocess.run(TIMEOUT_CMD + [ACL2_SBCL], cwd=cwd, input=script_text, text=True, capture_output=True)
    return p.returncode, p.stdout + "\n" + p.stderr

tmp = tempfile.mkdtemp(prefix="acl2_elide2_")
try:
    for name, form in [
        ("wo-direct", "(with-output :off :all (defconst *c* '42))"),
        ("wo-me", "(make-event '(with-output :off :all (defconst *c* '42)))"),
        ("sl-me", "(make-event '(with-prover-step-limit 1000 (defconst *c* '42)))"),
        ("wg-me", "(make-event '(with-guard-checking-event nil (defconst *c* '42)))"),
        ("wo-progn-me", "(make-event '(with-output :off :all (progn (defconst *c* '42))))"),
        ("big-wo-me", "(make-event '(with-output :off :all (defconst *c* '(1 2 3 4 5))))"),
    ]:
        d = os.path.join(tmp, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "b.lisp"), "w") as f:
            f.write(f'(in-package "ACL2")\n{form}\n(defthm c-ok (equal *c* *c*) :rule-classes nil)\n')
        rc1, out1 = run_acl2(d, '(certify-book "b" 0 t)\n')
        cert_ok = os.path.exists(os.path.join(d, "b.cert"))
        rc2, out2 = run_acl2(d, '(include-book "b")\n(value-triple (list :c *c*))\n')
        print(f"[{name}] cert_ok={cert_ok} rc1={rc1} rc2={rc2}")
        if not cert_ok or "Error" in out2 or "FAILED" in out2:
            print("  CERT:", "\n  ".join(out1.strip().splitlines()[-8:]))
            print("  INC :", "\n  ".join(out2.strip().splitlines()[-12:]))
        else:
            print("  INC VAL:", [l for l in out2.splitlines() if ":C" in l])
finally:
    shutil.rmtree(tmp, ignore_errors=True)
