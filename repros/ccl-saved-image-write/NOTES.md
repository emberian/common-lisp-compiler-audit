# CCL darwinarm64: saved image livelocks on an inline store into a purified vector

Machine: macOS arm64 (16K pages), CCL 1.14 darwinarm64 at `/Users/ember/dev/ccl` (HEAD `23c9edcf`),
ACL2 8.7+ (`1d2b39a424`) on that CCL and on SBCL. All runs 2026-11-13. Reproduce with `./run.sh`
(about 2 minutes; output of the last run is in `out-run.txt`, raw logs in `out/`).

## The trigger

A store instruction livelocks when **the instruction and the memory it writes lie in the same 16K page
of CCL's read-only ("pure") area**. That happens when all of these hold:

1. the image was saved with `save-application` and `:purify t` (the default), then restarted;
2. the target is an ivector (any specialised array or string) that existed before the save. Purify
   moves every such object into the pure area;
3. the store is compiled inline in a function that also existed before the save, so its code vector
   was purified too;
4. purify happened to place the code vector and the target element in the same 16K page. Objects
   defined together (a `defvar` next to its `defun`, a stobj next to its updaters) usually are.

Nothing else matters. Not the optimize policy, not the element type, not special variable versus
argument, not `:prepend-kernel`. It is a livelock, not a crash: the process spins at about 75% CPU
in the Mach exception thread and prints nothing.

## Trigger matrix

Plain CCL, image built by `matrix/mbuild.lisp`, one process per cell (`matrix/mtest.lisp`,
`matrix/matrix.sh`). "same page" is computed in the restarted image from `%address-of` the array and
the writer's code vector before the write is attempted. Full tables: `matrix/m-*.txt`.

| writer (all on a pre-save 4-element vector unless noted) | same page | result |
|---|---|---|
| `fast`: pre-save fn, `(speed 3) (safety 0)`, declared `simple-array` | yes | HANG |
| `safe`: pre-save fn, default policy, declared `simple-array` | yes | HANG |
| `undecl`: pre-save fn, no declarations (calls the generic setter) | yes (fn page) | returns, value correct |
| `generic`: `(setf (aref ...))` from the test script | n/a | returns, value correct |
| `postfast`: same fast lambda compiled after restart (code at `0x7000000000`, the JIT heap) | no | returns, value correct |
| `newarr`: pre-save fast fn on a vector made after restart (dynamic heap) | no | returns, value correct |

Element types: `bit`, `(unsigned-byte 8/16/32/64)`, `(signed-byte 8/16/32/64)`, `fixnum`,
`single-float`, `double-float` all hang in the `fast` and `safe` rows. `character` and `base-char`
vectors were purified too but landed one page away from their writers in this build, and returned
correctly: the same code as the hanging rows, with only the page differing. `(array t)` (a gvector)
is not purified and never hangs.

Same function, same vector, only the index changed (`matrix/mbig.lisp`, 100000-byte vector whose
first 1732 bytes share a page with `fast-u8`):

| index | element page | code page | result |
|---|---|---|---|
| 0 | `300000CBC000` | `300000CBC000` | HANG |
| 1500 | `300000CBC000` | `300000CBC000` | HANG |
| 1800 | `300000CC0000` | `300000CBC000` | returns, 9 stored, 1 nonzero element |
| 50000 | `300000CC8000` | `300000CBC000` | returns, 9 stored, 1 nonzero element |

Other variations:

| variation | result |
|---|---|
| `:prepend-kernel nil` (image run with `darm64cl -I img`) | identical: 12 types hang, `ch`/`bch`/`gv` return |
| special variable with a declared type (`fast-special-u8`) | returned in this build because its code was on another page; no dependence on the form |
| fresh image, no save (`c.lisp` from the original scratchpad) | both forms return (`#(0 4 0 0)`, `#(0 4 0 5)`) |
| pre-save cons, struct, hash table, simple-vector | in the dynamic heap (`0x3020...`), writes return and are correct |
| pre-save string: `(setf char)`, `replace`, `fill` | purified, writes return and are correct (out-of-line code) |
| second-generation image saved from the restarted image | hang is still there |
| `:purify nil` | different failure, see "Side findings" |

## Wrong values: none observed

Every write that returned was read back correctly. Evidence:

- 66 returning cells of the main matrix: the written vector equals the expected contents, the two
  guard vectors allocated on either side are unchanged, and both still hold after `(ccl:gc)`.
- A sweep of all 100000 elements of the big vector (`fast-big`, `fill-big`) gave the right counts.
- Generic writes to purified data made in a restarted image survive a second `save-application`
  and restart (`a-u8=#(0 42 0 0) big[50000]=43 str="Raaaaaaa"`).
