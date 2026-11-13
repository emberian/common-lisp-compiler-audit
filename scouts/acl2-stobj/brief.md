# Scout: stobj, array and attachment raw code versus the logic

## Why here
ACL2's own release notes are the history: `/Users/ember/dev/compiler-audit/scouts/data/acl2-soundness-notes.txt` holds every soundness paragraph from the 8.2 to 8.7 notes (22 of them). They cluster on: raw Lisp code generated for stobj field recognizers, `(satisfies pred)` field types, `swap-stobjs` with a live stobj, `defabsstobj` using `mbe`, stobjs interacting with `defattach`, `loop$`/`apply$`, `local` and portcullis commands, I/O channels, and printing to strings. Read that file first.

## Your question
Each of those fixes patched one path. Look for sibling paths that were not patched: the same mistake in an analogous function, field kind, or event. A stobj is a logical list with a raw destructive implementation, so every stobj primitive is a place where the logic and raw Lisp must agree.

Read the generators: `defstobj` raw code in `/Users/ember/dev/acl2-fix/head-worktree/defuns.lisp` and `other-events.lisp` (search `defstobj-raw-defs`, `defstobj-field-fns-raw-defs`, `defstobj-axiomatic-defs`, `defabsstobj`), `stobj-let` and nested stobjs, `with-local-stobj`, `swap-stobjs`, `copy-stobj`-like code, resizable arrays (`resize-`, `length-`), hash-table and stobj-table fields, `:non-executable`/`:non-memoizable` options, congruent stobjs, and array primitives `aref1`/`aset1`/`compress1` in `axioms.lisp`.

Productive probe shapes: for each field kind and type spec (including `(integer lo hi)`, `(signed-byte n)` at 62 to 64 bits, `(satisfies ...)`, `(or ...)`, `(member ...)`, `rational`, `character`, `string`, typed arrays of each, resizable arrays, nested stobj fields), compare the value obtained by the raw accessor/updater/recognizer with the value of the logical definition on the same data (logical value: evaluate with `(set-guard-checking :none)` on a non-live copy, or prove a small theorem by execution and compare); aliasing between congruent stobjs; updates through `stobj-let` that do not write back; `defattach` to functions taking stobjs; `memoize` of functions on stobjs; `:ubt` then redefinition of a stobj with a different layout while raw objects persist.

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
