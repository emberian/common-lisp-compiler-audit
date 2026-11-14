;; Positive-detection validation suite: confirms that our soundness oracle
;; catches all 4 newly discovered soundness bug classes!

(defun check-soundness-bug-probe (probe-id val-verified val-logic)
  (declare (xargs :mode :program))
  (if (not (equal val-verified val-logic))
      (cw "XDS-CONFIRMED-BUG|PROBE=~s0|VERIFIED=~x1|LOGIC=~x2~%"
          probe-id val-verified val-logic)
    (cw "XDS-PROBE-MISSED|PROBE=~s0|VAL=~x1~%" probe-id val-verified)))

;; Probe 1: translate11-flet drops outer known-dfs
(defun probe-flet-df-v ()
  (declare (xargs :guard t))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (flet ((id (y) y))
      (and (id t) (equal x 1)))))

(defun probe-flet-df-u ()
  (declare (xargs :verify-guards nil))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (flet ((id (y) y))
      (and (id t) (equal x 1)))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG1-FLET-KNOWN-DFS"
                                       (probe-flet-df-v)
                                       (probe-flet-df-u))))
   (declare (ignore ign))
   '(value-triple :ok)))

;; Probe 2: translate11-macrolet drops outer known-dfs
(defun probe-macrolet-df-v ()
  (declare (xargs :guard t))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (macrolet ((m (y) y))
      (and (m t) (equal x 1)))))

(defun probe-macrolet-df-u ()
  (declare (xargs :verify-guards nil))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (macrolet ((m (y) y))
      (and (m t) (equal x 1)))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG1B-MACROLET-KNOWN-DFS"
                                       (probe-macrolet-df-v)
                                       (probe-macrolet-df-u))))
   (declare (ignore ign))
   '(value-triple :ok)))

;; Probe 3: translate11-collecting-known-dfs retry branch drops outer known-dfs in MV-LET
(defun probe-rec-mv-df-v (n d)
  (declare (type double-float d)
           (xargs :guard (natp n)))
  (if (not (zp n))
      (mv-let (a b)
        (probe-rec-mv-df-v (- n 1) d)
        (mv a (or b (equal d 1))))
    (mv 0 nil)))

(defun probe-rec-mv-df-u (n d)
  (declare (type double-float d)
           (xargs :guard (natp n) :verify-guards nil))
  (if (not (zp n))
      (mv-let (a b)
        (probe-rec-mv-df-u (- n 1) d)
        (mv a (or b (equal d 1))))
    (mv 0 nil)))

