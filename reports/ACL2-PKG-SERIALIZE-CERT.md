# ACL2 Packages, Reader Macros, `serialize-raw`, and Portcullis / `.cert` / `hcomp` Boundary Audit (Wave-2 Lane D)

**Target:** ACL2 Version 8.7+ (`1d2b39a424eabeab269f189b37c29148d49fc516`)  
**Hosts Verified:** SBCL 2.6.10 (`darwin-arm64`) and Clozure Common Lisp 1.14 (`darwin-arm64`)  
**Fuzzing Harnesses:** `/Users/ember/dev/compiler-audit/hunts/pkg-serial-cert/` (`fuzz_serialize.py`, `fuzz_pkg_reader_cert.py`)  
**Standalone Reproducers:**
- `/Users/ember/dev/compiler-audit/repros/pkg-serial-v1-oob-soundness/`
- `/Users/ember/dev/compiler-audit/repros/pkg-serial-write-sandbox-bypass/`
- `/Users/ember/dev/compiler-audit/repros/pkg-serial-fal-never-desync/`
- `/Users/ember/dev/compiler-audit/repros/pkg-serial-read-object-with-case/`
- `/Users/ember/dev/compiler-audit/repros/pkg-serial-sharp-reader-bugs/`

**Deduplication Notice:** All primary findings below (`PSC-S1`, `PSC-S2`, `PSC-R1`, `PSC-F1`, `PSC-R2`, `PSC-R3`) are disjoint from `ACL2-BUG-REPORT.md` (`S1`–`S7`, `R1`–`R7`, `H1`), `reports/ACL2-BATCH-2.md` (`B2-R1`, `B2-R2`, `B2-S6b`), and `reports/ACL2-XDSMITH-GUARDS.md`. In addition, where our `serialize-read` fast-alist suite (`repros/pkg-serial-fal-never-desync/`) overlaps with `SCR-R1` (`:hons-mode :never` count=0 desync) and `SCR-L4` (`FAL` index `1` = `T`) in `reports/ACL2-STATE-CACHE-RISK.md`, we explicitly mark those sub-items for deduplication and highlight the **4 brand-new fast-alist bugs** uncovered here (`PSC-R1a` normed-spine `BREAK$-RAW` debugger entry on valid `.sao` files, `PSC-R1b` `#Y` reader macro crash on valid atom-only fast alists, `PSC-R1c` `ACL2::NIL` at `arr[2]` leaving `hl-falslot` with `key = NIL` and non-nil `val`, and `PSC-R1d` unvalidated bignum `count` raw error).

---

## 1. Executive Summary

