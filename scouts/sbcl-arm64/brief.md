# Scout: SBCL arm64 inline arithmetic that ACL2 code reaches

## Why here
ACL2 runs on SBCL 2.6.10 arm64 at `safety 0, speed 3` with declared integer types trusted. SBCL's fix history since 2023 concentrates in `src/compiler/srctran.lisp` (209 fix-like commits), `ir1opt.lisp` (90), `constraint.lisp` (53), `typetran.lisp` (46) and `src/compiler/arm64/arith.lisp` (57); the arm64 backend gets far less testing than x86-64. Use `git -C /Users/ember/dev/sbcl log --since=2024-01-01 -- src/compiler/arm64/arith.lisp src/compiler/srctran.lisp src/compiler/constraint.lisp` and `git show` to see what kinds of mistakes were recently fixed there, then look for the same mistake in neighbouring code that was not touched.

Random testing already done (do not repeat it): 360,000 random typed integer forms found nothing. What random forms did NOT reach is listed by running the gap report: the data file `/Users/ember/dev/compiler-audit/coverage/data/dietz-20k.sexp` contains `:all-transforms`, `:fired`, `:all-vops`, `:emitted`; unreached entries include transforms with signatures such as `(* fixnum t)`, `(+ t fixnum)`, `(- (unsigned-byte 64) <negative constant>)`, `(/ (unsigned-byte 64) (unsigned-byte 64))`, rational and ratio-constant arithmetic, and families for `logtest`, `truncate`, `floor`, `ceiling`, `expt`, `ash`, plus about 186 fixnum/signed/unsigned/bignum VOPs.

## Your question
Find a function, expressible with operations ACL2 has (`+ - * floor mod truncate rem ash logand logior logxor lognot logeqv integer-length logbitp logcount expt min max abs < <= = evenp oddp`, `if`, `let`, `the`, `car cdr cons`, characters via `char-code`/`code-char`), with truthful integer type declarations, whose compiled result under `(optimize (speed 3) (safety 0))` differs from the result of the same operations called through `notinline` generic functions (or `(funcall (symbol-function 'op) ...)`).

Method: read a specific VOP or deftransform (its argument type restrictions, the constants it special-cases, the widths at which it switches strategy: 62/63/64-bit, fixnum versus word versus signed-128), write a form whose declared types select exactly that path (confirm selection with `(let ((sb-c::*compiler-trace-output* *standard-output*)) (compile nil form))` or by disassembly), and evaluate it at the boundary values of those types against the notinline reference. Particular attention: `s128` VOPs and narrowing back to 64 bits, modular arithmetic transforms (`logand` of sums and shifts), `ash` with variable counts near 63/64, `truncate`/`floor` by constants (multiply-by-reciprocal), `integer-length` and range checks (`check-range<=`, `range<=`), comparisons mixing signed and unsigned words, constraint propagation across `if` that narrows a type incorrectly, and multiple-value returns. Use the `sbcl` host. If you find a divergence, also write the equivalent ACL2 function with `(declare (type ...))` and check it on `acl2-sbcl`.

## How you work (applies to every scout)

You are one of several workers auditing the consistency of ACL2 with its host Lisp compilers. You are a doer, not a summarizer: read source, form a specific hypothesis about how two things that must agree could disagree, write the smallest script that would show it, run it, and record what happened.

Tools you have: Read, Grep, Glob anywhere; Edit/Write only inside your own directory (your current directory); exactly one way to execute code:

    /Users/ember/dev/compiler-audit/scouts/lisp-run.sh HOST SCRIPT

HOST is `acl2-sbcl`, `acl2-ccl`, `sbcl` or `ccl`. SCRIPT is a file in your directory. For ACL2 hosts the script is fed on stdin to the ACL2 loop (end it with `(quit)`; `:q` drops to raw Lisp, `(lp)` returns). For `sbcl`/`ccl` it is loaded. The run is limited to 300 seconds, the full transcript goes to `SCRIPT.HOST.out`, and you see its last 6000 bytes. Read-only `git -C /Users/ember/dev/sbcl log|show` and `git -C /Users/ember/dev/ccl log|show` are also allowed. No other shell command will run; do not look for workarounds.

Ground truth:
- ACL2 source (commit 1d2b39a424, 8.7+ development snapshot): `/Users/ember/dev/acl2-fix/head-worktree/*.lisp`. The books directory is not checked out.
- SBCL 2.6.10 is the installed host; source of a slightly newer tree is at `/Users/ember/dev/sbcl/src/`. CCL 1.14 darwin arm64, source `/Users/ember/dev/ccl/`.
- ACL2 compiles at `safety 0`, so raw code trusts declared types and guards.
- ACL2 output: the prompt `ACL2 !>` precedes printed lines, `cw` wraps long lines, and with default settings an error in a script does not stop the following forms.

Standards:
- A finding counts only if it reproduces from a fresh image with scripts you ran yourself. Make the reproducer as small as you can, but size is not a criterion: if it needs several books, several sessions or a long event sequence, keep all of it. Save each as `repro-<short-name>.lisp` (or a `repro-<short-name>/` directory) with the exact commands, and keep the unreduced original next to it.
- Say exactly what disagrees with what: wrong VALUE (the serious kind), an ERROR where a value was expected, or a crash. Never call something a soundness bug unless you have a script in which ACL2 proves a false theorem or returns two different values for the same closed term; otherwise call it a divergence and say what is still unproven.
- Before reporting, try to explain the result as documented behaviour or as your own mistake (guard violation in raw code is undefined behaviour and is NOT a finding; printing differences are not findings).
- Refuted hypotheses are valuable: record them with one line on why, so nobody repeats them.
- Do not use `skip-proofs` or `defaxiom`, trust tags, `:redef`, or raw-Lisp redefinition in a claimed soundness reproducer; they are fine in probes.
- Do not edit anything outside your directory. Never use `git stash`. No commits.

Stopping processes, quoted verbatim from the owner's rules:

  ## Stopping processes: PID file or nothing (incident 2026-10-10)

  A subagent ran `pkill -f "cat" -u ember` to clear its own stuck `cat`. `-f` matches the whole
  command line, every app lives under `/Appli**cat**ions`, and 44 of my apps and agents got SIGTERM.
  - **Never kill by pattern.** No `pkill -f <anything>`, no `pkill -x <bare word>`, no `killall`, no `kill -u`.
  - **A process you started is stopped by the PID in its PID file**, and only that. Every detached job
    writes one (`nohup ... & echo $! > job.pid`). No PID file, no kill: tell me instead.
  - If you must look first, `pgrep -fl` and read the list; it is never the argument to a kill.
  - Every subagent brief you write quotes this block verbatim.

Files already in your directory are from an earlier start of this same task; reuse or overwrite them freely.

Deliverable: `FINDINGS.md` in your directory, updated as you go (so partial work survives), with sections **Confirmed** (claim, reproducer file, exact observed output, hosts tested), **Refuted** (hypothesis, why), **Not checked** (ideas you ran out of time for, most promising first). Your final message is a short summary pointing at that file. Aim for at least 12 distinct hypotheses actually executed.


## Continuation
A previous worker (a weaker model) already worked in this directory and stopped early. Read every file it left here first (FINDINGS.md if present, the probe scripts and their .out transcripts). Do not trust its conclusions: re-run each claimed reproducer yourself and correct FINDINGS.md where it is wrong or overstated. Then continue with what it did not check.
