# Stale, missing and foreign artifacts: certify-book / include-book

Claim under test: for every way the on-disk artifacts of a book (`.cert`,
`.port`, compiled file, expansion file) can disagree with the source or with
the including session, evaluating the book's functions after `include-book`
equals a from-scratch admission of the current source, or ACL2 refuses, or it
warns and falls back to the source. It must never silently run code that
disagrees with the logical definitions.

Hosts: ACL2 8.7+ at 1d2b39a424 on SBCL 2.6.10 (`head`) and CCL 1.14 (`ccl`),
darwin arm64. 122 scenarios per host, all run on both.

## Files

- `run.sh HOST [SCENARIO...]` runs the table (`head` or `ccl`); one ACL2 process at a time.
- `scenarios.tsv`: id, expected class (a regex over the observed class), group, description.
- `scenarios.sh`: one function `sc_<id>` per row. `lib.sh`: helpers (`put`, `cert`, `inc`, `ref`, `ctl`).
- `books/`: hand-written book families. `hbA`/`hbB` are two versions of one book
  with the same names, the same file length and different bodies (constant,
  guard-verified, unverified, `:program`, macro, `encapsulate`+`local`, `progn`,
  `defun-inline`, a 6001-element computed `defconst`, stobj, mutual recursion,
  typed, `loop$`, `lambda$`, a theorem). `sb*`/`top`/`lsub`: sub-books. `vt*`:
  reclassification. `me`/`mec`: environment-dependent `make-event` without and
  with `:check-expansion t`. `rc`: reader conditionals. `at`: attachments.
  `lq`/`ltop`: local definitions. `*q.lisp`: the queries.
- `synth-books/`: two generated books (seeds 11 and 12, 12 function pairs) copied
  once from `synth/synth.lisp`, and a mutant of seed 11.
- `results-head.tsv`, `results-ccl.tsv`: id, expected, observed, verdict,
  books included/certified, warning tags, control, description.
- `dispositions.tsv`: class and citation for every row outside the claim.
- `summary.md`: the tables below, regenerated from the results.

## Method

Each scenario runs a session under test (`inc`: forms, `include-book`, queries)
and a reference (`ref`: a new session in a clean directory holding only the
current sources, which `ld`s them and replays the same queries). Query records:
`@Q` values under guard checking `t`, `@N` under `:none`, `@W` the world's
stored bodies, constant values and theorem, `@S` whether the prover (executable
counterpart disabled) agrees with evaluation. Observed classes:

- `equal`: included, no warning, records identical to the reference;
- `warned-equal`: the same with a warning (`[Compiled file]`, `[Uncertified]`, ...);
- `refused`: the book was not added (for session conflicts the records after the
  failed include are also compared with a session that never tried);
- `STALE-silent` / `STALE-warned`: included, records differ from the reference.

Control: `ctl` replays the reference with the stale version of the file; the
control column is `ok` when its records differ from the reference's, so stale
code would be seen. `ctl_rawload` additionally loads a stale compiled file by
raw `load` over a fresh `ld` and must be reported `STALE-silent`. Rows with `-`
have no stale version (session conflicts, same-environment `make-event`).

## Results

| host | scenarios | as expected | equal | warned-equal | refused | STALE-silent | STALE-warned | error |
|---|---|---|---|---|---|---|---|---|
| SBCL | 122 | 92 | 40 | 27 | 24 | 24 | 7 | 0 |
| CCL | 122 | 92 | 39 | 28 | 24 | 24 | 7 | 0 |

By expected class (SBCL / CCL observed):

| expected | n | observed SBCL | observed CCL |
|---|---|---|---|
| `equal` | 32 | equal 32 | equal 32 |
| `STALE-silent` | 1 | STALE-silent 1 | STALE-silent 1 |
| `warned-equal` | 28 | STALE-warned 3, warned-equal 25 | STALE-warned 3, warned-equal 25 |
| `warned-equal / refused` | 30 | STALE-silent 18, STALE-warned 2, refused 8, warned-equal 2 | STALE-silent 18, STALE-warned 2, refused 8, warned-equal 2 |
| `equal / warned-equal / refused` | 10 | STALE-silent 5, STALE-warned 2, equal 3 | STALE-silent 5, STALE-warned 2, equal 3 |
| `equal / warned-equal` | 5 | equal 5 | equal 4, warned-equal 1 |
| `refused` | 16 | refused 16 | refused 16 |

