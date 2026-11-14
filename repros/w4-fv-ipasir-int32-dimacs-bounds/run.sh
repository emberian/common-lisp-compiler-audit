#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1

/opt/homebrew/bin/timeout --kill-after=5s 90s /opt/homebrew/bin/python3 -B - "$HERE" <<'PYEOF'
import sys, tempfile, shutil
from pathlib import Path

here = Path(sys.argv[1])
sys.path.insert(0, "/Users/ember/dev/compiler-audit/hunts/w4-acl2s-fv-fuzz")
import fuzz_gl_fgl_cp as m

repro_lisp = (here / "repro.lisp").read_text()

with tempfile.TemporaryDirectory(prefix="w4-fv-ipasir-") as td:
    shadow = m.build_fv_shadow_books(
        Path(td) / "books-root",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "centaur/misc", "centaur/bitops", "centaur/fty",
            "centaur/satlink", "centaur/ipasir",
        ],
    )
    for pkg_p in [
        Path(shadow) / "centaur" / "satlink" / "package.lsp",
        Path(shadow) / "centaur" / "ipasir" / "package.lsp",
    ]:
        if pkg_p.exists():
            pkg_p.write_text(pkg_p.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)"))

    for label, acl2_bin in [("SBCL-2.6.10", m.SBCL_ACL2), ("CCL-1.14", m.CCL_ACL2)]:
        rc, out, err = m.run_acl2_script(acl2_bin, repro_lisp, shadow, timeout_s=85)
        norm = " ".join(out.split())
        if ":DIMACS-NEG -2147483648" in norm and ":NEGATED-OVERFLOWS-S32 T" in norm and ":DIMACS-POS-S32 NIL" in norm and "Out of bounds literal" in norm:
            print(f"[{label}] REPRODUCED satlink/ipasir INT32_MIN + 2^31 Dimacs overflow & ipasir-add-lit$a mismatch:")
            for line in out.splitlines():
                if any(k in line for k in (":LIT-NEG-LITP", ":DIMACS-POS", "Out of bounds literal")):
                    print(" ", line)
        else:
            print(f"[{label}] FAILED to reproduce (rc={rc})")
            print(out[-1000:])
            sys.exit(1)

print("PASS: w4-fv-ipasir-int32-dimacs-bounds")
PYEOF
