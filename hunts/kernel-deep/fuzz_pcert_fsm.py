#!/usr/bin/env python3
"""
State-machine tester for ACL2 provisional certification (pcert),
@expansion.lsp, make-event, local include-book, :ttags, :skip-proofs-okp,
and :defaxioms-okp inheritance.
"""
import os
import shutil
import subprocess
import tempfile
import time

ACL2_SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
ACL2_CCL = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT_CMD = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]


def run_acl2(binary, workdir, script_text):
    cmd = TIMEOUT_CMD + [binary]
    p = subprocess.run(
        cmd,
        input=script_text,
        text=True,
        cwd=workdir,
        capture_output=True,
    )
    return p.returncode, p.stdout + "\n" + p.stderr


def check_clean_nil(binary, workdir, book_name, thm_name="bogus"):
    script = f"""(in-package "ACL2")
(include-book "{book_name}")
(defthm final-nil-proved nil :rule-classes nil :hints (("Goal" :use {thm_name})))
(value-triple (list :state-check
                    :ttag (ttag (w state))
                    :ttags-seen (global-val 'ttags-seen (w state))
                    :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
                    :redef-seen (global-val 'redef-seen (w state))))
"""
    rc, out = run_acl2(binary, workdir, script)
    if "FINAL-NIL-PROVED" in out and "Q.E.D." in out and ":TTAG NIL :TTAGS-SEEN NIL :SKIP-PROOFS-SEEN NIL :REDEF-SEEN NIL" in out:
        return True, out
    return False, out


SUB1_PAYLOAD_READER = """(in-package "ACL2")
(make-event
 (mv-let (chan state)
   (open-input-channel "payload.lsp" :object state)
   (mv-let (eofp form state)
     (read-object chan state)
     (declare (ignore eofp))
     (pprogn (close-input-channel chan state)
             (value form)))))
"""


