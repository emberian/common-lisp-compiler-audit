#!/usr/bin/env python3
import os, shutil, subprocess, tempfile

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]

def run_acl2(cwd, script_text):
    p = subprocess.run(TIMEOUT_CMD + [ACL2_SBCL], cwd=cwd, input=script_text, text=True, capture_output=True)
    return p.returncode, p.stdout + "\n" + p.stderr

tmp = tempfile.mkdtemp(prefix="acl2_elide3_")
try:
    for name, form in [
        ("wo-me-progn", "(make-event '(progn (with-output :off :all (defconst *c* '42))))"),
        ("sl-me-progn", "(make-event '(progn (with-prover-step-limit 1000 (defconst *c* '42))))"),
        ("encap-wo-me", "(make-event '(encapsulate () (with-output :off :all (defconst *c* '42))))"),
        ("encap-sl-me", "(make-event '(encapsulate () (with-prover-step-limit 1000 (defconst *c* '42))))"),
        ("wg-encap-me", "(make-event '(encapsulate () (with-guard-checking-event nil (defconst *c* '42))))"),
        ("direct-wo-p", "(with-output :off :all (defconst *c* '42))"),
    ]:
        d = os.path.join(tmp, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "b.lisp"), "w") as f:
            f.write(f'(in-package "ACL2")\n{form}\n(defthm c-ok (equal *c* *c*) :rule-classes nil)\n')
        rc1, out1 = run_acl2(d, '(assign save-expansion-file t)\n(certify-book "b" 0 t)\n')
        cert_text = ""
        if os.path.exists(os.path.join(d, "b.cert")):
            cert_text = open(os.path.join(d, "b.cert"), errors="replace").read()
        exp_text = ""
        if os.path.exists(os.path.join(d, "b@expansion.lsp")):
            exp_text = open(os.path.join(d, "b@expansion.lsp"), errors="replace").read()
        rc2, out2 = run_acl2(d, '(include-book "b")\n(value-triple (list :c *c*))\n')
        print(f"[{name}] rc1={rc1} rc2={rc2} has_exp={bool(exp_text)} err2={'Error' in out2 or 'HARD' in out2}")
        print("  cert exp-alist:", [l for l in cert_text.splitlines() if "ELIDED" in l or "DEFCONST" in l or "WITH-" in l][:5])
        if "Error" in out2 or "HARD" in out2 or "FAILED" in out2:
            print("  OUT2:", "\n  ".join(out2.strip().splitlines()[-15:]))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
