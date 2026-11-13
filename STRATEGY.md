*Editorial note (salvage, not authored content): This file was supposed to hold a
strategy plan authored by **gpt-6-astra** via the `codex` CLI on **2026-11-13**, for the
ACL2 + host-Lisp soundness/robustness audit. The run was **cut off by the codex CLI's own
safeguard before completion** — the safeguard flagged the content as a possible
cybersecurity risk at exactly the point where the plan file would have been written, so
`codex` never saved `STRATEGY.md`. What follows is a **mechanical salvage from the run
log** (`scratchpad/codex-strategy/strategy.log`, 3751 lines). It is **truncated**: the only
prose the model actually authored in the log is its opening statement of intent and its
closing summary. The detailed multi-section plan the brief asked for (the 7-part partition,
per-dimension oracles, exhaustion criteria, and a ranked roadmap) was **never emitted to the
log** and could not be recovered. See the Salvage notes at the end for exactly what survives
and what is missing.*

---

## Authored prose recovered from the run log

The two passages below are the complete set of model-authored (category-4) text in the
transcript, reproduced verbatim and in order. Everything else in the log is the task brief,
verbatim dumps of other files the model read (`RESEARCH.md` — read twice —, `LEDGER.md`,
`CCL.md`, `SBCL.md`, `ACL2-BUG-REPORT.md`, `primitives/README.md`, `loore-profile.txt`, and
two `primitives/*.lisp` files), or shell commands and their output; none of that is the
model's own plan and so is excluded.

### Opening intent (start of the run)

I'll read the ledger, research ranking, current tooling, and source boundaries, then write
`STRATEGY.md` with explicit exhaustion criteria and executable work packages. I'll leave
every other file untouched and run no git commands.

### Closing summary (end of the run, immediately before the safeguard aborted it)

The ledger supports putting history testing first. It also exposes two limits the plan needs
to address: "logical" evaluation still shares host primitives, and the matrix's suppressed
warnings invalidate its claimed fasl-fallback control. I also found an alias-aware sweep
already added by the parallel work, so I'll build on that rather than propose it anew.

---

## Salvage notes

**What this log actually contains.** The transcript is 3751 lines and almost entirely
non-authored: a `user` brief (lines 13–128), one short `codex` turn stating intent (lines
129–131), a sequence of nine read-only `exec` shell blocks (lines 132–3744) whose output is
verbatim file contents, and a final `codex` turn with the one-paragraph summary (lines
3745–3746). The run was configured with `reasoning summaries: none`, so the model's
chain-of-thought was never logged. Total cost was only **47,577 tokens** — consistent with a
read-and-summarize pass that was stopped before the plan was written.

**Sections that appear complete.** Both recovered passages are complete sentences and read
as finished:
- *Opening intent* — complete. A statement of approach, not plan content.
- *Closing summary* — complete as a paragraph. This is the model's final `-o`-style message.
  It makes three substantive claims (below) but is far shorter than the "under 250 words /
  top 5 moves" summary the brief requested, so even this message is partial relative to its
  spec.

**Sections that are cut off / missing entirely.** The body of the plan — i.e. essentially
all of it — is absent. The brief asked for seven parts: (1) a partition of the ACL2 × host
interface into dimensions with per-dimension oracle, generation strategy, and a concrete
"exhausted" criterion; (2) where bounded-exhaustive enumeration is feasible (and fixing the
primitive sweep's `eql`/`equal` blind spot); (3) event-sequence / history state-machine
fuzzing; (4) the oracle portfolio; (5) the host-compiler layer (SBCL/CCL, coverage-guided
toward unreached transforms/VOPs); (6) prioritization and a staged, swarm-parallel roadmap;
and (7) the path toward a future formal ACL2-vs-Lisp equivalence proof. **None of these
sections was written to the log.** The `-o` message also promised a ranked "top 5 moves" and
an explicit statement of where the model disagrees with `RESEARCH.md`'s ranking; neither the
ranked list nor the point-by-point disagreement survives.

**A caution for anyone re-reading the raw log.** Lines ~606–1018 and ~2183–2599 contain
exactly the kind of strategic prose the brief wanted — numbered recommendations with
`**Technique.** / **Implementation.** / **Reaches.** / **Cost.**` headers and citations to
XDsmith, EMI, YARPGen, Zest, swarm testing, etc. **This is not the model's writing.** It is
`RESEARCH.md` (the pre-existing 11-recommendation literature survey written earlier by
another agent), which the model `cat`'d in full once and re-read in `sed` chunks. It was
excluded from this salvage per instruction; do not mistake it for the recovered plan.

**What the model clearly intended but did not reach.** From its closing summary, the
direction it was going to argue for is legible even though the plan is gone:
- **Prioritize history / context testing first** — the model agreed with putting
  history/context (event-sequence, persistence-around-definitions) testing at the top,
  citing the ledger's bug distribution as support. (This aligns with, rather than overturns,
  `RESEARCH.md`'s top-ranked item.)
- **Two limits it meant to address in the plan:** (a) ACL2's "logical" evaluation path still
  shares host primitives, so it is not an independent oracle for bugs in the evaluator
  itself; and (b) the route matrix's suppressed warnings invalidate its claimed
  fasl-fallback control.
- **One build-on-existing note:** an alias-aware primitive sweep has already been added by a
  parallel agent (`primitives/sweep-aliased.lisp`), so the model intended to build on it
  rather than re-propose it (this is the `eql`/`equal` blind-spot fix the brief flagged).

**Recommended recovery action.** Because the plan body was blocked by the codex safeguard
(not by anything in the content being unrecoverable), the realistic fix is to **re-run the
`codex` strategy lead** — either rephrased to avoid the cybersecurity-risk classifier, or
with the elevated access the safeguard's error message pointed to — rather than to
reconstruct the plan from this log, which does not contain it.
