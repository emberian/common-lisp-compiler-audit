# Scenario functions; see lib.sh for the helpers and scenarios.tsv for the table.
# Naming: A and B are two versions of a book with the same function names, the
# same file length and different bodies.  "Current" is always what is on disk
# as book.lisp when the include happens; the stale version is passed to ctl.

# ---------- baseline and controls
sc_base()            { put hbA; cert; inc; ref; ctl book=hbB; }
sc_ctl_rawload()     { # control: a stale compiled file loaded by raw LOAD over a fresh ld must show up
  put vt1A book; cert; mv book.$FX old.$FX; rm -f book.cert; put vt1B book
  Q=cq INC='(ld "book.lisp")' MID=":q
(load \"old.$FX\")
(lp)" inc
  INCN=0; Q=cq ref; Q=cq ctl book=vt1A; }

# ---------- compiled file: missing, old, damaged
sc_fasl_missing()    { put hbA; cert; rm book.$FX; inc; ref; ctl book=hbB; }
sc_fasl_older()      { put hbA; cert; mt_like book.$FX book.cert -5; inc; ref; ctl book=hbB; }
sc_fasl_truncated()  { put hbA; cert; s=$(wc -c < book.$FX); keep_times book.$FX sh -c "head -c $((s/2)) book.$FX > t && cat t > book.$FX && rm t"; inc; ref; ctl book=hbB; }
sc_fasl_zero()       { put hbA; cert; keep_times book.$FX sh -c ": > book.$FX"; inc; ref; ctl book=hbB; }
sc_fasl_garbage()    { put hbA; cert; keep_times book.$FX sh -c "echo '(defun f (x) (list x 99))' > book.$FX"; inc; ref; ctl book=hbB; }
sc_fasl_otherhost()  { # the other host's compiled file under this host's name
  put hbA; CERTIMG=$OACL2 cert; mv book.$OFX other; rm -f book.cert; cert; cp other book.$FX; mt_like book.$FX book.cert 5; inc; ref; ctl book=hbB; }

# ---------- compiled file from another version of the book (same names, other bodies)
# certify A, keep its compiled file; install B and certify it; put A's compiled file back
_swap_AB() { put hbA; ${CERTWRAP:-} cert; cp -p book.$FX A.$FX; put hbB; ${CERTWRAP:-} cert; cp -p book.$FX B.$FX; cp A.$FX book.$FX; }
sc_fasl_oldver_newer()   { _swap_AB; mt_like book.$FX book.cert 5; inc; ref; ctl book=hbA; }
sc_fasl_oldver_same_mtime() { _swap_AB; touch -r B.$FX book.$FX; inc; ref; ctl book=hbA; }
sc_fasl_oldver_eq_cert() { _swap_AB; touch -r book.cert book.$FX; inc; ref; ctl book=hbA; }
sc_fasl_oldver_older()   { _swap_AB; mt_like book.$FX book.cert -5; inc; ref; ctl book=hbA; }
sc_fasl_oldver_checksum() { # the same with checksum book-hashes at certify and include time
  CERTPRE='(assign book-hash-alistp nil)'; _swap_AB; mt_like book.$FX book.cert 5
  PRE='(assign book-hash-alistp nil)' inc; ref; ctl book=hbA; }
sc_fasl_oldver_lcf_t()   { _swap_AB; mt_like book.$FX book.cert 5; INC='(include-book "book" :load-compiled-file t)' inc; ref; ctl book=hbA; }
sc_fasl_otherbook()  { # compiled file of an unrelated book (other function names) renamed
  put sbA other; cert other; put hbA; cert; cp other.$FX book.$FX; mt_like book.$FX book.cert 5; rm -f other.*; inc; ref; ctl book=hbB; }
sc_recert_nocompile()    { # natural flow: certify A compiled, edit to B, recertify without compiling
  put hbA; cert; put hbB; cert book "? nil :skip-proofs-okp t"; inc; ref; ctl book=hbA; }
sc_recert_nocompile_future() { # as above, but the old compiled file carries a future date (restored cache, clock skew)
  put hbA; cert; touch -A 010000 book.$FX; put hbB; cert book "? nil :skip-proofs-okp t"; inc; ref; ctl book=hbA; }

# ---------- source edited after certification, cert and compiled file left in place
sc_src_touch()       { put hbA; cert; touch -A 05 book.lisp; inc; ref; ctl book=hbB; }
sc_src_whitespace()  { put hbA; cert; echo >> book.lisp; inc; ref; ctl book=hbB; }
sc_src_whitespace_samelen() { # a space replaced by a newline, length and mtime kept
  put hbA; cert; keep_times book.lisp sh -c "sed -e '2s/ 1000/\\
1000/' book.lisp > t && cat t > book.lisp && rm t"; inc; ref; ctl book=hbB; }
sc_src_body_len()    { put hbA; cert; sed -e 's/(\* 2 x)/(* 22 x)/' book.lisp > t; cat t > book.lisp; rm t; inc; ref; ctl book=hbA; }
sc_src_body_samelen(){ put hbA; cert; touch -r book.lisp stamp; put hbB; touch -r stamp book.lisp; inc; ref; ctl book=hbA; }
sc_src_body_samelen_mtime() { put hbA; cert; touch -r book.lisp stamp; put hbB; touch -A 05 book.lisp; inc; ref; ctl book=hbA; }
sc_src_body_samelen_checksum() { CERTPRE='(assign book-hash-alistp nil)'; put hbA; cert; touch -r book.lisp stamp; put hbB; touch -r stamp book.lisp
  PRE='(assign book-hash-alistp nil)' inc; ref; ctl book=hbA; }
sc_src_guard_samelen() { # only a type declaration changes: (integer 0 100) -> (integer 0 900); compiled code keeps the old one
  put hbA; cert; touch -r book.lisp stamp; sed -e 's/(integer 0 100)/(integer 0 900)/' book.lisp > t; cat t > book.lisp; rm t; touch -r stamp book.lisp
  POST='(cw "@Q tz500 ~x0~%" (tz 500))' ; export POST; inc; ref; cp "$B/hbA.lisp" book.lisp; POST='(cw "@Q tz500 ~x0~%" (list :old (tz 99)))' ctl; }
sc_src_fn_added()    { put hbA; cert; echo "(defun added (x) (cons x 'new))" >> book.lisp; POST='(cw "@Q added ~x0~%" (added 3))' inc; POST='(cw "@Q added ~x0~%" (added 3))' ref; ctl book=hbB; }

# ---------- damaged compiled file of the OLD version (partial raw load, then fallback to source)
_trunc_old() { # $1 = percent of A's compiled file kept
  _swap_AB; s=$(wc -c < A.$FX); head -c $((s*$1/100)) A.$FX > book.$FX; mt_like book.$FX book.cert 5; inc; ref; ctl book=hbA; }
sc_fasl_oldver_trunc25() { _trunc_old 25; }
sc_fasl_oldver_trunc50() { _trunc_old 50; }
sc_fasl_oldver_trunc90() { _trunc_old 90; }
sc_fasl_oldver_trunc99() { _trunc_old 99; }

# ---------- certificate: missing, damaged, foreign
sc_cert_missing()    { put hbA; cert; rm book.cert; inc; ref; ctl book=hbB; }
sc_cert_zero()       { put hbA; cert; : > book.cert; touch -r book.lisp book.cert; inc; ref; ctl book=hbB; }
sc_cert_truncated()  { put hbA; cert; s=$(wc -c < book.cert); head -c $((s/2)) book.cert > t; cat t > book.cert; rm t; touch -r book.lisp book.cert; inc; ref; ctl book=hbB; }
sc_cert_otherbook()  { put sbA other; cert other; put hbA; cert; cp other.cert book.cert; touch -r book.lisp book.cert; rm -f other.*; inc; ref; ctl book=hbB; }
sc_cert_oldver_fasl_new() { # cert of A (same length and mtime as B's source), compiled file of B
  put hbA; cert; cp -p book.cert A.cert; touch -r book.lisp stamp; put hbB; cert; cp A.cert book.cert; touch -r stamp book.lisp; mt_like book.cert book.lisp 1; mt_like book.$FX book.cert 1; inc; ref; ctl book=hbA; }
sc_cert_otherhost_nofasl() { put hbA; CERTIMG=$OACL2 cert; rm -f book.$OFX; inc; ref; ctl book=hbB; }
sc_cert_otherhost_natural() { # this host certifies, then the other host recertifies in the same directory
  put hbA; cert; CERTIMG=$OACL2 cert; inc; ref; ctl book=hbB; }
sc_cert_otherhost_fasl() { # other host's cert, this host's compiled file made newer than it
  put hbA; cert; CERTIMG=$OACL2 cert; mt_like book.$FX book.cert 5; inc; ref; ctl book=hbB; }
sc_cert_otherhost_oldfasl() { # this host certified A; the other host certified B; this host's A compiled file is newer (same-second or skew)
  put hbA; cert; put hbB; CERTIMG=$OACL2 cert; mt_like book.$FX book.cert 5; inc; ref; ctl book=hbA; }
sc_port_missing()    { put hbA; cert; rm book.port; inc; ref; ctl book=hbB; }
_other_port() { put sbA other; CERTPRE='(defpkg "ZPP" nil)' cert other; cp other.port "$1"; rm -f other.* cert-other.*; }
PFQ='(cw "@Q zpp ~x0~%" (and (find-package-entry "ZPP" (known-package-alist state)) t))'
sc_port_other()      { put hbA; cert; _other_port book.port; POST=$PFQ inc; POST=$PFQ ref; ctl book=hbB; }
sc_port_other_uncert() { put hbA; cert; _other_port book.port; rm book.cert; POST=$PFQ inc; POST=$PFQ ref; ctl book=hbB; }

# ---------- include environment differs from the certification environment (artifacts untouched)
_envA() { put hbA; cert; }
sc_env_defaults()    { _envA; PRE='(set-ignore-ok t) (set-irrelevant-formals-ok t) (set-state-ok t) (set-verify-guards-eagerness 0) (set-bogus-mutual-recursion-ok t) (set-compile-fns t) (program)'; MID='(logic)'; inc
  REFPRE= ref; REFPRE= ctl book=hbB; }
sc_env_redundant()   { _envA; PRE='(defconst *k* 1000) (defun f (x) (declare (xargs :guard (integerp x))) (+ x *k* 1)) (defun-inline i (x) (declare (xargs :guard t)) (list x (quote ia)))'; inc; ref; ctl book=hbB; }
sc_env_conflict_fn() { _envA; PRE='(defun g (x) (declare (xargs :guard t :verify-guards nil)) (if (integerp x) (* 9 x) 0))'; inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_const() { _envA; PRE='(defconst *k* 7)'; inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_macro() { _envA; PRE='(defmacro e (x) (list (quote list) x 77))'; inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_inline() { _envA; PRE='(defun-inline i (x) (declare (xargs :guard t)) (list x (quote zz))) (defun ui0 (x) (declare (xargs :guard t)) (i x))'
  POST='(cw "@Q ui0 ~x0~%" (ui0 3))'; inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_late() { # the conflict is at the last function; afterwards the session defines f, g, e itself
  _envA; PRE='(defun lm (x) (declare (xargs :guard t)) (list x 77))'
  MID='(defconst *k* 5) (defun f (x) (declare (xargs :guard (integerp x))) (- x *k*)) (defun g (x) (declare (xargs :guard t)) (list x 78)) (defun e (x) (declare (xargs :guard t)) (list x 79)) (defmacro m (x) (list (quote list) x 80)) (defun um (x) (declare (xargs :guard t)) (m x)) (defun h (x) (declare (xargs :mode :program)) (list x 81))'
  inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_stobj() { _envA; PRE='(defstobj st (fld :type integer :initially 9) (g2 :initially nil)) (update-fld 77 st)'
  POST='(cw "@Q fld ~x0~%" (list (fld st) (g2 st)))'; inc; DIRTYCHK=1; REFLD= ref; }
sc_env_conflict_dirs() { # the same book name in two directories with different bodies; the second include must fail and leave the first intact
  mkdir da db; (cd da; put hbA; cert); (cd db; put hbB; cert); cp db/setup.err . 2>/dev/null; cp da/setup.err . 2>/dev/null
  INCN=2; PRE='(include-book "da/book")' INC='(include-book "db/book")' inc
  cp da/book.lisp book.lisp; ref; ctl book=hbB; }
sc_env_redef()       { # redefinition allowed: the book's definition must win, exactly as with ld
  _envA; PRE='(defun g (x) (declare (xargs :guard t :verify-guards nil)) (if (integerp x) (* 9 x) 0)) (redef!)'; inc; ref; ctl book=hbB; }
sc_env_pkg()         { _envA; PRE='(defpkg "ZPK" (quote (include-book in-package cons f g a))) (in-package "ZPK")' INC='(include-book "book")' inc; REFPRE= ref; ctl book=hbB; }
sc_env_skip_proofs() { _envA; PRE='(set-ld-skip-proofsp t state)' MID='(set-ld-skip-proofsp nil state)' inc; REFPRE= REFMID= ref; ctl book=hbB; }
sc_env_gc_none()     { _envA; PRE='(set-guard-checking :none)' inc; REFPRE= ref; ctl book=hbB; }
sc_env_gc_all()      { _envA; PRE='(set-guard-checking :all)' inc; REFPRE= ref; ctl book=hbB; }
sc_env_gc_nil()      { _envA; PRE='(set-guard-checking nil)' inc; REFPRE= ref; ctl book=hbB; }
sc_env_nocompiler()  { _envA; PRE='(set-compiler-enabled nil state)' inc; REFPRE= ref; ctl book=hbB; }
sc_env_nocompiler_oldver() { _swap_AB; mt_like book.$FX book.cert 5; PRE='(set-compiler-enabled nil state)' inc; REFPRE= ref; ctl book=hbA; }
sc_env_lcf_t()       { _envA; INC='(include-book "book" :load-compiled-file t)' inc; ref; ctl book=hbB; }
sc_env_lcf_nil()     { _envA; INC='(include-book "book" :load-compiled-file nil)' inc; ref; ctl book=hbB; }
sc_env_lcf_nil_oldver() { _swap_AB; mt_like book.$FX book.cert 5; INC='(include-book "book" :load-compiled-file nil)' inc; ref; ctl book=hbA; }
sc_env_lcf_warn()    { _envA; INC='(include-book "book" :load-compiled-file :warn)' inc; ref; ctl book=hbB; }
sc_env_lcf_comp()    { _envA; INC='(include-book "book" :load-compiled-file :comp)' inc; ref; ctl book=hbB; }
sc_env_lcf_t_missing() { _envA; rm book.$FX; INC='(include-book "book" :load-compiled-file t)' inc; DIRTYCHK=1; REFLD= ref; }
sc_env_memo()        { _envA; PRE='(defconst *k* 1000) (defun f (x) (declare (xargs :guard (integerp x))) (+ x *k* 1)) (memoize (quote f)) (cw "@Q pre ~x0~%" (f 3))'
  POST='(cw "@Q memo ~x0~%" (list (f 3) (f 4) (and (getpropc (quote f) (quote memoized) nil (w state)) t)))'; inc; ref; ctl book=hbB; }
sc_env_stobj_same()  { _envA; PRE='(defstobj st (fld :type integer :initially 5)) (update-fld 77 st)'; inc; ref; ctl book=hbB; }
ATPRE='(defstub cst (x) t) (defun impl-old (x) (declare (xargs :guard t)) (list x (quote old))) (defattach cst impl-old) (cw "@Q pre ~x0~%" (cst 3))'
sc_env_attach()      { put at; cert; Q=aq PRE=$ATPRE inc; Q=aq PRE=$ATPRE ref; }
sc_env_attach_memo() { put at; cert
  P="$ATPRE (defun call-cst (x) (declare (xargs :guard t)) (list (cst x) (quote ca))) (memoize (quote call-cst) :aokp t) (cw \"@Q pre2 ~x0~%\" (call-cst 3))"
  Q=aq PRE=$P inc; Q=aq PRE=$P ref; }
sc_env_pkg_conflict() { # the book's portcullis defines package ZP; the session has ZP with other imports
  put hbA; CERTPRE='(defpkg "ZP" (quote (car cdr)))' cert
  PRE='(defpkg "ZP" (quote (car cons)))' POST='(cw "@Q pk ~x0~%" (symbol-package-name (quote zp::cdr)))'; inc; DIRTYCHK=1; REFLD= ref; }

# ---------- make-event whose expansion depends on the environment
_me() { # $1 book (me | mec)
  cp "$B/data.txt" .; put "$1"; CERTPRE="(assign zg 'cert)" cert; }
sc_me_same()         { _me me;  Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" ref; }
sc_me_global()       { _me me;  Q=mq PRE="(assign zg 'inc)" inc; Q=mq PRE="(assign zg 'inc)" ref; Q=mq REFPRE="(assign zg 'cert)" ctl; }
sc_me_unset()        { _me me;  Q=mq inc; Q=mq ref; Q=mq REFPRE="(assign zg 'cert)" ctl; }
sc_me_file()         { _me me;  echo '(file-version-2)' > data.txt; Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" ref; Q=mq PRE="(assign zg 'cert)" ctl data.txt=data.txt; }
sc_me_world()        { _me me;  P="(assign zg 'cert) (defun extra-fn (x) x)"; Q=mq PRE=$P inc; Q=mq PRE=$P ref; Q=mq REFPRE="(assign zg 'cert)" ctl; }
sc_me_host()         { cp "$B/data.txt" .; put me; CERTPRE="(assign zg 'cert)" CERTIMG=$OACL2 cert; rm -f book.$OFX; Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" ref; Q=mq PRE="(assign zg 'cert)" REFIMG=$OACL2 ctl; }
sc_mec_same()        { _me mec; Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" ref; }
sc_mec_global()      { _me mec; Q=mq PRE="(assign zg 'inc)" inc; Q=mq PRE="(assign zg 'inc)" DIRTYCHK=1; REFLD= ref; }
sc_mec_file()        { _me mec; echo '(file-version-2)' > data.txt; Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" DIRTYCHK=1; REFLD= ref; }
sc_mec_world()       { _me mec; P="(assign zg 'cert) (defun extra-fn (x) x)"; Q=mq PRE=$P inc; Q=mq PRE=$P DIRTYCHK=1; REFLD= ref; }
sc_mec_host()        { cp "$B/data.txt" .; put mec; CERTPRE="(assign zg 'cert)" CERTIMG=$OACL2 cert; rm -f book.$OFX; Q=mq PRE="(assign zg 'cert)" inc; Q=mq PRE="(assign zg 'cert)" DIRTYCHK=1; REFLD= ref; }
sc_rc_host()         { # reader conditionals #+sbcl / #+ccl in a book certified by the other host
  put rc; CERTIMG=$OACL2 cert; rm -f book.$OFX; Q=rq inc; Q=rq ref; Q=rq REFIMG=$OACL2 ctl; }
sc_rc_host_fasl()    { # ... with this host's own compiled file (certified here first, then by the other host), made newer
  put rc; cert; CERTIMG=$OACL2 cert; mt_like book.$FX book.cert 5; Q=rq inc; Q=rq ref; Q=rq REFIMG=$OACL2 ctl; }

# ---------- sub-books
_sub() { put ${1:-sbA} sub; put lsub lsub; put top top; cert sub; cert lsub; cert top; }
sc_sub_pristine()    { _sub; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbB; }
sc_sub_src_edited()  { _sub; put sbB sub; touch -A 05 sub.lisp; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_recert()      { _sub; put sbB sub; touch -A 05 sub.lisp; cert sub; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_recert_samestamp() { _sub; touch -r sub.lisp stamp; put sbB sub; touch -r stamp sub.lisp; cert sub; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_recert_samestamp_checksum() { CERTPRE='(assign book-hash-alistp nil)'; _sub; touch -r sub.lisp stamp; put sbB sub; touch -r stamp sub.lisp; cert sub
  TOP=top Q=tq PRE='(assign book-hash-alistp nil)' inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_fasl_oldver() { _sub; cp -p sub.$FX A.$FX; put sbB sub; cert sub; cert top; cp A.$FX sub.$FX; mt_like sub.$FX sub.cert 5; mt_like top.$FX sub.$FX 1; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_top_fasl_oldver() { _sub; cp -p top.$FX A.$FX; put sbB sub; cert sub; cert top; cp A.$FX top.$FX; mt_like top.$FX top.cert 5; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbA; }
sc_sub_fasl_missing(){ _sub; rm sub.$FX; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbB; }
sc_sub_lcf_t_missing(){ _sub; rm sub.$FX; TOP=top Q=tq INC='(include-book "top" :load-compiled-file t)' inc; TOP=top Q=tq DIRTYCHK=1; REFLD= ref; }
sc_sub_cert_missing(){ _sub; rm sub.cert; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbB; }
sc_sub_local_changed(){ _sub; echo '(defthm lsub-lemma-2 (equal (cdr (cons x y)) y) :rule-classes nil)' >> lsub.lisp; cert lsub; TOP=top Q=tq inc; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbB; }
sc_sub_local_missing(){ _sub; rm lsub.lisp lsub.cert lsub.$FX; TOP=top Q=tq inc; put lsub lsub; TOP=top Q=tq ref; TOP=top Q=tq ctl sub=sbB; }
sc_sub_preincluded_other() { # the session already has sub's functions from a session definition of the other version: conflict
  _sub; PRE='(defun sf (x) (declare (xargs :guard t)) (list x (quote zz)))' TOP=top Q=tq inc; PRE='(defun sf (x) (declare (xargs :guard t)) (list x (quote zz)))' TOP=top Q=tq DIRTYCHK=1; REFLD= ref; }

# ---------- reclassification in a later book (verify-termination, verify-guards)
_vt() { put vt1A vt1; put vt2 vt2; cert vt1; cert vt2; }
VHP="(defun vh (x) (declare (xargs :mode :program :guard t)) (list x 'va))"
sc_vt_pristine()     { _vt; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq ref; TOP=vt2 Q=vq ctl vt1=vt1B; }
sc_vt_pre_program()  { _vt; PRE="$VHP (cw \"@Q pre ~x0~%\" (vh 3))"; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq ref; TOP=vt2 Q=vq ctl vt1=vt1B; }
sc_vt_pre_logic()    { _vt; PRE="(defun vh (x) (declare (xargs :guard t)) (list x 'va))"; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq ref; TOP=vt2 Q=vq ctl vt1=vt1B; }
sc_vt_pre_conflict() { _vt; PRE="(defun vh (x) (declare (xargs :mode :program :guard t)) (list x 'vx))"; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq DIRTYCHK=1; REFLD= ref; }
sc_vt_sub_recert()   { _vt; put vt1B vt1; touch -A 05 vt1.lisp; cert vt1; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq ref; TOP=vt2 Q=vq ctl vt1=vt1A; }
sc_vt_sub_recert_samestamp() { _vt; touch -r vt1.lisp stamp; put vt1B vt1; touch -r stamp vt1.lisp; cert vt1; TOP=vt2 Q=vq inc; TOP=vt2 Q=vq ref; TOP=vt2 Q=vq ctl vt1=vt1A; }
sc_vt_sub_first()    { # include the changed, recertified sub-book first, then the stale reclassifying book
  _vt; put vt1B vt1; touch -A 05 vt1.lisp; cert vt1; INCN=2; DIRTYCHK=1; PRE='(include-book "vt1")' TOP=vt2 Q=vq inc; PRE='(include-book "vt1")' REFLD= TOP=vt2 Q=vq ref; }

# ---------- expansion file
_expAB() { CERTPRE='(assign save-expansion-file t)'; put hbA; cert; cp -p book@expansion.lsp A.exp; put hbB; cert; }
sc_exp_nofasl()      { _expAB; rm book.$FX; inc; ref; ctl book=hbA; }
sc_exp_oldver()      { _expAB; rm book.$FX; cp A.exp book@expansion.lsp; mt_like book@expansion.lsp book.cert 5; inc; ref; ctl book=hbA; }
sc_exp_oldver_comp() { # :load-compiled-file :comp compiles the (stale) expansion file; a later plain include then finds a compiled file
  _expAB; rm book.$FX; cp A.exp book@expansion.lsp; mt_like book@expansion.lsp book.cert 5
  INC='(include-book "book" :load-compiled-file :comp)' inc; cp inc.out inc-comp.out; inc; ref; ctl book=hbA; }
sc_exp_oldver_fasl_ok() { # stale expansion file next to a good compiled file: the compiled file must win
  _expAB; cp A.exp book@expansion.lsp; mt_like book@expansion.lsp book.cert 9; inc; ref; ctl book=hbA; }

# ---------- saved images
_img() { # certify A, include it, save an image; then replace all artifacts on disk by B's
  put hbA; cert
  printf '%s\n(include-book "book")\n:q\n(save-exec "zimg" nil)\n' "$QUIET" > save.lsp; TMO=600 run_acl2 save.lsp save.out
  [ -x zimg ] || echo "no image" >> setup.err
  put hbB; cert; }
sc_img_restart()     { _img; INC='(cw "restarted~%")' INCIMG=./zimg inc; ref book=hbA; ctl book=hbB; }
sc_img_reinclude()   { _img; INCIMG=./zimg inc; ref; ctl book=hbA; }
sc_img_undo_reinclude() { _img; PRE=':ubt! 1' INCIMG=./zimg inc; ref; ctl book=hbA; }
sc_img_certify_on_top() { # in the restarted image (A in the world, B on disk) certify a book whose theorem holds only for A; then include it in a new session
  _img; printf '(in-package "ACL2")\n(defthm t2 (equal (f 0) 1001) :rule-classes nil)\n' > top2.lisp
  CERTIMG=./zimg cert top2 || rm -f setup.err; ls top2.cert
  T2='(cw "@Q t2 ~x0~%" (list (f 0) (getpropc (quote t2) (quote theorem) nil (w state))))'
  INC='(include-book "top2")' POST=$T2 inc; POST=$T2 ref; ctl book=hbA; }

# ---------- generated books (synth), copied once into synth-books/
_syn() { cp "$ROOT/synth-books/$1/book.lisp" book.lisp; cp "$ROOT/synth-books/s11/queries.lisp" queries.lisp; }
sc_syn_base()        { _syn s11; cert; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11m/book; }
sc_syn_fasl_missing(){ _syn s11; cert; rm book.$FX; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11m/book; }
sc_syn_fasl_mutant() { # compiled file of a mutant (two constants changed, same length) under the certified original
  _syn s11m; cert; cp -p book.$FX M.$FX; _syn s11; cert; cp M.$FX book.$FX; mt_like book.$FX book.cert 5; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11m/book; }
sc_syn_fasl_otherseed() { # compiled file of another seed's book (same function names, unrelated bodies)
  _syn s12; cert; cp -p book.$FX M.$FX; _syn s11; cert; cp M.$FX book.$FX; mt_like book.$FX book.cert 5; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11m/book; }
sc_syn_src_mutant_samestamp() { _syn s11; cert; touch -r book.lisp stamp; _syn s11m; touch -r stamp book.lisp; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11/book; }
sc_syn_cert_otherhost() { _syn s11; CERTIMG=$OACL2 cert; rm -f book.$OFX; Q=queries inc; Q=queries ref; Q=queries ctl book=../synth-books/s11m/book; }

# ---------- more natural (no hand-set mtimes) flows
sc_cert_otherhost_oldfasl_natural() { # this host certifies A; the source becomes B; the other host certifies B at once.  No touch.
  put hbA; cert; put hbB; CERTIMG=$OACL2 cert; stat -f '%N %Sm' -t '%H:%M:%S' book.*; inc; ref; ctl book=hbA; }
sc_portcullis_book_changed() { # top2 is certified in a world that included book (A); book then becomes B and is recertified
  put hbA; cert; printf '(in-package "ACL2")\n(defthm t2 (equal (f 0) 1001) :rule-classes nil)\n' > top2.lisp
  CERTPRE='(include-book "book")' cert top2; put hbB; touch -A 05 book.lisp; CERTPRE= cert
  T2='(cw "@Q t2 ~x0~%" (list (f 0) (getpropc (quote t2) (quote theorem) nil (w state))))'
  INC='(include-book "top2")' POST=$T2 inc; POST=$T2 ref; ctl book=hbA; }

# ---------- local definitions and locally included books must leave nothing behind
LQS='(defconst *lqc* 5) (defmacro lqm (x) (list (quote list) x 77)) (defun q (x) (declare (xargs :guard t)) (cons x (quote mine))) (defun q2 (x) (declare (xargs :guard t)) (cons x (quote mine2))) (defun q3 (x) (declare (xargs :guard t)) (cons x (quote mine3))) (defun-inline qi (x) (declare (xargs :guard t)) (cons x (quote mine-inline)))'
# the reference admits only the book's non-local events (ld does not skip local ones)
LTNL="(defun lt (x) (declare (xargs :guard t)) (cons x 'lt)) (defun lt2 (x) (declare (xargs :guard t)) (cons x 'lt2))"
_ltop() { put lq lq; put ltop ltop; cert lq; cert ltop; }
sc_local_leftover()  { # after the include the session defines the names the book only had locally
  _ltop; TOP=ltop Q=lqq MID=$LQS inc; TOP=ltop Q=lqq MID=$LQS REFLD=$LTNL ref; }
sc_local_predef()    { # the session defines those names first (other bodies), then includes
  _ltop; TOP=ltop Q=lqq PRE=$LQS inc; TOP=ltop Q=lqq PRE=$LQS REFLD=$LTNL ref; }
sc_fasl_oldver_cp_p() { # B certified elsewhere first; A certified here later; B's source and cert copied in with cp -p
  mkdir server; (cd server; put hbB; cert); sleep 2; put hbA; cert; cp -p server/book.lisp server/book.cert .; inc; ref; ctl book=hbA; }