(make-event
 (mv-let (a1 b1) (probe-rec-mv-df-v 1 (to-df 1))
   (declare (ignore a1))
   (mv-let (a2 b2) (probe-rec-mv-df-u 1 (to-df 1))
     (declare (ignore a2))
     (let ((ign (check-soundness-bug-probe "BUG2-MVLET-RETRY-KNOWN-DFS" b1 b2)))
       (declare (ignore ign))
       '(value-triple :ok)))))

;; Probe 4: FOR loop$ of-type double-float reinterprets boxed bignum (expt 2 100) as raw IEEE-754 float
(defun probe-for-df-v (k)
  (declare (xargs :guard (equal k 100)))
  (let ((lst (list (expt 2 k))))
    (loop$ for x of-type double-float in lst
           collect (from-df (df+ x (to-df 0))))))

(defun probe-for-df-u (k)
  (declare (xargs :guard (equal k 100) :verify-guards nil))
  (let ((lst (list (expt 2 k))))
    (loop$ for x of-type double-float in lst
           collect (from-df (df+ x (to-df 0))))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG3-LOOP-FOR-OFTYPE-DF"
                                       (probe-for-df-v 100)
                                       (probe-for-df-u 100))))
   (declare (ignore ign))
   '(value-triple :ok)))

;; Probe 5a & 5b: DO loop$ translate-with-var-tuples known-dfs shadowing bugs
(defthm probe-ev$-on-quoted-cons
  (implies (and (syntaxp (quotep x))
                (tamep x)
                (consp x)
                (not (equal (car x) 'quote))
                (not (equal (car x) 'if))
                (not (equal (car x) 'apply$))
                (not (equal (car x) 'ev$)))
           (equal (ev$ x a)
                  (apply$ (car x) (ev$-list (cdr x) a))))
  :hints (("Goal" :expand ((ev$ x a)))))

(defthm probe-ev$-on-quoted-var-or-quote
  (and (implies (and (syntaxp (quotep x)) (tamep x) (symbolp x))
                (equal (ev$ x a) (cdr (assoc-equal x a))))
       (implies (and (syntaxp (quotep x)) (tamep x) (consp x) (equal (car x) 'quote))
                (equal (ev$ x a) (cadr x))))
  :hints (("Goal" :expand ((ev$ x a)))))

(defthm probe-dfp-df+-0
  (implies (dfp y) (dfp (binary-df+ y 0))))

(defun probe-do-df-shadow-a-u (k)
  (declare (xargs :guard (equal k 100) :verify-guards nil))
  (let ((v (expt 2 k)))
    (loop$ with v of-type double-float = v
           do :measure (acl2-count 0)
           (return (from-df (df+ v (to-df 0)))))))

(make-event `(defconst *probe-do-a-logic* ',(probe-do-df-shadow-a-u 100)))

(defun probe-do-df-shadow-a-v (k)
  (declare (xargs :guard (equal k 100)
                  :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (let ((v (expt 2 k)))
    (loop$ with v of-type double-float = v
           do :measure (acl2-count 0)
           (return (from-df (df+ v (to-df 0)))))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG4A-DO-WITH-PREMATURE-KNOWN-DFS"
                                       (probe-do-df-shadow-a-v 100)
                                       *probe-do-a-logic*)))
   (declare (ignore ign))
   '(value-triple :ok)))

(defun probe-do-df-shadow-b-u (x)
  (declare (type double-float x)
           (xargs :verify-guards nil))
  (prog2$
   (from-df x)
   (loop$ with x = (expt 2 100)
          with y of-type double-float = x
          do :measure (acl2-count 0)
          (return (from-df (df+ y (to-df 0)))))))

(make-event `(defconst *probe-do-b-logic* ',(probe-do-df-shadow-b-u (to-df 0))))

(defun probe-do-df-shadow-b-v (x)
  (declare (type double-float x)
           (xargs :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (prog2$
   (from-df x)
   (loop$ with x = (expt 2 100)
          with y of-type double-float = x
          do :measure (acl2-count 0)
          (return (from-df (df+ y (to-df 0)))))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG4B-DO-WITH-UNREMOVED-KNOWN-DFS"
                                       (probe-do-df-shadow-b-v (to-df 0))
                                       *probe-do-b-logic*)))
   (declare (ignore ign))
   '(value-triple :ok)))

;; Probe 6: translate11-do-clause stobjs-out=t compiles unboxed binary-df+ on boxed alist entry into *cl-cache*!
(defun probe-legal-do-df-u ()
  (declare (xargs :verify-guards nil))
  (loop$ with z of-type double-float = (to-df (expt 2 100))
         do :measure (acl2-count 0)
         (return (from-df (df+ z (to-df 0))))))

(make-event `(defconst *probe-do-cache-before* ',(probe-legal-do-df-u)))

(defun probe-legal-do-df-v ()
  (declare (xargs :guard t
                  :guard-hints (("Goal" :in-theory (e/d (apply$ apply$-lambda ev$-list (:e tamep) apply$-primp apply$-prim do-body-guard-wrapper return-last)
                                                        (ev$ dfp binary-df+ from-df to-df lex-fix l< assoc-eq-safe))))))
  (loop$ with z of-type double-float = (to-df (expt 2 100))
         do :measure (acl2-count 0)
         (return (from-df (df+ z (to-df 0))))))

(make-event
 (let ((ign (check-soundness-bug-probe "BUG5-DO-CLAUSE-LAMBDA-CL-CACHE"
                                       (probe-legal-do-df-u)
                                       *probe-do-cache-before*)))
   (declare (ignore ign))
   '(value-triple :ok)))

;; Probe 7: Plain FOR loop$ with compound of-type (member / or / complex / atom / real / string k / null / standard-char)
;; produces an ill-formed LAMBDA object, causing special-loop$-scion-callp AND collect-certain-lambda-objects to return NIL
;; and completely drop BOTH Special Conjecture (a)/(b) AND the loop$ body's own guard obligations!
(defun probe-loop-member-v (x)
  (declare (xargs :guard t))
  (let ((lst (list (cons x x))))
    (car (loop$ for z of-type (member :a :b) in lst
                collect (eq z '(0 . 0))))))

(defun probe-loop-member-u (x)
  (declare (xargs :verify-guards nil))
  (let ((lst (list (cons x x))))
    (car (loop$ for z of-type (member :a :b) in lst
                collect (eq z '(0 . 0))))))

(make-event
 (mv-let (erp uval state)
   (with-guard-checking-error-triple :none
     (trans-eval '(probe-loop-member-u 0) 'probe state t))
   (declare (ignore erp))
   (let ((ign (check-soundness-bug-probe "BUG6-PLAIN-LOOP-DROPPED-OFTYPE-AND-BODY-GUARD"
                                         (probe-loop-member-v 0)
                                         (cdr uval))))
     (declare (ignore ign))
     (value '(value-triple :ok)))))

:q
