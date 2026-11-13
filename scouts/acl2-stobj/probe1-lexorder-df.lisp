; Probe 1: raw lexorder/alphorder/merge-sort-lexorder on raw double-floats
; (reachable from :type double-float stobj fields via to-df).
; Logically to-df returns a rational, so lexorder on two to-df values takes
; the (<= x y) branch.  Raw: rationalp is nil for a raw double-float, so
; alphorder falls to the symbol branch -> symbol< on floats.

(defun df2 (x) (to-df x))

; Direct calls in the loop (guard-checked execution):
(lexorder (to-df #d1.5) (to-df #d2.5))
(alphorder (to-df #d1.5) (to-df #d2.5))
(alphorder 1 (to-df #d2.5))
(merge-sort-lexorder (list (to-df #d2.5) (to-df #d1.5) 7))
(quit)
