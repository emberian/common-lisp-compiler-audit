# Scout: CCL arm64 backend inline paths that ACL2 code reaches

## Why here
ACL2 also runs on CCL 1.14 darwin arm64. The arm64 port is young: 228 commits touch `compiler/ARM64/`, most recent 2026-11-04 (`git -C /Users/ember/dev/ccl log -- compiler/ARM64`). One compiler bug is already confirmed on this host: one-argument `floor`/`truncate`/`round`/`ceiling` on a declared fixnum returns one value instead of two (`/Users/ember/dev/common-lisp-compiiler-audit/repros/ccl-unary-division.lisp`). Do not re-report it; look for its relatives.

Random testing done: 360,000 random typed integer forms, nothing. Coverage of the compiler's own tables by those forms is recorded in `/Users/ember/dev/compiler-audit/coverage/data/ccl-gap-dietz-20k.txt` (read it): 93 of 243 arm64 p2 handlers and 148 of 529 vinsn templates were reached. Unreached and relevant: `fixnum-ash`, `fixnum-overflow`, `%i+`, `%i-`, `%ilsr`, `natural-shift-left/right`, `%natural+`, `%natural-`, `%natural-logand/logior/logxor`, `require-s8/s16/s32/s64`, `require-u16/u32/u64`, `consp`, `endp`, `char-code`, `code-char`, `multiple-value-bind`, `nth-value`, `self-call`, and vinsns such as `u64->integer`, `s64->integer`, `box-fixnum`, `unbox-s64`, `u64-popcount`, `shift-left-variable-word`, `sign-extend-halfword`.

## Your question
Find a function, expressible with operations ACL2 has (integer arithmetic and bit operations, `if`, `let`, `the`, `car cdr cons`, `char-code`/`code-char`, self-recursion, multiple values), with truthful type declarations, whose compiled result under `(optimize (speed 3) (safety 0))` differs from an unoptimized reference (the same operations declared `notinline`, or evaluated through `funcall` of `symbol-function`).

Method: read the p2 handler in `/Users/ember/dev/ccl/compiler/ARM64/arm642.lisp` (`defarm642 <operator>`) and the vinsns it emits in `arm64-vinsns.lisp`, and the front-end path that creates that operator (`nx1.lisp`, `optimizers.lisp`, `acode-rewrite.lisp`): what declared types select it, which constants are special-cased, and where 61-bit fixnum, 64-bit natural and bignum cases meet. Write a form whose declarations select that path, then evaluate at the boundaries: most-positive/negative fixnum and their neighbours, 2^60..2^64 and neighbours, shift counts 0, 1, 60 to 65, negative shifts, divisors 1, -1 and powers of two. Unsigned 64-bit (`(unsigned-byte 64)`) arithmetic and logical-immediate encoding of constants (`arm64-asm.lisp`) deserve particular attention, as do tail self-calls with more arguments than registers and functions returning multiple values through `mv-let`-style code. Use the `ccl` host; for any divergence also write the equivalent ACL2 function with `(declare (type ...))` and check it on `acl2-ccl`.

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
A previous worker (a weaker model) already worked in this directory and stopped early. Read every file it left here first (FINDINGS.md if present, the probe scripts and their .out transcripts). Do not trust its conclusions: re-run each claimed reproducer yourself and correct FINDINGS.md where it is wrong or overstated (for example, behaviour that the ACL2 documentation describes as intended is not a finding; say so). Then continue with what it did not check.
