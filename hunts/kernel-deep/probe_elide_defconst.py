#!/usr/bin/env python3
"""
Test hcomp-elided-defconst-alist2 vs subst-by-position-eliding-defconst2
mismatch on with-output / with-prover-step-limit / with-guard-checking!
"""
import os
import shutil
import subprocess
import tempfile

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]


def run_acl2(cwd, script_text):
    p = subprocess.run(
        TIMEOUT_CMD + [ACL2_SBCL],
        cwd=cwd,
        input=script_text,
        text=True,
        capture_output=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


def main():
    tmp = tempfile.mkdtemp(prefix="acl2_elide_")
    try:
        # Note: expansion-alist gets populated by make-event or macros or top-level expansion!
        # Let's test both direct top-level forms and make-event-generated forms, with compile=t and compile=nil.
        for compile_flg in ["t", "nil"]:
            d = os.path.join(tmp, f"comp_{compile_flg}")
            os.makedirs(d, exist_ok=True)
            book = """(in-package "ACL2")
(with-output :off :all (defconst *wo-direct* '42))
(with-prover-step-limit 1000 (defconst *sl-direct* '99))
(make-event '(with-output :off :all (defconst *wo-me* '123)))
(make-event '(with-prover-step-limit 1000 (defconst *sl-me* '456)))
(make-event '(with-guard-checking nil (defconst *wg-me* '789)))
(defthm chk-vals
  (and (equal *wo-direct* 42)
       (equal *sl-direct* 99)
       (equal *wo-me* 123)
       (equal *sl-me* 456)
       (equal *wg-me* 789))
  :rule-classes nil)
"""
            with open(os.path.join(d, "b.lisp"), "w") as f:
                f.write(book)
            rc1, out1 = run_acl2(d, f'(certify-book "b" 0 {compile_flg})\n')
            rc2, out2 = run_acl2(
                d,
                '(include-book "b")\n'
                '(value-triple (list *wo-direct* *sl-direct* *wo-me* *sl-me* *wg-me*))\n'
                '(defthm prove-nil-if-mismatch (equal *wo-me* 123) :rule-classes nil)\n',
            )
            print(f"=== compile={compile_flg} cert_rc={rc1} inc_rc={rc2} ===")
            print("cert tail:", "\n".join(out1.strip().splitlines()[-10:]))
            print("inc tail:", "\n".join(out2.strip().splitlines()[-20:]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
