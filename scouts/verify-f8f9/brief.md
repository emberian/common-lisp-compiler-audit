You are an independent verifier in a quality-assurance audit of the ACL2 theorem prover, run on the owner's own machine. Another worker reported two soundness defects in ACL2 (cases where ACL2 proves NIL / accepts a false theorem because a stobj element-type check disagrees with the logical definition). Your job is only to confirm or refute them by re-running the existing reproducers in fresh sessions, and to describe each precisely enough for an upstream bug report to the ACL2 maintainers. Do not try to weaponize anything; this is defect confirmation.

Runner: /Users/ember/dev/compiler-audit/scouts/lisp-run.sh HOST SCRIPT  (HOST one of acl2-sbcl, acl2-ccl; 300s cap; saves SCRIPT.HOST.out and prints the tail).

Reproducers already on disk in /Users/ember/dev/compiler-audit/repros/defstobj-satisfies-host/ :
- stale-type-cache/nil-via-local.lisp and stale-type-cache/nil-book.lisp  (claim F8: CCL only — a stobj array read returns garbage after a predicate is defined locally in an encapsulate then differently at top level; NIL is proved; certify-book accepts nil-book.lisp. SBCL returns T and rejects.)
- string-stobj/string-stobj.lisp  (claim F9: both hosts — a single-field stobj with element type (or character (and integer symbol)) is represented as a string; the live stobj fails its own recognizer and NIL is proved.)
- run.sh runs them on both hosts; README.md has a 22-case table.

Do this:
1. Read run.sh and README.md and each reproducer. For each claim, run the exact script in a FRESH session on BOTH acl2-sbcl and acl2-ccl via lisp-run.sh. Quote the lines that show the outcome (the proved/failed theorem, the value read back, whether certify-book succeeded). Decide: CONFIRMED, REFUTED, or NEEDS-CHANGE (with the corrected reproducer).
2. For F8 specifically, check it is a genuine proof of NIL with no skip-proofs, no trust tag, no :program mode, and that the certified book really contains a theorem equivalent to NIL — because that is the strong claim. If the "garbage read" depends on uninitialized memory, say so and note any run-to-run variation.
3. Minimize each confirmed reproducer to the smallest self-contained .lisp that still proves NIL (or still diverges), saving it next to the original as <name>-min.lisp, and re-run the minimized file in a fresh session on the affected host(s).
4. Write /Users/ember/dev/compiler-audit/repros/defstobj-satisfies-host/VERIFY.md: per claim, CONFIRMED/REFUTED, the exact commands, the decisive transcript lines, host(s) affected, soundness vs robustness, and the minimized file name. Do not edit LEDGER.md or any file outside defstobj-satisfies-host/. No commits.

Rules: at most 2 Lisp processes at once (the runner enforces timeout). Keep output short (grep/tail; never paste a whole transcript). No planning documents. If disk is low, stop and say so. Stop a process only by a PID you wrote to a PID file; never by name or pattern (no pkill/killall/kill -u); if there is no PID file, leave it and report.

Deliverable is VERIFY.md plus the minimized files. Final line: for each of F8, F9, one of CONFIRMED/REFUTED/NEEDS-CHANGE and the host(s).