| ID | Severity / Category | Subsystem | Root Cause (`head-worktree`) | Verified Impact (SBCL 2.6.10 & CCL 1.14) | Standalone Reproducer |
|---|---|---|---|---|---|
| **PSC-S1** | **Critical — Memory Safety + Soundness (`NIL` proved, `:ttags nil`, zero `#+`/`#-`)** | `serialize-read` / `#Y` / `#Z` V1 decoder + `include-book` | `ser-decode-from-stream` (`serialize-raw.lisp:1535-1539, 1575`, compiled at `(safety 0)`) sets `arr-size = 0` and `final-obj = -1` when V1 `size/idx = 0`, passing `(= free arr-size)` (`0 = 0`) and executing out-of-bounds `(svref arr -1)` on a 0-element `dynamic-extent` `simple-vector`. In addition, `check-and-translate` (`axioms.lisp:23384`) skips `chk-bad-lisp-object` when `*hcomp-status* = 'include-book`. | **Single-host CCL (`:ttags nil`, zero books):** `(serialize-read "v1-zero.sao")` reads CCL's raw vector header word and returns **`#<BOGUS object @ #xBE>`** into pure `:logic` mode, falsifying ACL2's 5-type universe partition (`consp`, `acl2-numberp`, `symbolp`, `characterp`, `stringp` all `NIL`) and crashing guard-verified `(lexorder val val)` in raw Lisp `SYMBOL-NAME`.<br>**Cross-host SBCL $\to$ CCL (`:ttags nil`, zero `#+`/`#-`):** SBCL reads header word `0` and certifies `(defthm v1z-is-0 (equal (v1z) 0))`; CCL includes `v1_book` without `chk-bad-lisp-object`, evaluates `(v1z)` to `#<BOGUS object @ #xBE>` $\neq 0$, and proves **`(defthm nil-proved nil :rule-classes nil)` Q.E.D.** | `repros/pkg-serial-v1-oob-soundness/` |
| **PSC-S2** | **High — Security / Sandbox & Wormhole Purity Bypass (`:ttags nil`)** | `serialize-write` (`serialize.lisp:37-51`) | Unlike `open-output-channel` (`axioms.lisp:19295-19316`), `serialize-write-fn` requires **no trust tag**, checks neither `*wormholep*` nor `(f-get-global 'writes-okp state)`, and skips `pathname-unix-to-os` (`cbd` resolution), calling Common Lisp `(with-open-file ... :direction :output :if-exists :supersede)` directly. | (a) A guard-verified `:logic`-mode function taking **no `state`** overwrites arbitrary disk files from inside `wormhole` as a side effect of pure `defthm` simplification (`:ttags nil`).<br>(b) `(certify-book ... :ttags nil)` blocks `open-output-channel` (`writes-okp = nil`, requiring `defttag` + `open-output-channel!`) yet allows `serialize-write` inside `make-event` to clobber arbitrary files with `:ttags nil`. | `repros/pkg-serial-write-sandbox-bypass/` |
| **PSC-R1** | **Medium-High — Raw Debugger Break / Abort on Valid Objects & `faltable` Corruption** | `serialize-raw` + `hons-raw` V3 fast-alist restore | (a) **Novel:** `hl-hspace-restore-fal-for-serialize` (`hons-raw.lisp:3236-3239`) treats any existing `faltable` entry for `alist` as fast-alist stealing and invokes `hl-alist-stolen-warning` (`BREAK$-RAW` under default `slow-alist-action = :break`), failing to account for normed-spine fast alists (`EQ` across reads/writes).<br>(b) `#Y` (`ser-cons-reader-macro` $\to$ `:hons-mode :never`) hits the `serialize-raw.lisp:1406-1414` `count = 0` stream desync (cf. `SCR-R1`).<br>(c) **Novel:** `arr[2] = ACL2::NIL` bypasses `index != 0` and leaves `hl-falslot` with `key = NIL` and non-nil `val = #<HASH-TABLE>`; bignum `count` (`2^100`) crashes `make-hash-table` (extending `SCR-L4`). | (a) Writing `(make-fast-alist (hons-copy '((a . 1) (b . 2))))` with `serialize-write` and calling `serialize-read` drops straight into the raw Lisp debugger (`BREAK$-RAW`) on both SBCL and CCL.<br>(b) Printing `(make-fast-alist '(a b))` under `(with-serialize-character #\Y ...)` produces an unreadable file (`Invalid serialized object, magic number incorrect: 0 AC 12 B`).<br>(c) Untrusted `.sao` (`:ttags nil`) violates both `faltable` empty-slot and non-atom-key invariants (`hons-raw.lisp:2758-2765`). | `repros/pkg-serial-fal-never-desync/` |
| **PSC-F1** | **Medium — Functional / Specification Bug** | `read-object-with-case` (`axioms.lisp:18846-18853, 20609`) | `:DOC io` (`doc.lisp:63543-63552`) and `read-object-with-case`'s guard (`(member-eq mode '(:upcase :downcase :preserve :invert))`) specify ANSI CL `readtable-case` semantics, but `axioms.lisp:20609` hardcodes `(set-acl2-readtable-case :preserve)` and `set-acl2-readtable-case` (`axioms.lisp:18846-18853`) has `(declare (ignore mode))` and expands to `'(setf (readtable-case *acl2-readtable*) :preserve)`. | `:downcase` reads `(FOO bar Mixed)` as `(FOO \|bar\| \|Mixed\|)` instead of `(\|foo\| \|bar\| \|mixed\|)`; `:invert` reads `(FOO bar Mixed)` as `(FOO \|bar\| \|Mixed\|)` instead of `(\|foo\| BAR \|Mixed\|)` on both SBCL and CCL. | `repros/pkg-serial-read-object-with-case/` |
| **PSC-R2** | **Medium — Unhandled Raw Lisp Reader Aborts, Silent Bad Parses & `hidden-defpkg` Leak** | `#u`, `#f`, `#!` sharp-macros (`acl2-fns.lisp:1440-1571`) | (a) `sharp-u-read` (`:1461-1488`) checks uppercase `(#\B #\O #\X)` only, ignores `read-from-string`'s 2nd return value (`next-index`), and fails to catch `end-of-file` / `division-by-zero` from `read-from-string`.<br>(b) `sharp-f-read` (`:1521-1571`) never requires `len > 0` mantissa digits.<br>(c) `sharp-bang-read` (`:1450-1453`) uses `assoc` on `known-package-alist` instead of `find-non-hidden-package-entry`. | `#ub1010` fails under `:preserve`; `#u\|42 NOT A NUMERAL\|` silently returns `42`; `#uB_` and `#u1_0/0_0` abort from raw Lisp instead of signaling `acl2-reader-error`; `(#f)`, `(#f-)`, `(#f.)`, `(#fx)` silently read as `(0)`; `#!SECRET-HIDDEN-PKG` succeeds even when `SECRET-HIDDEN-PKG` is a `hidden-defpkg` from a `(local (include-book ...))`. | `repros/pkg-serial-sharp-reader-bugs/` |
| **PSC-R3** | **Low-Medium — Host Raw Stack Overflow (CCL arm64)** | `ser-make-array-wrapper` (`serialize-raw.lisp:1510-1516, 1541, 1548`) | `ser-decode-from-stream` checks `(typep arr-size 'fixnum)` (`2^60 - 1` max on 64-bit Lisps) and stack-allocates `arr` via `(declare (dynamic-extent arr decoder))`. `ser-make-array-wrapper` has `#+sbcl (declare (optimize (safety 3)))` (catching heap/array-dimension limits cleanly on SBCL) but leaves CCL at `(safety 0)`. | On CCL 1.14 arm64, `(serialize-read ...)` on a 20-byte `.sao` header with `size/idx = 2^57` overflows the raw thread stack (`ABORTING from raw Lisp`) instead of signaling `"Serialized object is too large."` | `hunts/pkg-serial-cert/fuzz_serialize.py` (`ccl_stack_overflow_array_2_57`) |

---

## 2. Systematic Audit Coverage Matrix

