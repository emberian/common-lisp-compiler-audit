#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1

/opt/homebrew/bin/timeout --kill-after=5s 90s /opt/homebrew/bin/python3 -B - "$HERE" <<'PYEOF'
import sys, tempfile
from pathlib import Path

here = Path(sys.argv[1])
sys.path.insert(0, "/Users/ember/dev/compiler-audit/hunts/w4-acl2s-fv-fuzz")
import fuzz_gl_fgl_cp as m

repro_lisp = (here / "repro.lisp").read_text()

with tempfile.TemporaryDirectory(prefix="w4-fv-smtlink-") as td:
    td_p = Path(td)
    shadow = m.build_fv_shadow_books(
        td_p / "books-root",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic", "arithmetic-5", "centaur/misc", "centaur/bitops",
            "centaur/fty", "kestrel/utilities/system", "projects/smtlink",
        ],
    )
    pkg_lsp = Path(shadow) / "projects" / "smtlink" / "package.lsp"
    pkg_lsp.write_text(pkg_lsp.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)"))
    top_p = Path(shadow) / "projects" / "smtlink" / "top.lisp"
    top_p.write_text(top_p.read_text().split("(in-theory (disable")[0])

    smt_work = td_p / "smt-work"
    smt_work.mkdir(parents=True, exist_ok=True)
    (smt_work / "smtlink-config").write_text(f"smt-cmd={m.PYTHON3_BIN}\n")
    cases_p = smt_work / "repro_cases.lisp"
    cases_p.write_text(repro_lisp.replace(":smtlink-custom (", f':smtlink-custom (:smt-dir "{smt_work}" '))

    driver = f"""
{m.SHELLPOOL_SETUP}
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(ld "std/portcullis.acl2" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/sv/tutorial/portcullis.acl2" :dir :system)
(ld "projects/smtlink/portcullis.acl2" :dir :system)
(defun smt::falist-to-xdoc () (declare (xargs :mode :program)) "")
(defun smt::talist-to-xdoc () (declare (xargs :mode :program)) "")
(defun smt::ualist-to-xdoc () (declare (xargs :mode :program)) "")
(include-book "projects/smtlink/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "centaur/fty/top" :dir :system :uncertified-okp t)
(add-default-hints '((smt::smt-computed-hint clause)))
(defun w4-z3-smt-cnf ()
  (declare (xargs :guard t))
  (smt::change-smtlink-config (smt::default-smtlink-config)
                              :smt-cmd "{m.PYTHON3_BIN}"))
(defattach smt::custom-smt-cnf w4-z3-smt-cnf)
(defttag nil)
(ld "{cases_p}" :ld-error-action :continue)
"""

    for label, acl2_bin in [("SBCL-2.6.10", m.SBCL_ACL2), ("CCL-1.14", m.CCL_ACL2)]:
        rc, out, err = m.run_acl2_script(
            acl2_bin, driver, shadow, extra_env={"SMT_HOME": str(smt_work)}, timeout_s=85, cwd=str(smt_work)
        )
        if "(:SMT-LET-SHADOW-NIL " in out and "(:SMT-LET-SHADOW-NIL NIL)" not in out:
            print(f"[{label}] REPRODUCED end-to-end ACL2 + Z3 NIL theorem via SMTLink let-shadowing:")
            for line in out.splitlines():
                if ":SMT-LET-SHADOW-NIL" in line:
                    print(" ", line)
        else:
            print(f"[{label}] FAILED to reproduce (rc={rc})")
            print(out[-1000:])
            sys.exit(1)

print("PASS: w4-fv-smtlink-let-shadow-unsound")
PYEOF