- `read-sequence` from a file into a purified vector filled all 40000 bytes.

Two things that look like a lost write but are not silent:

- **Kill artifact in ACL2.** When `timeout` sends SIGTERM to the spinning ACL2, it sometimes prints
  the "interrupt or error ... cleaning up" note and sometimes aborts the update with no message and
  carries on reading the script, so a later read shows the old value (`@read (0 0)`). Checked by
  snapshotting the output at 10 s of a 16 s timeout, three runs: nothing after the prompt until the
  signal. A user who interrupts the hang by hand could see the same quiet abort.
- **read(2) straight into a purified vector fails with EFAULT.** `ccl::fd-read` into a pinned
  pre-save vector returned -14 and wrote nothing; the same call into a fresh vector returned 40000
  (`matrix/mio.lisp`). The kernel does not take the user-level fault path. It is an error return,
  but code that ignores it would see stale data.

## Root cause

Verified by direct observation:

- `CCL_DEBUG_WX=1` on the hanging process prints the loop itself, two faults per iteration with
  the same pc:

      W^X fixup #2 RW far=0x300000cc4b58 pc=0x300000cc4950
      W^X fixup #3 RX far=0x300000cc4950 pc=0x300000cc4950
      W^X fixup #4 RW far=0x300000cc4b58 pc=0x300000cc4950   (and so on)

  Returning cases log a single RW fixup for the store and carry on.
- `sample` of a hung process: the lisp thread makes no progress, and the exception thread sits in
  `catch_mach_exception_raise_state` calling `mprotect` (`arm64-darwin-mach.c:537`).
- Disassembly of the safe writer shows the store inline: `(strb wimm0 (:@ arg_x imm1))`, from vinsn
  `misc-set-u8` (`compiler/ARM64/arm64-vinsns.lisp:2532-2536`). The backend is doing nothing wrong.

From the source (`/Users/ember/dev/ccl/lisp-kernel`):

1. `arm64-gc.c:1991-2020` `copy_ivector_reference`: purify copies every ivector except macptrs
   into the pure area, user data as well as code vectors. This is the same rule as the PPC and
   32-bit ARM ports (`arm-gc.c:1562-1582`).
2. `arm64-gc.c:2345-2355` (after purify) and `image.c:550-558` (at image load): the whole pure area
   is `mprotect`ed `PROT_READ|PROT_EXEC`.
3. On a write fault in the pure area the page is made `PROT_READ|PROT_WRITE`, dropping execute:
   `arm64-darwin-mach.c:86-92` (`darwin_arm64_try_wx_fixup`, the path actually taken, called at
   `:537`) and `arm64-exceptions.c:1290-1301`; `UnProtectMemory` is RW-only on this platform
   (`memory.c:431-433`).
4. On an instruction-fetch fault in the pure area the page is made `PROT_READ|PROT_EXEC` again,
   dropping write: `arm64-darwin-mach.c:69-75`, `arm64-exceptions.c:1242-1247`.