Rows outside the claim, with disposition (same on both hosts unless noted):

| scenario | observed | class | tamper | disposition |
|---|---|---|---|---|
| fasl_oldver_newer | STALE-silent | soundness | mtime | F10 with the time set by hand. :DOC book-hash's own example says to "update the write-date on the compiled file ... if you want to avoid a warning". |
| fasl_oldver_same_mtime | STALE-silent | soundness | mtime | F10 with the time set by hand. |
| fasl_oldver_eq_cert | STALE-silent | soundness | mtime | F10 with the time set by hand (equal dates are accepted). |
| fasl_oldver_checksum | STALE-silent | soundness | mtime | F10; checksum book-hashes do not cover the compiled file. |
| fasl_oldver_lcf_t | STALE-silent | soundness | mtime | F10; :load-compiled-file t adds no check. |
| src_body_samelen | STALE-silent | documented | mtime | :DOC book-hash: the default book-hash is file length and write date ("decreased security"); checksum mode refuses (src_body_samelen_checksum). Observed in addition: the certificate's cert-data supplies the translated bodies and theorem formulas, so :pe shows the new text while the logical body, the theorem and the code are the old ones. |
| src_guard_samelen | STALE-silent | documented | mtime | As src_body_samelen; the old guard check in the compiled *1* function rejects a call that the new declaration allows (error, not a wrong value). |
| cert_oldver_fasl_new | STALE-silent | documented | content | Old certificate with matching length and date: cert-data from the certificate overrides the source's bodies and theorems in the world. :DOC book-hash (certificate contents are not hashed by book-hash alists). |
| cert_otherhost_oldfasl | STALE-silent | soundness | mtime | F10, cross-host, time set by hand. |
| port_other_uncert | STALE-warned | documented | content | :DOC uncertified-books: for an uncertified book with a .port file, "the forms in B.port [are] evaluated before the forms in B.lisp"; a foreign .port adds its package to the session. |
| me_global | STALE-silent | documented | none | :DOC make-event: the expansion "is recorded in the book's certificate and re-used during a subsequent include-book". |
| me_unset | STALE-silent | documented | none | As me_global. |
| me_file | STALE-silent | documented | none | As me_global. |
| me_world | STALE-silent | documented | none | As me_global. |
| me_host | STALE-warned | documented | none | As me_global (the expansion made by the other host is used). |
| rc_host | STALE-warned | soundness | none | F12. repros/cross-host-reader-conditional/. Only a source comment covers it (acl2.lisp, Remarks on *acl2-readtable*: *features* must be the same "throughout all phases"); certificates record neither host nor features. |
| rc_host_fasl | STALE-silent | soundness | none | F12 with this host's own compiled file: no warning at all. |
| sub_src_edited | STALE-warned | documented | none | O1. repros/uncertified-top-stale-compiled/. [Uncertified] warning, yet the stale compiled file of the uncertified book is loaded. :DOC uncertified-books: "all bets are off", "quiet logical inconsistency". |
| sub_recert | STALE-warned | documented | none | O1, as sub_src_edited (the sub-book is recertified, the top book is not). |
| sub_recert_samestamp | STALE-silent | documented | mtime | :DOC book-hash, as src_body_samelen but for a sub-book: top's certificate still matches, top's compiled file carries the old macro expansions, inline bodies and constant. |
| sub_recert_samestamp_checksum | STALE-warned | documented | mtime | O1; with checksums the mismatch is detected and warned about, the stale compiled file is still loaded. |
| sub_fasl_oldver | STALE-silent | soundness | mtime | F10 for a sub-book's compiled file. |
| sub_top_fasl_oldver | STALE-silent | soundness | mtime | F10 for the top book's compiled file after a sub-book changed. |
| exp_oldver | STALE-warned | soundness | mtime | Same date rule for book@expansion.lsp (:DOC book-compiled-file: the expansion file "can be loaded if the compiled file is missing"); a [Compiled file] warning is printed but the stale expansion file is what gets loaded. |
| exp_oldver_comp | STALE-silent | soundness | mtime | As exp_oldver; :load-compiled-file :comp turns the stale expansion file into a compiled file that later includes load silently. |
| img_reinclude | STALE-silent | documented | none | :DOC redundant-events: "An include-book event is redundant if the book has already been included"; the image keeps the version it was saved with. |
| syn_fasl_mutant | STALE-silent | soundness | mtime | F10 on a generated book (residues change, no warning). |
| syn_src_mutant_samestamp | STALE-silent | documented | mtime | As src_body_samelen, generated book. |
| cert_otherhost_oldfasl_natural | STALE-silent | soundness | none | F10, race variant. repros/stale-compiled-file/race.sh. certify-book on the other host deletes only its own compiled file; dates have 1 s resolution. |
| fasl_oldver_cp_p | STALE-silent | soundness | none | F10. repros/stale-compiled-file/run.sh. A compiled file is tied to its book only by "write date >= certificate's" (load-compiled-book, interface-raw.lisp). |

