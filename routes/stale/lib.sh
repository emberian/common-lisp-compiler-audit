# Helpers for the stale-artifact scenarios.  Sourced by run.sh; every scenario
# function runs in its own subshell with cwd = an empty work directory.
#
# A scenario arranges files, then calls `inc` (the session under test: PRE forms,
# an include-book, the queries) and `ref` (a new session in a clean directory
# holding only the current sources, which `ld`s them and replays the same
# queries), and usually `ctl` (the same as `ref` but with the stale version of
# some file, to show the queries can tell the versions apart).

ROOT=/Users/ember/dev/compiler-audit/routes/stale
B=$ROOT/books

host_setup() {
  HOST=$1
  ACL2=/Users/ember/dev/acl2-fix/$HOST-worktree/saved_acl2
  case $HOST in
    head) FX=fasl;    OHOST=ccl;  OFX=da64fsl ;;
    ccl)  FX=da64fsl; OHOST=head; OFX=fasl ;;
    *) echo "host must be head or ccl" >&2; exit 2 ;;
  esac
  OACL2=/Users/ember/dev/acl2-fix/$OHOST-worktree/saved_acl2
}

QUIET="(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))"

# run_acl2 SCRIPT OUT [IMAGE]
run_acl2() {
  nice -n 15 timeout "${TMO:-300}" "${3:-$ACL2}" < "$1" > "$2" 2>&1
  echo "@EXIT $?" >> "$2"
}

# put VERSION [NAME]: install books/VERSION.lisp as NAME.lisp (default book)
put() { cp "$B/$1.lisp" "${2:-book}.lisp"; }

# cert [NAME [ARGS...]]: certify NAME (default book).  CERTPRE = forms first,
# CERTIMG = image to use.  Default args allow any portcullis and skip-proofs.
cert() {
  local n=${1:-book}; [ $# -gt 0 ] && shift
  local args=${*:-"? t :skip-proofs-okp t"}
  printf '%s\n(certify-book "%s" %s)\n(quit)\n' "${CERTPRE:-}" "$n" "$args" > "cert-$n.lsp"
  run_acl2 "cert-$n.lsp" "cert-$n.out" "${CERTIMG:-}"
  [ -f "$n.cert" ] || { echo "certify $n failed" >> setup.err; return 1; }
}

# The @I line reports (books in the include-book-alist, how many of them carry a
# book-hash, i.e. are considered certified).
IFORM='(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))'

# inc: the session under test.  PRE, INC (default (include-book "$TOP")), MID
# (forms between include and queries), Q (query file under books/), POST, INCIMG.
inc() {
  local q=${Q:-hq}
  [ -f "$B/$q.lisp" ] && cp "$B/$q.lisp" .
  {
    echo "$QUIET"
    echo "${PRE:-}"
    echo "${INC:-(include-book \"${TOP:-book}\")}"
    echo "(in-package \"ACL2\")"
    echo "$IFORM"
    echo "${MID:-}"
    echo "(ld \"$q.lisp\" :ld-error-action :continue)"
    echo "${POST:-}"
    echo "(quit)"
  } > inc.lsp
  run_acl2 inc.lsp inc.out "${INCIMG:-}"
}

# fresh OUT [name=version ...]: clean directory with the current *.lisp and
# *.txt of the work directory (then the named overrides), no artifacts; a new
# session runs REFPRE, lds $TOP.lisp (or REFLD), then the queries and REFPOST.
fresh() {
  local out=$1; shift
  local q=${Q:-hq} d=fresh.$$.$RANDOM
  mkdir "$d"
  cp ./*.lisp "$d"/ 2>/dev/null; cp ./*.txt "$d"/ 2>/dev/null
  rm -f "$d"/inc.lsp "$d"/cert-*.lsp
  local m
  for m in "$@"; do cp "$B/${m#*=}.lisp" "$d/${m%%=*}.lisp" 2>/dev/null || cp "$B/${m#*=}" "$d/${m%%=*}"; done
  [ -f "$B/$q.lisp" ] && cp "$B/$q.lisp" "$d"/
  {
    echo "$QUIET"
    echo "${REFPRE-${PRE:-}}"
    echo "${REFLD-(mv-let (erp val state) (ld \"${TOP:-book}.lisp\" :ld-error-action :error) (declare (ignore val)) (pprogn (fms \"@LD ~x0~%\" (list (cons #\\0 (if erp :failed :ok))) *standard-co* state nil) (value :invisible)))}"
    echo "(in-package \"ACL2\")"
    echo "${REFMID-${MID:-}}"
    echo "(ld \"$q.lisp\" :ld-error-action :continue)"
    echo "${REFPOST-${POST:-}}"
    echo "(quit)"
  } > "$d/ref.lsp"
  ( cd "$d" && run_acl2 ref.lsp ref.out "${REFIMG:-}" )
  cp "$d/ref.out" "$out"
  rm -rf "$d"
}
ref() { fresh ref.out "$@"; }
ctl() { fresh ctl.out "$@"; }

# rec FILE: the comparable records of a session
rec() { grep -a -o '@[A-Z]* .*\|@END' "$1" | grep -v '^@I \|^@EXIT\|^@LD ' ; }

# Set a file's mtime to another file's mtime plus SECONDS (may be negative).
mt_like() { # mt_like FILE REF [SECONDS]
  touch -r "$2" "$1"
  local s=${3:-0}
  if [ "$s" -gt 0 ]; then touch -A "$(printf '%02d' "$s")" "$1"
  elif [ "$s" -lt 0 ]; then touch -A "-$(printf '%02d' "$(( -s ))")" "$1"; fi
}

# keep_times FILE CMD...: run CMD (which rewrites FILE), then restore FILE's mtime
keep_times() { local f=$1; shift; cp -p "$f" "$f.ts"; "$@"; touch -r "$f.ts" "$f"; rm -f "$f.ts"; }