5. The comment at `arm64-exceptions.c:1222-1230` describes this oscillation as the design
   ("write fault -> mprotect RW, NX fetch -> mprotect RX, same page may flip again on a later
   store"). It does not account for the store instruction living in the page it writes: making
   the page writable makes the instruction unfetchable, and the reverse, so the store can never
   complete.

Other ports do not have this problem because their `UnProtectMemory` restores RWX
(`memory.c:435`, used at `arm-exceptions.c:935-939`), so a dirtied pure page stays executable.
Apple Silicon forbids RWX on ordinary mappings, and the port replaced it with the flip.

Confidence: high. The mechanism is logged directly, the page-equality prediction matched all 90
cells of the main matrix plus the index experiment and the ACL2 per-type matrix, and the source
reads the same way. I did not build a patched kernel to show a fix removes it.

Fix directions (inferred, not tested): keep mutable ivectors out of the pure area on this
platform (purify only code vectors and immutable data), or give code and data separate
page-aligned pure regions, or have the handler single-step or emulate the store when pc and
fault address share a page.

## ACL2

`save-exec` does nothing CCL-specific that matters here: `save-acl2-in-ccl-aux` runs `(ccl::gc)`
then `(ccl:save-application core-name)` with default arguments, so `:purify t`
(`/Users/ember/dev/acl2-fix/head-worktree/acl2-init.lisp:2466-2467`).

It reproduces with ordinary user steps (`acl2-build.lisp`, `acl2-hang.lisp`): `defstobj` with an
array field, `:q`, `(save-exec "zimg" nil)`, restart, `(update-zari 1 9 zst)` hangs. In the saved
image the array and the code of `update-zari` are both on page `300005168000`. The same script on
SBCL-hosted ACL2 returns `(0 9 7 0)`.

One two-field stobj per element type, all in one image (`matrix/acl2-build2.lisp`,
`matrix/acl2-m2.txt`). Each `defstobj` consumes about one 16K page of pure space, so whether a
given array shares a page with its updater depends on what was defined before it:

| stobj array field | raw Lisp type | same page as updater | `update-...i` after restart |
|---|---|---|---|
| `(unsigned-byte 8)` | `(simple-array (unsigned-byte 8))` | yes | HANG |
| `bit` | `simple-bit-vector` | yes | HANG |
| `(unsigned-byte 16)`, `(unsigned-byte 32)`, `(unsigned-byte 64)` | specialised | yes | HANG |
| `(signed-byte 8)`, `(signed-byte 32)` | specialised | yes | HANG |
| `character` | `simple-base-string` | yes | HANG |
| resizable `(unsigned-byte 8)` | specialised | yes | HANG |
| `(unsigned-byte 8)` with `:inline t` (store inlined into the `*1*` function, same page) | specialised | yes | HANG |
| `(signed-byte 64)`, `(integer 0 100)`, `double-float` | specialised, purified | no (next page) | returns, correct |
| `t` | `simple-vector`, not purified | no | returns, correct |
| scalar field write, array read | | | returns, correct |

The three "no" rows are layout luck in that image, not immunity: their arrays are in the pure area
like the others. A single 15-field stobj (`matrix/acl2-build.lisp`, `matrix/acl2-m1.txt`) put all
its arrays one or two pages away from the updaters and every update returned correctly, so a big
stobj can escape where a small one hangs.

Also returned correctly in the saved image: `resize-zrs`, `aset1` and `compress1` on a pre-save
ACL2 array, a memoized function called on old and new arguments, `hons`/`hons-equal`/`hons-copy`
against a pre-save hons. These rest on conses, simple-vectors and hash tables, which purify leaves
in the dynamic heap.

## Side findings

- **`:purify nil` images lose user-compiled functions.** With `:purify nil`, calling any function
  compiled before the save crashes the restarted image (SIGILL at `0x700000000c`, "udf #0", or
  SIGSEGV at `0x7000000000`). The function's code vector address is in the JIT code heap, and
  that memory is zero or unmapped after restart (`matrix/np.lisp`, `matrix/np2.lisp`). A
  `:purify nil` image with no user functions starts and runs. Inferred, not traced in source: the
  JIT heap is not written to the image and only purify moves code out of it. ACL2 does not use
  `:purify nil`.
- The original observation "safe function works, fast function hangs" does not hold: with a
  declared `simple-array` type the default policy also emits the inline store and also hangs.
  What worked in the first experiment was the generic out-of-line `(setf aref)`.

## Verified / inferred / not checked

Verified (ran it, saw it):
- Hang reproduces in plain CCL and through ACL2 `save-exec`; SBCL-hosted ACL2 control returns.
- Hang occurs exactly when store instruction and target share a page (matrix, index experiment,
  ACL2 per-type matrix); the RW/RX alternation is logged by the kernel's own debug trace.
- Independent of optimize policy, element type and `:prepend-kernel`; needs `:purify t`.
- No wrong value in any returning write, including neighbours, after GC, and across a re-save.
- read(2) into a purified vector returns EFAULT.
- ACL2's CCL save path is a bare `save-application`.

Inferred (from reading source, consistent with the observations):
- Other CCL ports avoid the loop because they restore RWX.
- The `:purify nil` crash is the JIT code heap not being saved.
- The fix directions above.

Not checked:
- Multi-threaded behaviour. A second thread executing code on a page while another thread writes
  data on it should flip the page back and forth and may slow or stall both; not tested.
- Whether upstream or newer commits of this port change the handler.
- A patched kernel.
- ACL2 `hons`/memoize beyond the three quick calls above; ACL2(p); books certified into a saved image.
- Linux arm64 or any other platform.

## Files

- `run.sh`: builds and runs both reproducers, prints the comparison, deletes each image.
- `ccl-build.lisp`, `ccl-test.lisp`: minimal plain-CCL reproducer (control / generic / hang).
- `acl2-build.lisp`, `acl2-control.lisp`, `acl2-hang.lisp`: minimal ACL2 reproducer.
- `out-run.txt`, `out/`: output of the last `run.sh`.
- `matrix/`: scripts and result tables for everything above.
