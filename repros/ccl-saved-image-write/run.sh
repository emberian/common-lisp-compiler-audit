#!/bin/sh
# Reproduces: CCL darwinarm64 saved image livelocks when an inline store hits a purified
# ivector that shares a 16K page with the storing code.  Plain CCL first, then ACL2.
# Every Lisp runs under nice + timeout; at most one saved image exists at a time and
# each is deleted as soon as its tests are done.
CCL=${CCL:-/Users/ember/dev/ccl/darm64cl}
ACL2_CCL=${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}
ACL2_SBCL=${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}
here=$(cd "$(dirname "$0")" && pwd); cd "$here" || exit 1
out=$here/out; mkdir -p "$out"
cleanup() { rm -f "$here/img" "$here/zimg" "$here"/zimg.*; }
trap cleanup EXIT
verdict() { case $1 in 0) echo "returned";; 124|137) echo "HANG (killed by timeout)";; *) echo "exit code $1";; esac; }

echo "=== 1. plain CCL: $($CCL --version)"
cleanup
nice -n 15 timeout 60 "$CCL" --batch --no-init --load ccl-build.lisp > "$out/ccl-build.out" 2>&1 || { echo "build failed, see $out/ccl-build.out"; exit 1; }
for c in control generic hang; do
  CASE=$c CCL_DEBUG_WX=1 nice -n 15 timeout -k 5 8 ./img --batch --no-init --load ccl-test.lisp > "$out/ccl-$c.out" 2>&1
  eval "rc_$c=$?"
done
grep -h '^@code-vector\|^@on-page' "$out/ccl-control.out"
echo "  control (inline store, element on another page) : $(verdict $rc_control)  $(grep -h '^@control' "$out/ccl-control.out")"
echo "  generic (out-of-line store, element on code page): $(verdict $rc_generic)  $(grep -h '^@generic' "$out/ccl-generic.out")"
echo "  hang    (inline store, element on code page)     : $(verdict $rc_hang)  $(grep -h '^@hang' "$out/ccl-hang.out")"
echo "  W^X fixups logged in 8 s (CCL_DEBUG_WX logs at most 16): control=$(grep -c 'W^X fixup' "$out/ccl-control.out") generic=$(grep -c 'W^X fixup' "$out/ccl-generic.out") hang=$(grep -c 'W^X fixup' "$out/ccl-hang.out")"
echo "  last fixups of the hang case (same pc, alternating RW/RX):"
grep 'W^X fixup' "$out/ccl-hang.out" | tail -4 | sed 's/^/    /'
cleanup

run_acl2() { # label, acl2 executable
  label=$1; exe=$2
  if [ ! -x "$exe" ]; then echo "  [$label] $exe not found, skipped"; return; fi
  cleanup
  nice -n 15 timeout 180 "$exe" < acl2-build.lisp > "$out/acl2-$label-build.out" 2>&1
  [ -x ./zimg ] || { echo "  [$label] save-exec failed, see $out/acl2-$label-build.out"; return; }
  nice -n 15 timeout -k 5 30 ./zimg < acl2-control.lisp > "$out/acl2-$label-control.out" 2>&1; rc1=$?
  nice -n 15 timeout -k 5 30 ./zimg < acl2-hang.lisp > "$out/acl2-$label-hang.out" 2>&1; rc2=$?
  echo "  [$label] before save : $(grep -h -o '@before.*' "$out/acl2-$label-build.out" | head -1)"
  echo "  [$label] read + scalar write in saved image : $(verdict $rc1)  $(grep -h -o '@read.*' "$out/acl2-$label-control.out") / $(grep -h -o '@scalar-write.*' "$out/acl2-$label-control.out") $(grep -h -o '@pages.*' "$out/acl2-$label-control.out")"
  echo "  [$label] (update-zari 1 9 zst) in saved image: $(verdict $rc2)  $(grep -h -o '@array-write.*' "$out/acl2-$label-hang.out")"
  cleanup
}
echo "=== 2. ACL2 (defstobj with a (unsigned-byte 8) array field, save-exec, restart)"
run_acl2 ccl "$ACL2_CCL"
run_acl2 sbcl "$ACL2_SBCL"
echo "=== expected on an affected CCL: plain-CCL 'hang' and ACL2-on-CCL update-zari HANG; every other line returns."
echo "    (After the timeout's SIGTERM, ACL2 may print a cleanup NOTE or simply abort the update; that output is a kill artifact.)"
echo "raw outputs: $out"
ls "$here"/img "$here"/zimg* 2>/dev/null && echo "WARNING: image left behind" || echo "no saved image left in $here"