def scenario_1_local_subbook_make_event():
    """
    S1: sub1.lisp has (local (include-book "sub2")) + (make-event ...).
    Does top's post-alist record sub2? No!
    When sub2 is later replaced with bogus (with :skip-proofs-okp t) and sub1 is
    recertified with :skip-proofs-okp t (sub1.lisp mtime unchanged!), can top
    complete :pcert :complete WITHOUT :skip-proofs-okp t?
    """
    d = tempfile.mkdtemp(prefix="pcert_s1_")
    try:
        with open(os.path.join(d, "sub2.lisp"), "w") as f:
            f.write('(in-package "ACL2")\n(defun helper (x) x)\n')
        with open(os.path.join(d, "sub1.lisp"), "w") as f:
            f.write(
                '(in-package "ACL2")\n'
                '(local (include-book "sub2"))\n'
                '(make-event (if (getprop \'bogus \'theorem nil \'current-acl2-world (w state))\n'
                '                 \'(defthm sub1-bogus nil :rule-classes nil :hints (("Goal" :use bogus)))\n'
                '               \'(defun sub1-ok (x) x)))\n'
            )
        with open(os.path.join(d, "top.lisp"), "w") as f:
            f.write(
                '(in-package "ACL2")\n'
                '(include-book "sub1")\n'
                '(defthm top-ok (equal (car (cons x y)) x))\n'
            )
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub2" 0 nil)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :create)\n')
        rc1, out1 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :convert)\n')
        assert "top.pcert1" in out1, out1[-600:]
        time.sleep(1.1)
        with open(os.path.join(d, "sub2.lisp"), "w") as f:
            f.write('(in-package "ACL2")\n(defun helper (x) x)\n(skip-proofs (defthm bogus nil :rule-classes nil))\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub2" 0 nil :skip-proofs-okp t)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil :skip-proofs-okp t)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :complete)\n')
        print("[S1 local sub2] pcert :complete tail:\n", out2[-500:])
        ok, out3 = check_clean_nil(ACL2_SBCL, d, "top", "sub1-bogus")
        print(f"[S1 local sub2] clean nil proved? {ok}")
        if ok:
            print(out3[-600:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def scenario_2_pcert_complete_make_event_skip_proofs():
    d = tempfile.mkdtemp(prefix="pcert_s2_")
    try:
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write("(defun ok-fn (x) x)\n")
        with open(os.path.join(d, "sub1.lisp"), "w") as f:
            f.write(SUB1_PAYLOAD_READER)
        with open(os.path.join(d, "top.lisp"), "w") as f:
            f.write(
                '(in-package "ACL2")\n'
                '(include-book "sub1")\n'
                '(defthm top-ok (equal (car (cons x y)) x))\n'
            )
        rc_s, out_s = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil)\n')
        assert "sub1.cert" in out_s, out_s[-600:]
        rc0, out0 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :create)\n')
        assert "top.pcert0" in out0, out0[-600:]
        rc1, out1 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :convert)\n')
        assert "top.pcert1" in out1, out1[-600:]
        time.sleep(1.1)
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write("(skip-proofs (defthm bogus nil :rule-classes nil))\n")
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil :skip-proofs-okp t)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :complete)\n')
        print("[S2 make-event skip-proofs] pcert :complete tail:\n", out2[-500:])
        ok, out3 = check_clean_nil(ACL2_SBCL, d, "top", "bogus")
        print(f"[S2 make-event skip-proofs] clean nil proved? {ok}")
        if ok:
            print(out3[-600:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def scenario_3_pcert_complete_defaxioms():
    d = tempfile.mkdtemp(prefix="pcert_s3_")
    try:
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write("(defun ok-fn (x) x)\n")
        with open(os.path.join(d, "sub1.lisp"), "w") as f:
            f.write(SUB1_PAYLOAD_READER)
        with open(os.path.join(d, "top.lisp"), "w") as f:
            f.write(
                '(in-package "ACL2")\n'
                '(include-book "sub1")\n'
                '(defthm top-ok (equal (car (cons x y)) x))\n'
            )
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :create)\n')
        rc1, out1 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :convert)\n')
        assert "top.pcert1" in out1, out1[-600:]
        time.sleep(1.1)
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write("(defaxiom bogus nil :rule-classes nil)\n")
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil :defaxioms-okp t)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :complete)\n')
        print("[S3 defaxiom] pcert :complete tail:\n", out2[-500:])
        ok, out3 = check_clean_nil(ACL2_SBCL, d, "top", "bogus")
        print(f"[S3 defaxiom] clean nil proved? {ok}")
        if ok:
            print(out3[-600:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def scenario_4_pcert_complete_ttags():
    d = tempfile.mkdtemp(prefix="pcert_s4_")
    try:
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write("(defun ok-fn (x) x)\n")
        with open(os.path.join(d, "sub1.lisp"), "w") as f:
            f.write(SUB1_PAYLOAD_READER)
        with open(os.path.join(d, "top.lisp"), "w") as f:
            f.write(
                '(in-package "ACL2")\n'
                '(include-book "sub1")\n'
                '(defthm top-ok (equal (car (cons x y)) x))\n'
            )
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :create)\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :convert)\n')
        time.sleep(1.1)
        with open(os.path.join(d, "payload.lsp"), "w") as f:
            f.write('(progn (defttag :evil) (progn! (set-raw-mode t) (defun evil-raw () t)))\n')
        run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil :ttags :all)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :complete)\n')
        print("[S4 ttags] pcert :complete tail:\n", out2[-500:])
        rc3, out3 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(include-book "top")\n(value-triple (list (ttag (w state)) (global-val \'ttags-seen (w state))))\n')
        print("[S4 ttags] include-book top (no :ttags) tail:\n", out3[-500:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def scenario_5_pcert_convert_with_skip_proofs_create():
    """
    What if a book itself is certified with :skip-proofs-okp t :pcert :create,
    and then :pcert :convert WITHOUT :skip-proofs-okp t?
    """
    d = tempfile.mkdtemp(prefix="pcert_s5_")
    try:
        with open(os.path.join(d, "b.lisp"), "w") as f:
            f.write('(in-package "ACL2")\n(skip-proofs (defthm bogus nil :rule-classes nil))\n')
        rc1, out1 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "b" 0 nil :skip-proofs-okp t :pcert :create)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "b" 0 nil :pcert :convert)\n')
        rc3, out3 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "b" 0 nil :pcert :complete)\n')
        print("[S5] convert out2:\n", out2[-400:])
        print("[S5] complete out3:\n", out3[-400:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


def scenario_6_top_includes_sub_pcert0():
    """
    What if sub1 is certified with :pcert :create and :skip-proofs-okp t,
    and top is certified with :pcert :create (no :skip-proofs-okp t),
    then sub1 is recertified with :skip-proofs-okp t, then top :convert -> :complete?
    """
    d = tempfile.mkdtemp(prefix="pcert_s6_")
    try:
        with open(os.path.join(d, "sub1.lisp"), "w") as f:
            f.write('(in-package "ACL2")\n(skip-proofs (defthm bogus nil :rule-classes nil))\n')
        with open(os.path.join(d, "top.lisp"), "w") as f:
            f.write('(in-package "ACL2")\n(include-book "sub1")\n(defthm top-bogus nil :rule-classes nil :hints (("Goal" :use bogus)))\n')
        rc1, out1 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "sub1" 0 nil :skip-proofs-okp t :pcert :create)\n')
        rc2, out2 = run_acl2(ACL2_SBCL, d, '(in-package "ACL2")\n(certify-book "top" 0 nil :pcert :create)\n')
        print("[S6] top :pcert :create (including sub1.pcert0 with skip-proofs) tail:\n", out2[-500:])
    finally:
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    scenario_1_local_subbook_make_event()
    scenario_2_pcert_complete_make_event_skip_proofs()
    scenario_3_pcert_complete_defaxioms()
    scenario_4_pcert_complete_ttags()
    scenario_5_pcert_convert_with_skip_proofs_create()
    scenario_6_top_includes_sub_pcert0()