| Mission Target | Source Files Audited (`head-worktree`) | Mechanisms & Invariants Checked | Audit Outcome |
|---|---|---|---|
| **1. Packages, Imports, Locks & Portcullis / `.cert` / `hcomp` Symbol Identity** | `defpkgs.lisp` (1–779), `acl2-check.lisp` (1–401), `acl2.lisp` (1–1600, 2100–2600), `other-events.lisp` (1425–1860, 8500–8650, 10440–11420, 12290–12360, 17805–17925, 34680–34950), `axioms.lisp` (1175–1245, 3090–3200, 5430–5775, 23180–23430), `rewrite.lisp` (12775–12815) | `*common-lisp-symbols-from-main-lisp-package*` / `*acl2-exports*`; `defpkg-raw1` symbol-sharing & CL shadow checks; `hidden-defpkg` recording in `.cert` portcullis & `chk-package-reincarnation-import-restrictions` across multi-book `local` `include-book` diamonds; `intern-in-package-of-symbol` raw CL vs logical `member-symbol-name` congruence (`symbol-package-name`, `pkg-imports`, `bad-lisp-objectp` rejection of `COMMON-LISP` non-ACL2 symbols); `acl2-input-channel-package` across `ld`; SBCL package locks; `*1*` raw function binding & `chk-bad-lisp-object` skip under `*hcomp-status* = 'include-book` | **2 Bugs Found:** (1) `chk-bad-lisp-object` skip during `*hcomp-status* = 'include-book` (`axioms.lisp:23384`) enables full `NIL` proof escalation in **PSC-S1** when combined with `#Y` V1 OOB; (2) `sharp-bang-read` ignores `package-entry-hiddenp` (**PSC-R2c**).<br>**Verified Sound:** `defpkg-raw1` + `chk-package-reincarnation-import-restrictions` soundly block `PKG::SYM` dual-CL-symbol reincarnation splits across portcullis, `local` sub-books, and compiled `.fasl`/`hcomp` files; `bad-lisp-objectp` soundly rejects `COMMON-LISP::EVAL` and unexported CL symbols (`acl2-symbolp` check). |
| **2. ACL2 Reader (`read-object`, `read-object-with-case`, Sharp-Macros, Cert vs CL `.fasl` Reader)** | `acl2-fns.lisp` (900–1750, 2050–2300), `axioms.lisp` (18830–18920, 20450–20635), `interface-raw.lisp` (5000–5850), `acl2.lisp` (2150–2550), `doc.lisp` (63520–63610) | `*acl2-readtable*` dispatch table (`acl2.lisp:2230-2380`): `#.` disabled (`error`), `#+`/`#-` disabled in `*acl2-readtable*` (only active when host readtable leaks or via `read-object$`), `#!`, `#u`, `#b`/`#o`/`#x`, `#c`, `#f`, `#d`, `#{"""..."""}`, `#\...` (`*acl2-character-alist*`: `Newline`, `Space`, `Page`, `Rubout`, `Tab`, `Backspace`, `Return`, 2-hex `#\xXX` rejected unless standard name), `#Y`/`#Z`; `read-object-with-case`; `read-object-suppress` | **2 Bug Groups Found:** **PSC-F1** (`read-object-with-case` ignores `:downcase` & `:invert`) and **PSC-R2** (`#u`, `#f`, `#!` defects).<br>**Verified Sound:** `#.`, `#A`, `#S`, `#P`, `#=`, `##` are properly rejected in `*acl2-readtable*`; `#\{"""..."""}` fancy string reader cleanly handles EOF and delimiter boundaries; `*acl2-character-alist*` enforces cross-host portable character names (`code-char 0..255`). |
| **3. `serialize-write` / `serialize-read` (`serialize.lisp`, `serialize-raw.lisp`, `hons-raw.lisp`)** | `serialize.lisp` (1–105), `serialize-raw.lisp` (1–1575), `hons-raw.lisp` (800–4395) | Trust-tag requirements (**none** for either `serialize-read` or `serialize-write`!); V1/V2/V3 header & trailer magic; `size/idx`, `arr-size`, `final-obj`, `free` bounds at `(safety 0)`; `ser-decode-nat` bignum handling; rational `den = 0`, `gcd != 1`, negative zero, `sign > 1`; complex `imag = 0` canonicalization; 8-bit ISO-8859-1 character stream encoding; string norming under `:smart`/`:always`/`:never` (`hons-equal` equivalence); `ser-decode-and-load-packages` (`check-packagesp = t` vs `nil`, `ACL2_INVISIBLE`, `KEYWORD`, `COMMON-LISP`); `ser-decode-loop` DAG `(< car-index free)` / `(< cdr-index free)` acyclicity; V3 `FAL` restore & `faltable` invariants; output channel / wormhole / `writes-okp` sandbox rules | **4 Bug Groups Found:** **PSC-S1** (V1 `size/idx=0` `(svref arr -1)` OOB memory read + `NIL` proof), **PSC-S2** (`serialize-write` wormhole & `writes-okp` sandbox bypass), **PSC-R1** (normed-spine `BREAK$-RAW`, `#Y` atom-only FAL crash, `ACL2::NIL`/atom `faltable` corruption, bignum `count`), and **PSC-R3** (CCL `2^57` stack array overflow).<br>**Verified Sound:** Rational/complex decoders normalize `2/4 -> 1/2`, `-0/5 -> 0`, `#c(3 0) -> 3`, and error cleanly on `den = 0` or `sign > 1`; `ser-decode-loop` enforces strict topological index ordering (`< car-index free`, `< cdr-index free`), preventing cyclic conses; `:df` IEEE-754 floats cannot be passed to polymorphic `serialize-write` and have no tag in V1/V2/V3; cross-host SBCL $\leftrightarrow$ CCL `.sao` files are bit-for-bit compatible on valid non-empty-FAL objects. |
| **4. Automated Fuzzing Harnesses** | `hunts/pkg-serial-cert/fuzz_serialize.py`, `hunts/pkg-serial-cert/fuzz_pkg_reader_cert.py` | Grammar-based + mutation-based V1/V2/V3 `.sao` fuzzer (87 adversarial streams + 12 multi-type cross-host round-trip families $\times$ 5 read modes + 3 isolated stress checks); differential `read-object-with-case` fuzzer, sharp-macro fuzzer, and multi-book portcullis/`hidden-defpkg` fuzzer | Executed cleanly with `/opt/homebrew/bin/timeout` on both SBCL 2.6.10 and CCL 1.14; automatically reproduced **PSC-S1**, **PSC-R1**, **PSC-F1**, **PSC-R2**, and **PSC-R3** (saved in `fuzz_serialize_results.json` and `fuzz_pkg_reader_results.json`). |

---

## 3. Detailed Findings, Root-Cause Analysis, and Patches

### PSC-S1 [CRITICAL — Soundness & Raw Memory Safety]: Out-of-Bounds `(svref arr -1)` at `(safety 0)` in `ser-decode-from-stream` + `chk-bad-lisp-object` Bypass in `include-book` Proves `NIL` (`:ttags nil`, Zero `#+`/`#-`)

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/pkg-serial-v1-oob-soundness/` (`repro.lisp`, `run.sh`)
- **Affected Files:**
  - `serialize.lisp:64-88` (`serialize-read-fn` — `:logic` mode, **no trust tag required**)
  - `acl2-fns.lisp:2161-2165` (`#Y` / `#Z` installed in `*acl2-readtable*` — **no trust tag required**)
  - `serialize-raw.lisp:1527-1575` (`ser-decode-from-stream`, compiled with `*Step-1-compile-decl*` at `(safety 0)`)
  - `axioms.lisp:23381-23390` (`check-and-translate` skips `chk-bad-lisp-object` when `(eq *hcomp-status* 'include-book)`)

