# Scout: things ACL2 recomputes after certification

## Starting point (a confirmed bug, found today)
`/Users/ember/dev/compiler-audit/repros/loop-ignore-ok/loop-ignore-ok.lisp`: a book with `(set-ignore-ok t)` and a function whose `loop$` body binds an unused variable certifies, but calling the function after `include-book` raises "Implementation error: translate11-loop$ in oneify encountered an untranslatable LOOP$". Loading the same file with `ld` works. Cause: `oneify` in `/Users/ember/dev/acl2-fix/head-worktree/interface-raw.lisp` (search for `untranslatable LOOP$`) re-translates the `loop$` against the world current when the executable counterpart is built, and after include-book the book's `acl2-defaults-table` setting is not in effect.

## Your question
That instance only produces an error. Find out whether the same class can produce a wrong VALUE: any place where ACL2, after a book was certified (or a function admitted), recomputes, re-translates, re-expands or re-evaluates something in a context that can differ from the one in which it was checked, such that it succeeds with a different meaning.

Concretely read and probe:
- `oneify` and `oneify-cltl-code` in `interface-raw.lisp`: the `lambda$` case has the same re-translate structure (untested); also how macros, `mbe`, `ec-call`, `return-last`, `flet`, `stobj-let`, `with-local-stobj` are handled there versus in `translate11` (`translate.lisp`).
- What context differs at include-book time: `acl2-defaults-table` (every key, not only ignore-ok), `local` events and what is skipped, the includer's pre-existing world (tables, `macro-aliases`, `untrans-table`, badges and warrants, attachments via `defattach`), package and `*readtable*`/`*read-base*` state, `ld` specials, guard-checking mode.
- `install-defs-for-add-trip`, `hcomp-init`, `load-compiled-book`, `acl2-compile-file` in `interface-raw.lisp` and the expansion-file machinery in `other-events.lisp`: when is the compiled definition used and when is it re-derived; what does `defconst` store versus recompute; what does `make-event` replay.
- Translation that consults the world for more than legality (for example anything that depends on badges, warrants, `defattach`, stobj recognizers, defined constants, or macro definitions that could differ between the certification world and an including world).

A wrong-value result means: one script, a certified book with no `skip-proofs`, and a closed term whose value differs between a session that `ld`s the book source and a session that `include-book`s it (or between the logical value and the executed value in one session). Use `certify-book` then `include-book` in separate runs of lisp-run.sh; both `acl2-sbcl` and `acl2-ccl`.

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
