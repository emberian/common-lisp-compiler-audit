# Scout: ACL2 soundness fixes from releases 4.0 through 6.5 that may be only partially fixed

## Material
`/Users/ember/dev/compiler-audit/scouts/data/acl2-soundness-mid.txt` holds every paragraph mentioning soundness from the ACL2 release notes of versions 4.0 through 6.5, grouped by release. Read all of it first. Each paragraph describes a way ACL2 could once prove a false theorem and how it was patched.

## Your question
A patch closes one path. For each fixed bug, work out the invariant that was violated, find the check that now enforces it in the current source (`/Users/ember/dev/acl2-fix/head-worktree/*.lisp`; the notes usually name the function or feature, and the source comments often retell the story, so grep for distinctive words from the note), and then ask: which newer features, added after that fix, reach the same invariant by a different route that the check does not cover? Features added later include `loop$`, `lambda$`, `apply$` and badges/warrants, `df` floating point, `stobj-let` and nested and abstract stobjs, stobj-tables, `defattach`, `memoize` and `memoize-partial`, `make-event` and its expansion files, `defun-inline`, `mbe`/`ec-call`/`return-last`, `with-global-stobj`, `:program`-mode wormholes, `set-raw-mode`, `defwarrant`, `do loop$`, `defun-nx`/`non-exec`, congruent stobjs, hons and fast alists.

Rank the old bugs by how likely a sibling is, and spend your time on the top ones: try to rebuild the original exploit from the note's description (it should now be rejected: confirm that, and say which check rejects it), then try the variants through newer features. A rejected variant is a recorded refutation; an accepted one is a finding to pursue to a wrong value or a proof of a false theorem.

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

Deliverable: `FINDINGS.md` in your directory, updated as you go (so partial work survives), with sections **Confirmed** (claim, reproducer file, exact observed output, hosts tested), **Refuted** (hypothesis, why), **Not checked** (ideas you ran out of time for, most promising first). Your final message is a short summary pointing at that file. Aim for at least 12 distinct hypotheses actually executed.
