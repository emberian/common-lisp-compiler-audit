#!/usr/bin/env python3
"""
Expanded Provisional Certification (`pcert`), `@expansion.lsp`, `local include-book`,
`defpkg` / `make-event` / `defconst` elision, and `:ttags` checking state-machine tester (v2).
"""
import os
import shutil
import subprocess
import tempfile
import time

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


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def test_pcert_complete_stale_subbook(tmp):
    """P1: sub1 re-certified with skip-proofs-okp t / defaxioms-okp t / ttags :all
    while top finishes :pcert :complete."""
    results = []
    for mode, sub1_body, cert_flags in [
        ("skip-proofs", '(skip-proofs (defthm bad-ax nil :rule-classes nil))', 't nil'),
        ("defaxiom", '(defaxiom bad-ax2 nil :rule-classes nil)', 'nil t'),
        ("ttag-all", '(defttag :evil) (progn+touchable :all (defthm bad-ok t :rule-classes nil))', 'nil nil :ttags :all'),
    ]:
        d = os.path.join(tmp, f"p1_{mode}")
        os.makedirs(d, exist_ok=True)
        write(os.path.join(d, "payload.lsp"), "(defthm sub1-ok (equal x x))\n")
        write(os.path.join(d, "sub1.lisp"), '(in-package "ACL2")\n(make-event (er-progn (assign k 1) (value \'(defthm sub1-ok (equal x x)))))\n')
        write(os.path.join(d, "top.lisp"), '(in-package "ACL2")\n(include-book "sub1")\n(defthm top-ok (equal (cons x y) (cons x y)))\n')

        rc1, out1 = run_acl2(d, '(certify-book "sub1" 0 nil)\n')
        rc2, out2 = run_acl2(d, '(certify-book "top" 0 nil :pcert :create)\n')
        time.sleep(0.05)
        # Re-write sub1.lisp with untrusted axiom/skip-proofs/ttag and re-certify sub1 cleanly,
        # OR keep sub1.lisp mtime older than top.pcert1 by overwriting payload or touching!
        write(os.path.join(d, "sub1.lisp"), f'(in-package "ACL2")\n{sub1_body}\n')
        rc3, out3 = run_acl2(d, f'(certify-book "sub1" 0 nil {cert_flags})\n')
        rc4, out4 = run_acl2(d, '(certify-book "top" 0 nil :pcert :complete)\n')
        has_top_cert = os.path.exists(os.path.join(d, "top.cert"))
        rc5, out5 = run_acl2(d, '(include-book "top" :ttags nil)\n(value-triple (list :seen (global-val \'skip-proofs-seen (w state)) (global-val \'axioms-seen (w state)) (global-val \'ttags-seen (w state))))\n')
        results.append((mode, rc1, rc2, rc3, rc4, has_top_cert, rc5,
                        "LOAD-FAILED" if "FAILED" in out5 or "Error" in out5 else "LOAD-OK",
                        out4[-300:], out5[-450:]))
    return results


def test_expansion_file_defconst_and_pkg(tmp):
    """P2: @expansion.lsp with defconst elision, with-prover-time-limit, skip-proofs, local defpkg + make-event."""
    d = os.path.join(tmp, "p2_exp")
    os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "pkg.lisp"), '(in-package "ACL2")\n(defpkg "MYPKG" \'(defun defthm in-package equal cons car cdr nil t))\n')
    write(os.path.join(d, "expbook.lisp"), """(in-package "ACL2")
(local (include-book "pkg"))
(defconst *big-const* '(1 2 3 4 5))
(with-output :off :all (defconst *wrapped-const* '(a b c)))
(with-prover-time-limit 10 (defconst *timed-const* '(d e f)))
(encapsulate () (defconst *encap-const* '(g h i)))
(make-event '(defthm exp-ok (equal (car *big-const*) 1)))
(local (defthm use-pkg (equal (car (cons 'mypkg::foo nil)) 'mypkg::foo) :rule-classes nil))
""")
    rc_pkg, out_pkg = run_acl2(d, '(certify-book "pkg" 0 nil)\n')
    rc_cert, out_cert = run_acl2(d, '(certify-book "expbook" 0 nil :save-expansion-file t)\n')
    exp_exists = os.path.exists(os.path.join(d, "expbook@expansion.lsp"))
    # Now try certifying from expansion file!
    rc_inc, out_inc = run_acl2(d, '(include-book "expbook")\n(value-triple (list :const *big-const* *wrapped-const* *timed-const* *encap-const*))\n')
    # Also test certifying expbook@expansion.lsp directly if it exists
    rc_exp_cert = None
    out_exp_cert = ""
    if exp_exists:
        rc_exp_cert, out_exp_cert = run_acl2(d, '(certify-book "expbook@expansion" 0 nil)\n')
    return {
        "rc_pkg": rc_pkg,
        "rc_cert": rc_cert,
        "exp_exists": exp_exists,
        "rc_inc": rc_inc,
        "rc_exp_cert": rc_exp_cert,
        "out_cert_tail": out_cert[-400:],
        "out_inc_tail": out_inc[-400:],
        "out_exp_cert_tail": out_exp_cert[-500:] if out_exp_cert else "",
    }