#### Root Cause

In `serialize-raw.lisp:1527-1548`, `ser-decode-from-stream` computes `arr-size` and `final-obj` from the decoded `version` and `size/idx`:

```lisp
  (let* ((version  (ser-decode-magic stream))
         (size/idx (ser-decode-nat stream))
         (arr-size (if (or (eq version :v2)
                           (eq version :v3))
                       (cond ((eq size/idx 0)
                              2)
                             (t
                              (+ size/idx 1)))
                     size/idx))
         (final-obj (if (or (eq version :v2)
                            (eq version :v3))
                        size/idx
                      (- arr-size 1))))

    (unless (typep arr-size 'fixnum)
      (error "Serialized object is too large."))

    (let* ((arr     (ser-make-array-wrapper arr-size))
           (decoder (make-ser-decoder :array arr
                                      :free 0
                                      :version version)))
      (declare (dynamic-extent arr decoder)
               (type ser-decoder decoder))
```

For V2 and V3 (`#xAC120BC8`, `#xAC120BC9`), `size/idx = 0` maps to `arr-size = 2` (`arr[0] = nil, arr[1] = t`) and `final-obj = 0`.  
For **V1 (`#xAC120BC7`)**, however, **there is no lower-bound check `(>= size/idx 1)`**! When a 13-byte V1 payload specifies `size/idx = 0` followed by seven `0` counts for `nats`, `rats`, `complexes`, `chars`, `strs`, `pkgs`, `conses` and the 4-byte V1 trailer:

```
AC 12 0B C7   00   00 00 00 00 00 00 00   AC 12 0B C7
```

1. `arr-size = 0`, `final-obj = (- 0 1) = -1`.
2. `(ser-make-array-wrapper 0)` allocates a 0-element `simple-vector` on the stack (`dynamic-extent`).
3. All 7 atom/cons section counts are `0`, leaving `(ser-decoder-free decoder) = 0`.
4. Line `1568` checks `(= (ser-decoder-free decoder) arr-size)` $\implies$ `(= 0 0)` $\implies$ **`T`**!
5. Line `1575` executes **`(svref arr -1)` at `(safety 0)`**, performing an unchecked out-of-bounds read 8 bytes *before* element 0 of `arr` (its raw Lisp object header word)!

#### Verified Impact 1: Single-Host CCL Universe-Partition Violation & Guard-Verified Crash (Zero Books, `:ttags nil`)

On Clozure CL 1.14 (`darwin-arm64`), a `simple-vector` header word at offset `-8` from element 0 has tag/subtag `0xBE` (`subtag-simple-vector`). Reading `arr[-1]` at `(safety 0)` fabricates the raw Lisp immediate **`#<BOGUS object @ #xBE>`** and returns it directly from `(serialize-read "v1-zero.sao")` into pure `:logic`-mode ACL2 without any trust tag:

- `(consp val)` $\to$ `NIL`
- `(acl2-numberp val)` $\to$ `NIL`
- `(symbolp val)` $\to$ `NIL`
- `(characterp val)` $\to$ `NIL`
- `(stringp val)` $\to$ `NIL`

Every ACL2 object satisfies `(or (consp x) (acl2-numberp x) (symbolp x) (characterp x) (stringp x))` in the logic, yet `val` falsifies all five predicates! Passing `val` to guard-verified `:logic`-mode `(lexorder val val)` (`:guard t`, proved reflexive theorem `(lexorder x x)`) enters `alphorder`, which assumes any non-number, non-character, non-string atom must be a `symbol` and calls `(symbol-name val)`, crashing in raw Lisp:
```
Error: The value #<BOGUS object @ #xBE> is not of the expected type SYMBOL.
```

#### Verified Impact 2: Full `(defthm nil-proved nil)` Soundness Proof (Zero `#+`/`#-` Reader Conditionals, `:ttags nil`)

Unlike Bug `S2` (`cross-host-reader-conditional`, which relies on `#+sbcl`/`#+ccl`), `#Y` is an official ACL2 reader macro enabled in `*acl2-readtable*` (`acl2-fns.lisp:2161-2165`) specifically designed for portable serialized constants in books and `.cert` files:

1. On **SBCL 2.6.10 (`arm64`)**, a 0-element `simple-vector` stores its boxed fixnum length `0` (`0x0000000000000000`) immediately preceding element 0, so `(svref arr -1)` at `(safety 0)` deterministically returns fixnum **`0`**! Thus `v1_book.lisp`:
   ```lisp
   (in-package "ACL2")
   (defun v1z () '#Y<13-byte-v1-zero>)
   (defthm v1z-is-0 (equal (v1z) 0) :rule-classes nil)
   ```
   certifies cleanly via `(certify-book "v1_book" 0 t :ttags nil)` with zero warnings and zero reader conditionals (`v1_book.cert` stores the portcullis/checksums; `v1_book.lisp` itself has no `#+`/`#-`).
2. On **CCL 1.14 (`arm64`)**, `(include-book "v1_book" :ttags nil)` reads `v1_book.lisp` using `*acl2-readtable*`, so `#Y<13-byte-v1-zero>` decodes to `#<BOGUS object @ #xBE>`. Normally `translate` calls `chk-bad-lisp-object` on quoted constants, which would catch `#<BOGUS object @ #xBE>` (`bad-lisp-objectp` $\to$ `T`). **However**, `axioms.lisp:23384` explicitly bypasses `chk-bad-lisp-object` during `include-book`:
   ```lisp
   ((and (not (eq *hcomp-status* 'include-book)) ; optimization
         (chk-bad-lisp-object x))
    ...)
   ```
   Consequently, CCL installs the executable counterpart `*1*v1z` returning `#<BOGUS object @ #xBE>` while importing the certified theorem `v1z-is-0: (equal (v1z) 0)`!