## Findings (reproducers in `../../repros/`)

- **F10, soundness, both hosts, no hand tampering**: `repros/stale-compiled-file/`.
  `include-book` loads a compiled file when its write date is >= the
  certificate's and checks nothing else. `run.sh`: the new book is certified
  elsewhere, the old book is certified locally two seconds later, the new
  `book.lisp` and `book.cert` are copied in with `cp -p`; a fresh
  `(include-book "book")` prints no warning, runs the old `f`, gives `*k*` the
  old value in the logical world, and proves `nil` from the book's own theorem.
  `race.sh`: the same with no copy at all, when two hosts share a directory and
  the other host recertifies within the same second (its `certify-book` removes
  only its own compiled file).
- **F11, robustness, both hosts**: `repros/portcullis-book-changed-raw-abort/`.
  A book certified on top of `(include-book "sub")`; `sub` then changes and is
  recertified. Including the book aborts from raw Lisp with "There is a problem
  with the certificate, which may be described below in detail." and no detail;
  piped input after it is dropped. Cause: the pre-alist check in
  `chk-raise-portcullis` calls `include-book-raw-error` outside the handler that
  turns such errors into warnings.
- **F12, soundness, both hosts, documented only in a source comment**:
  `repros/cross-host-reader-conditional/`. A book using `#+sbcl`/`#+ccl`
  certified by one host and included by the other with that certificate: code is
  compiled from what the includer reads, the logical body and theorem come from
  the certificate, `nil` is proved. `acl2.lisp` ("Remarks on *acl2-readtable*")
  says `*features*` must not differ; nothing checks it.
- **O1, documented behaviour**: `repros/uncertified-top-stale-compiled/`. Edit and
  recertify a sub-book, include the stale top book: one `[Uncertified]` warning,
  then the old compiled file and the old certificate's translated bodies are used
  anyway and `nil` is provable. :DOC uncertified-books: "all bets are off".
- Observation behind several documented rows: the certificate's cert-data
  supplies translated bodies and theorem formulas by name. With a certificate
  that still matches (default book-hash is length and write date), `:pe` shows
  the new source text while the logical body, the stored theorem and the code
  are the old ones.

Everything else held: missing, older, truncated, emptied, garbage and
other-host compiled files fall back with a warning (also when a truncated file
of the old version was partly loaded first); damaged or foreign certificates are
refused or treated as uncertified; all 10 session conflicts are refused and leave
the session's own definitions intact; different defaults table, package,
`ld-skip-proofsp`, guard-checking mode, compiler switch and every
`:load-compiled-file` value give the fresh values; `:check-expansion t` refuses
all four environment changes; local definitions leave nothing behind; a
restarted image keeps what it included and re-includes correctly after undo.

## Not covered

Provisional certification beyond one manual pass, `.acl2x` files, ttags and raw
mode, `ACL2_COMPILE_FLG`/`cert.pl` build flows, hand-edited certificate contents
(the serialized format was only truncated, emptied and swapped), compiled files
from another ACL2 or host-Lisp version, books in non-ACL2 packages, symlinked or
moved directories, ACL2(p)/ACL2(r), memoize tables across `save-exec`.
`run-matrix.sh` (not edited): its `s3` output list omits `warning!`, which makes
ACL2 inhibit `warning` too, so its "fasl-load fallback warnings" count cannot
become non-zero.
