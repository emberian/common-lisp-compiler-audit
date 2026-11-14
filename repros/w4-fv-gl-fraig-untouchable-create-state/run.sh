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

with tempfile.TemporaryDirectory(prefix="w4-fv-fraig-") as td:
    shadow = m.build_fv_shadow_books(
        Path(td) / "books-root",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "hacking",
            "centaur/misc", "centaur/bitops", "centaur/fty", "centaur/aig",
            "centaur/satlink", "centaur/ubdds", "centaur/gl",
        ],
    )
    for pkg_rel in ["gl", "satlink", "bitops", "fty", "aig", "ubdds"]:
        p = Path(shadow) / "centaur" / pkg_rel / "package.lsp"
        if p.exists():
            p.write_text(p.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)"))

    for label, acl2_bin in [("SBCL-2.6.10", m.SBCL_ACL2), ("CCL-1.14", m.CCL_ACL2)]:
        rc, out, err = m.run_acl2_script(acl2_bin, repro_lisp, shadow, timeout_s=85)
        if ":GL-FRAIG-CREATE-STATE-NIL" in out and ":GL-FRAIG-CREATE-STATE-NIL NIL)" not in out:
            print(f"[{label}] REPRODUCED NIL theorem under (defttag nil) via bfr-fraig-satlink.lisp:42:")
            for line in out.splitlines():
                if ":GL-FRAIG-CREATE-STATE-NIL" in line:
                    print(" ", line)
        else:
            print(f"[{label}] FAILED to reproduce (rc={rc})")
            print(out[-1000:])
            sys.exit(1)

print("PASS: w4-fv-gl-fraig-untouchable-create-state")
PYEOF
