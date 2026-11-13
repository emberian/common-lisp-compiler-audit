; Probe 8: aref1/aset1/compress1 raw vs logic (differential on same terms).
; Raw: top-level evaluation uses the registered-vector fast path.
; Logical: defthm via executable-counterpart uses the *1* (alist) defs.

(defconst *a-none*
  '((:HEADER :DIMENSIONS (4) :MAXIMUM-LENGTH 8 :DEFAULT 0 :NAME foo :ORDER :none)
    (0 . 10) (1 . 20) (2 . 0) (3 . 40)))

(defconst *a-asc*
  '((:HEADER :DIMENSIONS (4) :MAXIMUM-LENGTH 8 :DEFAULT 0 :NAME bar :ORDER <)
    (0 . 10) (1 . 20) (3 . 40)))

(defconst *a-desc*
  '((:HEADER :DIMENSIONS (4) :MAXIMUM-LENGTH 8 :DEFAULT 0 :NAME baz :ORDER >)
    (3 . 40) (1 . 20) (0 . 10)))

; register the arrays (raw compress1)
(compress1 'foo *a-none*)
(compress1 'bar *a-asc*)
(compress1 'baz *a-desc*)

; ---- RAW reads ----
(list (aref1 'foo *a-none* 0) (aref1 'foo *a-none* 2) (aref1 'foo *a-none* 3))
(list (aref1 'bar *a-asc* 1) (aref1 'bar *a-asc* 2) (aref1 'bar *a-asc* 3))
(list (aref1 'baz *a-desc* 0) (aref1 'baz *a-desc* 2) (aref1 'baz *a-desc* 3))

; ---- RAW writes + reads ----
(aset1 'foo *a-none* 2 99)
(aref1 'foo *a-none* 2)
(aset1 'foo *a-none* 0 0)   ; write a DEFAULT value: logically the pair stays
(aref1 'foo *a-none* 0)
(aset1 'bar *a-asc* 2 77)
(aref1 'bar *a-asc* 2)
(aset1 'baz *a-desc* 1 0)   ; default write into a >-ordered array
(aref1 'baz *a-desc* 1)

; ---- LOGICAL equivalents ----
(defthm aref-none-log
  (equal (list (aref1 'foo *a-none* 0) (aref1 'foo *a-none* 2)
               (aref1 'foo *a-none* 3))
         '(10 0 40))
  :rule-classes nil)

(defthm aref-asc-log
  (equal (list (aref1 'bar *a-asc* 1) (aref1 'bar *a-asc* 2)
               (aref1 'bar *a-asc* 3))
         '(20 0 40))
  :rule-classes nil)

(defthm aset-none-log
  (equal (list (aref1 'foo (aset1 'foo *a-none* 2 99) 2)
               (aref1 'foo (aset1 'foo (aset1 'foo *a-none* 2 99) 0 0) 0))
         '(99 0))
  :rule-classes nil)

(defthm aset-asc-log
  (equal (aref1 'bar (aset1 'bar *a-asc* 2 77) 2) 77)
  :rule-classes nil)

(defthm aset-desc-log
  (equal (aref1 'baz (aset1 'baz *a-desc* 1 0) 1) 0)
  :rule-classes nil)

; ---- maximum-length tripwire: order-:none array, length reaching max-length ----
; dimensions 3, maximum-length 3, order :none: 3 pairs + header = length 4 > 3?
(defconst *a-tight*
  '((:HEADER :DIMENSIONS (3) :MAXIMUM-LENGTH 3 :DEFAULT 0 :NAME tgh :ORDER :none)
    (0 . 5) (1 . 6) (2 . 7)))
(compress1 'tgh *a-tight*)
(aset1 'tgh *a-tight* 1 8)   ; length 4+1=5 > 3? alist already 4 long > max 3
(quit)
