; Probe 9: aset1 on an :order :none array at exactly maximum-length.
; Logically aset1 returns (compress1 l') and compress1 with order :none is
; (prog2$ <hard-error check> l) = l'.  Raw: compress1 hard-errors.
; Is the guard-legal call an error where the logic returns a value?

(defconst *a-tight*
  '((:HEADER :DIMENSIONS (3) :MAXIMUM-LENGTH 4 :DEFAULT 0 :NAME tgh :ORDER :none)
    (0 . 5) (1 . 6) (2 . 7)))

(array1p 'tgh *a-tight*)   ; sanity: expect T
(length *a-tight*)        ; 4 = maximum-length

; logical claim: aset1 past the bound returns the pushed alist
(defthm aset-tight-log
  (equal (aset1 'tgh *a-tight* 1 9)
         '((1 . 9)
           (:HEADER :DIMENSIONS (3) :MAXIMUM-LENGTH 4 :DEFAULT 0 :NAME tgh :ORDER :none)
           (0 . 5) (1 . 6) (2 . 7)))
  :rule-classes nil)

; raw: register and then write (to-go is 0 right after compress1)
(compress1 'tgh *a-tight*)
(aset1 'tgh *a-tight* 1 9)

; also check the ordered variants at the boundary (order < and >): the
; to-go=0 branch rebuilds instead of erroring; compare with logic
(defconst *b-tight*
  '((:HEADER :DIMENSIONS (3) :MAXIMUM-LENGTH 4 :DEFAULT 0 :NAME tgi :ORDER <)
    (0 . 5) (1 . 6) (2 . 7)))
(compress1 'tgi *b-tight*)
(aset1 'tgi *b-tight* 2 8)
(aref1 'tgi (aset1 'tgi *b-tight* 2 8) 2)

(defthm aset-tight-asc-log
  (equal (aref1 'tgi (aset1 'tgi *b-tight* 2 8) 2) 8)
  :rule-classes nil)

(quit)
