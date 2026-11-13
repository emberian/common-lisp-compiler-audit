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