def test_pcert_local_defpkg_and_ttags(tmp):
    """P3: :pcert with local include-book + defttag in local vs non-local + include-book :ttags checking."""
    d = os.path.join(tmp, "p3_ttag")
    os.makedirs(d, exist_ok=True)
    write(os.path.join(d, "loc.lisp"), '(in-package "ACL2")\n(defttag :loc-tag)\n(defthm loc-thm (equal x x))\n')
    write(os.path.join(d, "main.lisp"), '(in-package "ACL2")\n(local (include-book "loc"))\n(defthm main-thm (equal (cons x y) (cons x y)))\n')
    rc1, out1 = run_acl2(d, '(certify-book "loc" 0 nil :ttags ((:loc-tag)))\n')
    rc2, out2 = run_acl2(d, '(certify-book "main" 0 nil :ttags nil)\n')
    rc3, out3 = run_acl2(d, '(certify-book "main" 0 nil :ttags ((:loc-tag)))\n')
    rc4, out4 = run_acl2(d, '(include-book "main" :ttags nil)\n')
    # Also test pcert :create -> :convert -> :complete
    write(os.path.join(d, "pmain.lisp"), '(in-package "ACL2")\n(local (include-book "loc"))\n(defthm pmain-thm (equal (cons x y) (cons x y)))\n')
    rc5, out5 = run_acl2(d, '(certify-book "pmain" 0 nil :ttags ((:loc-tag)) :pcert :create)\n')
    rc6, out6 = run_acl2(d, '(certify-book "pmain" 0 nil :ttags ((:loc-tag)) :pcert :complete)\n')
    rc7, out7 = run_acl2(d, '(include-book "pmain" :ttags nil)\n')
    return {
        "loc_cert": rc1,
        "main_nil_ttag_failed": ("FAILED" in out2 or "Error" in out2),
        "main_with_ttag_ok": ("Error" not in out3 and "FAILED" not in out3),
        "inc_main_nil_ttag_ok": ("Error" not in out4 and "FAILED" not in out4),
        "pcert_create_err": ("Error" in out5 or "FAILED" in out5),
        "pcert_complete_err": ("Error" in out6 or "FAILED" in out6),
        "inc_pmain_nil_ttag_ok": ("Error" not in out7 and "FAILED" not in out7),
        "out4_tail": out4[-300:],
        "out7_tail": out7[-300:],
    }


def main():
    tmp = tempfile.mkdtemp(prefix="acl2_pcert2_")
    try:
        print("=== P1: pcert :complete stale subbook ===")
        for item in test_pcert_complete_stale_subbook(tmp):
            print(item[:8])
            if item[5]:
                print("  top.cert CREATED! out4:", item[8].strip().splitlines()[-3:])
                print("  include-book top:", item[9].strip().splitlines()[-5:])

        print("\n=== P2: @expansion.lsp + defconst elision + local defpkg ===")
        p2 = test_expansion_file_defconst_and_pkg(tmp)
        for k, v in p2.items():
            if not k.endswith("_tail"):
                print(f"  {k}: {v}")
        print("  out_exp_cert_tail:", p2["out_exp_cert_tail"].strip()[-350:])

        print("\n=== P3: local include-book ttag + pcert ===")
        p3 = test_pcert_local_defpkg_and_ttags(tmp)
        for k, v in p3.items():
            if not k.endswith("_tail"):
                print(f"  {k}: {v}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