3. Next, `(defthm v1z-not-0 (not (equal (v1z) 0)) :rule-classes nil)` evaluates `(equal #<BOGUS object @ #xBE> 0)` $\to$ `NIL`, `(not NIL)` $\to$ `T`, proving `(not (equal (v1z) 0))` by `:executable-counterpart`!
4. Combining `v1z-is-0` and `v1z-not-0` proves **`(defthm nil-proved nil :rule-classes nil)` Q.E.D.** with `(global-val 'ttags-seen (w state)) = NIL`!

#### Minimal Patch

In `serialize-raw.lisp:1528-1542`, reject `size/idx = 0` for V1 before computing `final-obj`:
```lisp
         (version  (ser-decode-magic stream))
         (size/idx (ser-decode-nat stream))
         (_        (when (and (eq version :v1) (eql size/idx 0))
                     (error "Invalid V1 serialized object: size/idx cannot be 0.")))
```
And as defense-in-depth in `serialize.lisp:87`, assert `(when (bad-lisp-objectp val) (error ...))` before returning `val` from `serialize-read-fn`.

---

### PSC-S2 [HIGH — Security / Sandbox & Wormhole Purity Bypass]: `serialize-write` Bypasses `*wormholep*`, `writes-okp`, and `cbd` Path Resolution Without Any Trust Tag

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/pkg-serial-write-sandbox-bypass/` (`repro.lisp`, `run.sh`)
- **Affected File:** `serialize.lisp:34-51` (`serialize-write`, `serialize-write-fn`)

#### Root Cause

ACL2's standard file-output primitive `open-output-channel` (`axioms.lisp:19295-19323`) enforces three core sandbox and purity invariants:
1. **Wormhole purity (`*wormholep*`):** Wormholes execute inside pure `:logic` functions taking **no `state`**. Allowing disk writes inside a wormhole lets pure proof simplification mutate external files, so `open-output-channel` calls `(wormhole-er 'open-output-channel ...)`.
2. **Untrusted book certification (`writes-okp`):** During `certify-book`, `make-event`, and clause-processor execution, `(f-get-global 'writes-okp state)` is bound to `nil` so certifying an untrusted `:ttags nil` book cannot overwrite arbitrary user files (`~/.ssh/...`, `.cert` files, etc.); writing requires an active trust tag (`defttag`) and `open-output-channel!`.
3. **Connected book directory (`cbd`):** Relative filenames are resolved via `(pathname-unix-to-os fname state)` relative to `(cbd)`.

By contrast, `serialize-write-fn` (`serialize.lisp:37-51`) requires **no trust tag** and bypasses all three:
```lisp
(defun serialize-write-fn (filename obj verbosep state)
  (declare (xargs :guard (and (stringp filename)
                              (booleanp verbosep))
                  :stobjs state)
           (ignorable filename obj verbosep))
  #-acl2-loop-only
  (cond
   ((live-state-p state)
    (with-open-file
     (stream filename
             :direction :output
             :if-exists :supersede)
     (let* ((*ser-verbose* verbosep))
       (ser-encode-to-stream obj stream)))
    (return-from serialize-write-fn state))
   ...))
```

#### Verified Impact (Both SBCL 2.6.10 & CCL 1.14)

1. **State-free `:logic` disk write during `defthm`:** `repro.lisp` defines a guard-verified `:logic` function `(defun pure-state-free-fn (x) (declare (xargs :guard t)) ...)` that enters a `wormhole` and calls `(serialize-write "wormhole_pwned.sao" '(:written-from-wormhole))`. Proving `(defthm pure-proof-triggers-disk-write (equal (pure-state-free-fn 42) 42))` simplifies `(pure-state-free-fn 42)` and creates `wormhole_pwned.sao` on disk with `ttags = NIL`!
2. **`certify-book` (`:ttags nil`) file-write sandbox bypass:** `run.sh` shows `(certify-book "blocked_book" 0 t :ttags nil)` aborts when `make-event` calls `open-output-channel`, whereas `(certify-book "wb_book" 0 t :ttags nil)` succeeds with `writes-okp = NIL` and `ttags = NIL`, creating `cert_bypassed.sao` on disk!

#### Minimal Patch

In `serialize.lisp:44-51`, enforce the exact same `*wormholep*`, `writes-okp`, and `pathname-unix-to-os` checks as `open-output-channel` (and provide `serialize-write!` gated by an active `ttag` if book-certification writes are desired):
```lisp
   ((live-state-p state)
    (when *wormholep*
      (wormhole-er 'serialize-write nil))
    (when (null (f-get-global 'writes-okp state))
      (er hard? 'serialize-write
          "File writing via SERIALIZE-WRITE is not permitted in this context ~
           (WRITES-OKP is NIL)."))
    (let ((os-fname (pathname-unix-to-os filename state)))
      (with-open-file (stream os-fname :direction :output :if-exists :supersede)
        ...)))
```

---

### PSC-R1 [MEDIUM-HIGH — Raw Lisp Break / Abort on Valid Objects & `faltable` Corruption]: Fast-Alist Deserialization Defects in `serialize-raw.lisp` and `hons-raw.lisp`

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/pkg-serial-fal-never-desync/` (`repro.lisp`, `run.sh`)
- **Affected Files:** `hons-raw.lisp:3197-3240`, `serialize-raw.lisp:1400-1414`

#### Sub-Bugs & Deduplication Note

1. **PSC-R1a [100% Novel — Valid Object Triggers Raw `BREAK$-RAW`]:** In `hons-raw.lisp:3231-3240`:
   ```lisp
   (let* ((faltable  (hl-hspace-faltable hs))
          (slot      (hl-faltable-general-lookup alist faltable))
          (new-ht    (hl-mht :size (max 60 count))))
     (hl-check-alist-for-serialize-restore alist hs)
     (hl-make-fast-alist-put-pairs alist new-ht)
     (when (hl-falslot-val slot)
       ;; BOZO how much of an error is this?  Do we want to warn about it?
       (hl-alist-stolen-warning 'hl-hspace-restore-fal-for-serialize))
     (setf (hl-falslot-val slot) new-ht)
     (setf (hl-falslot-key slot) alist))
   ```
   Compare `hl-hspace-make-fast-alist` (`hons-raw.lisp:2930-2932`), which immediately returns `alist` if `(hl-falslot-val slot)` is already non-nil! Whenever a valid fast alist has a **normed spine** — e.g., `(make-fast-alist (hons-copy '((a . 1) (b . 2))))` — its cons cells are normed (`honsp = t`). Deserializing that `.sao` file in the same session that wrote it, or reading it twice in any session, or reading **any** fast alist twice with `:hons-mode :always`, or including two `.cert` files whose `make-event` expansions `#Z`-encoded the same normed fast alist reconstructs the **identical `EQ` hons cell** `alist`. `(hl-falslot-val slot)` is therefore already non-nil, and `hl-alist-stolen-warning` fires — which under ACL2's **default** `slow-alist-action` (`:break`) calls `BREAK$-RAW` (`(break)`), dropping the user out of ACL2 into the raw Common Lisp debugger!
2. **PSC-R1b [`#Y` Reader Macro Extension of `SCR-R1`]:** As noted in `SCR-R1` (`ACL2-STATE-CACHE-RISK.md`), `ser-decode-and-restore-fals` (`serialize-raw.lisp:1406-1414`) skips `(ser-decode-nat stream)` for `count` when `(eq hons-mode :never)`, letting the next loop iteration treat `count` as `index`. In addition to `(serialize-read ... :hons-mode :never)`, **`#Y` (`ser-cons-reader-macro` in `acl2-fns.lisp:2135-2142`) unconditionally passes `hons-mode = :never`**. Consequently, printing a valid atom-only fast alist `(make-fast-alist '(only-atom-1 only-atom-2))` via `print-object$` under `(with-serialize-character #\Y ...)` writes `count = 0` and produces an unreadable file that aborts `read-object` in raw Lisp with `Invalid serialized object, magic number incorrect: 0 AC 12 B`! (Conversely, if a crafted `.sao` has `count >= arr-size`, `:hons-mode :never` aborts with `FAL index to restore is too large!`.)
3. **PSC-R1c [Novel Extension of `SCR-L4` — `ACL2::NIL` Corrupts Empty-Slot Invariant]:** `ser-decode-and-restore-fals` terminates on `index = 0` (assuming `NIL` can only appear at `arr[0]`), and `hl-check-alist-for-serialize-restore` (`hons-raw.lisp:3202`) immediately returns `nil` on `(atom alist)` without signaling an error!
   - When `index = 1` (`arr[1] = T`) or `arr[2] = 42`, `T` or `42` is bound in `faltable` (violating Fast Alist Invariant 1, `hons-raw.lisp:2758`: *"Atoms are never bound in the FALTABLE"*).
   - **Even worse**, when a crafted V3 `.sao` encodes symbol `"NIL"` in package `"ACL2"` at `arr[2]` and specifies FAL `(index = 2, count = 5)`, `index = 2 != 0` passes the loop guard while `(svref array 2)` is **`NIL`**! `hl-hspace-restore-fal-for-serialize` then sets `(hl-falslot-val slot)` to `#<HASH-TABLE>` and `(hl-falslot-key slot)` to **`NIL`**, directly violating the `hl-falslot` representation invariant (`hons-raw.lisp:2760-2765`: an empty slot is identified by `key = NIL`, with `val = NIL`)!
4. **PSC-R1d [Novel — Bignum `count` Raw Error]:** `count` is decoded with `ser-decode-nat` (arbitrary-precision natural) and passed straight to `(hl-mht :size (max 60 count))` without checking `(typep count 'fixnum)`, triggering an unhandled raw Lisp error when `count = 2^100`.

#### Minimal Patch

1. In `serialize-raw.lisp:1406-1414`, always consume `count` from `stream` regardless of `hons-mode`, and validate `(consp alist)` and `(typep count '(integer 0 #.(expt 2 28)))`:
   ```lisp
   (let ((count (ser-decode-nat stream)))
     (unless (eq hons-mode :never)
       (let ((alist (svref array index)))
         (unless (consp alist)
           (error "Invalid serialized FAL: non-cons at index ~a." index))
         (unless (typep count '(integer 0 #.(expt 2 28)))
           (error "Invalid serialized FAL count: ~a." count))
         (hl-restore-fal-for-serialize alist count))))
   ```
2. In `hons-raw.lisp:3231-3240`, match `hl-hspace-make-fast-alist` (`:2930-2932`): if `(hl-falslot-val slot)` is already non-nil (for an already-normed `alist`), simply keep the existing backing hash table instead of calling `hl-alist-stolen-warning`!

---

### PSC-F1 [MEDIUM — Functional / Spec Bug]: `read-object-with-case` Completely Ignores `:downcase` and `:invert` Modes

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/pkg-serial-read-object-with-case/` (`repro.lisp`, `run.sh`)
- **Affected Files:** `axioms.lisp:18846-18853`, `axioms.lisp:20587-20612`, `doc.lisp:63543-63552`

#### Root Cause

Both `:DOC io` (`doc.lisp:63543-63552`) and the guard of `read-object-with-case` (`axioms.lisp:20589-20590`) specify four ANSI Common Lisp `readtable-case` modes `(:upcase :downcase :preserve :invert)`:

```lisp
(defun read-object-with-case (channel mode state)
  (declare (xargs :guard (and (symbolp channel)
                              (open-input-channel-p channel :object state)
                              (member-eq mode '(:upcase :downcase :preserve :invert)))))
```

However, there is a **double hardcoding of `:preserve`** in `axioms.lisp`:
1. At `axioms.lisp:20605-20610`:
   ```lisp
   (cond ((eq mode :upcase)
          (read-object channel state))
         (t (prog2$ (set-acl2-readtable-case :preserve)
                    (read-object-with-case1 channel state))))
   ```
   Every non-`:upcase` value of `mode` (`:downcase`, `:preserve`, `:invert`) passes literal `:preserve` to `set-acl2-readtable-case`!
2. At `axioms.lisp:18846-18853`:
   ```lisp
   (defmacro set-acl2-readtable-case (mode)
     (declare (xargs :guard (member-eq mode '(:upcase :downcase :preserve :invert)))
              (ignore mode))
     #-acl2-loop-only
     '(progn (setf (readtable-case *acl2-readtable*) :preserve)
             nil)
     #+acl2-loop-only
     nil)
   ```
   `set-acl2-readtable-case` itself has `(declare (ignore mode))` and hardcodes `:preserve`!

#### Verified Impact (Both SBCL 2.6.10 & CCL 1.14)

Reading `"(FOO bar Mixed)"` via `(read-object-with-case ch mode state)`:
- `:upcase` $\to$ `(FOO BAR MIXED)` (correct)
- `:preserve` $\to$ `(FOO |bar| |Mixed|)` (correct)
- `:downcase` $\to$ `(FOO |bar| |Mixed|)` (**BUG**: expected `(|foo| |bar| |mixed|)`)
- `:invert` $\to$ `(FOO |bar| |Mixed|)` (**BUG**: expected `(|foo| BAR |Mixed|)`)

#### Minimal Patch

Pass `mode` in `axioms.lisp:20609` (`(set-acl2-readtable-case mode)`) and un-ignore `mode` in `axioms.lisp:18846-18853`:
```lisp
(defmacro set-acl2-readtable-case (mode)
  (declare (xargs :guard (member-eq mode '(:upcase :downcase :preserve :invert))))
  #-acl2-loop-only
  `(progn (setf (readtable-case *acl2-readtable*) ,mode)
          nil)
  #+acl2-loop-only
  (declare (ignore mode))
  #+acl2-loop-only
  nil)
```

---

### PSC-R2 [MEDIUM — Reader Robustness & Package Visibility Bugs]: Defects in `#u`, `#f`, and `#!` Sharp-Macros

- **Reproducer:** `/Users/ember/dev/compiler-audit/repros/pkg-serial-sharp-reader-bugs/` (`repro.lisp`, `run.sh`)
- **Affected File:** `acl2-fns.lisp:1440-1571`

#### Root Causes & Verified Behaviors

1. **`sharp-u-read` (`acl2-fns.lisp:1461-1488`):**
   - **Case-sensitivity bug (`:1468`):** `(member c '(#\B #\O #\X))` checks only uppercase radix letters after calling `read-symbol-name-preserving-case`. Under `(read-object-with-case ch :preserve state)`, `#ub1010` fails to match `#\B`, falls through to the decimal branch, calls `(read-from-string "b1010")`, gets the symbol `|b1010|`, and aborts with `HARD ACL2 ERROR in ACL2-READER: Failure to read #u expression: result |b1010| is not a numeral.`
   - **Silent trailing-garbage acceptance (`:1467-1488`):** `sharp-u-read` calls `(read-symbol-name-preserving-case stream)`, which allows vertical-bar escapes (`|...|`), strips `_`, and calls `(read-from-string s)` while discarding its second return value (`next-index`). Thus `#u|42 NOT A NUMERAL|` silently reads as **`42`**, and `#u|X10 NOT HEX|` silently reads as **`16`**!
   - **Unhandled raw Lisp `END-OF-FILE` and `DIVISION-BY-ZERO` (`:1476, :1480`):** `#uB_` (or `#uO_`, `#uX_`) strips `_` to `"#B"` and calls `(read-from-string "#B")` without `handler-case`, aborting from raw Lisp (`END-OF-FILE` / reader error) instead of calling `acl2-reader-error`. Similarly, `#u1_0/0_0` strips `_` to `"10/00"` and triggers an unhandled raw Lisp `DIVISION-BY-ZERO` / `READER-ERROR`.

2. **`sharp-f-read` (`acl2-fns.lisp:1521-1571`):**
   - `sharp-f-read` initializes `mantissa = 0, len = 0`, reads an optional sign, optional digits, optional `.` + fractional digits, and optional `e`/`d`/etc. exponent — **never checking that at least one digit was actually consumed (`(> len 0)`)**! Consequently, degenerate inputs `(#f)`, `(#f-)`, `(#f.)`, and `(#fx)` all silently parse as `(0)`.

3. **`sharp-bang-read` (`acl2-fns.lisp:1450-1453`):**
   - When reading `#!PKG expr`, line `1450` checks:
     ```lisp
     (assoc package-string (known-package-alist *the-live-state*) :test 'equal)
     ```
     However, `known-package-alist` ALSO contains **hidden packages** (`package-entry-hiddenp` = `T`, i.e., `cadr` = `(NIL T)` or similar hidden flag) introduced only inside `(local (include-book ...))` (`hidden-defpkg`). Everywhere else in ACL2 (`in-package`, `defpkg`, `certify-book`), hidden packages are filtered via `find-non-hidden-package-entry` so they remain invisible in the logical world. Because `sharp-bang-read` uses raw `assoc`, `#!SECRET-HIDDEN-PKG (1 2 3)` succeeds even though `(in-package "SECRET-HIDDEN-PKG")` is rejected as unknown!

#### Minimal Patch

- In `sharp-u-read`: check `(member (char-upcase c) '(#\B #\O #\X))`; reject `|`/`\` escapes (or check `(= next-index (length str))` from `multiple-value-bind (result next-index) (read-from-string ...)` and verify every character is a valid digit/radix/`/`/`+`/`-`/`_`); and wrap `read-from-string` in `(handler-case ... (error (c) (acl2-reader-error ...)))`.
- In `sharp-f-read`: track `saw-digit-p` across integer and fractional digit loops and call `(acl2-reader-error ...)` unless `saw-digit-p` is true.
- In `sharp-bang-read`: replace `(assoc package-string (known-package-alist *the-live-state*) :test 'equal)` with `(find-non-hidden-package-entry package-string (known-package-alist *the-live-state*))`.

---

### PSC-R3 [LOW-MEDIUM — Host Raw Stack Overflow on CCL arm64]: Missing `(safety 3)` & Array Upper Bound in `ser-make-array-wrapper`

- **Fuzzer Check:** `/Users/ember/dev/compiler-audit/hunts/pkg-serial-cert/fuzz_serialize.py` (`ccl_stack_overflow_array_2_57`)
- **Affected File:** `serialize-raw.lisp:1510-1516, 1541-1548`

#### Root Cause

In `serialize-raw.lisp:1510-1516, 1541-1548`:
```lisp
(defun ser-make-array-wrapper (size)
; Sol Swords reported in July 2017 that with SBCL, he has provided the
; following safety-3 wrapper to avoid some crashes in ser-decode-from-stream.
  #+sbcl (declare (optimize (safety 3)))
  (make-array size))
...
    (unless (typep arr-size 'fixnum)
      (error "Serialized object is too large."))

    (let* ((arr     (ser-make-array-wrapper arr-size))
           ...)
      (declare (dynamic-extent arr decoder) ...)
```
On 64-bit CCL (`darwin-arm64`), `most-positive-fixnum` is $2^{60} - 1$, whereas `array-total-size-limit` is $2^{56}$ and `arr` is declared `dynamic-extent` while `serialize-raw.lisp` is compiled at `(safety 0)`. A 20-byte `.sao` file with `size/idx = 2^{57}` passes `(typep arr-size 'fixnum)` and attempts raw stack allocation at `(safety 0)` on CCL, overflowing the thread stack (`ABORTING from raw Lisp`) instead of signaling `"Serialized object is too large."` (or remove `dynamic-extent` on `arr` for large `arr-size` and check `(< arr-size array-dimension-limit)` + `(declare (optimize (safety 3)))` unconditionally on all hosts, not just `#+sbcl`).

---

## 4. Automated Fuzzing Harnesses & Results Summary

Both harnesses live in `/Users/ember/dev/compiler-audit/hunts/pkg-serial-cert/` and run cleanly under `/opt/homebrew/bin/timeout --kill-after=10s 120s` on SBCL 2.6.10 and CCL 1.14:

1. **`fuzz_serialize.py`** (`fuzz_serialize_results.json`):
   - **Part A (12 edge-case object families $\times$ 2 writers [SBCL, CCL] $\times$ 2 readers [SBCL, CCL] $\times$ 5 read paths [`:smart`, `:always`, `:never`, `#Y`, `#Z`] = 180 round-trip checks):**
     - Verified cross-host bit-level compatibility for bignums, rationals, complexes, `0..255` chars, normed/unnormed strings, multi-package symbols, shadowed fast alists, improper fast alists, and shared Hons DAGs.
     - Automatically flagged **6 failures** on `fal-only-atoms` across `:never` and `#Y` on both SBCL and CCL (**PSC-R1b** / `SCR-R1`).
   - **Part B (87 adversarial & byte-mutated V1/V2/V3 `.sao` files $\times$ 2 hosts = 400+ untrusted `serialize-read` executions):**
     - Automatically flagged **3 universe-partition violations** (`universe-ok=NIL`) on CCL for `v1_size0_oob` across `:smart`, `:always`, and `:never` (**PSC-S1**).
     - Automatically flagged **12 `faltable` structural invariant violations** across SBCL and CCL for `v3_fal_atom_t`, `v3_fal_atom_int42`, and `v3_fal_atom_nil_via_pkg` (`:SLOT1-NIL-KEY-HAS-VAL`, `:SLOT1-ATOM-KEY`, `:SLOT2-ATOM-KEY` — **PSC-R1c**).
   - **Isolated Checks:** Confirmed `triggered_break_raw = true` on both SBCL and CCL for normed-spine fast alists (**PSC-R1a**), raw Lisp errors on `count = 2^100` (**PSC-R1d**), and CCL raw stack abort on `size/idx = 2^57` (**PSC-R3**).

2. **`fuzz_pkg_reader_cert.py`** (`fuzz_pkg_reader_results.json`):
   - **Part A (`read-object-with-case` differential fuzzer):** Caught **14 case-conversion mismatches** across `:downcase` and `:invert` on SBCL and CCL (**PSC-F1**).
   - **Part B (Sharp-macro boundary fuzzer):** Caught **28 anomalies** across `#u` (`#ub1010` `:preserve` failure, `#u|42 JUNK|` trailing garbage, `#uB_` / `#uO_` / `#uX_` / `#u1_0/0_0` raw Lisp aborts) and `#f` (`(#f)`, `(#f-)`, `(#f.)`, `(#fx)` reading as `(0)`) (**PSC-R2a,b**).
   - **Part C (Portcullis / `hidden-defpkg` / reincarnation fuzzer):** Confirmed `defpkg-raw1` and `chk-package-reincarnation-import-restrictions` block incompatible package reincarnation, and caught **2 visibility leaks** where `#!HIDDEN-PKG-FUZZ` succeeded on a `hidden-defpkg` (**PSC-R2c**).

---

## 5. One-Command Reproduction

Each standalone reproducer executes on both SBCL (`head-worktree/saved_acl2`) and CCL (`ccl-worktree/saved_acl2`), wraps every ACL2 invocation in `/opt/homebrew/bin/timeout --kill-after=10s 120s`, exits `0` upon verifying all expected markers, and cleans up all temporary files via `trap cleanup EXIT`:

```bash
/Users/ember/dev/compiler-audit/repros/pkg-serial-v1-oob-soundness/run.sh
/Users/ember/dev/compiler-audit/repros/pkg-serial-write-sandbox-bypass/run.sh
/Users/ember/dev/compiler-audit/repros/pkg-serial-fal-never-desync/run.sh
/Users/ember/dev/compiler-audit/repros/pkg-serial-read-object-with-case/run.sh
/Users/ember/dev/compiler-audit/repros/pkg-serial-sharp-reader-bugs/run.sh
```
