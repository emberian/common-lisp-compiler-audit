; Probe 13b: after :ubt! + redefinition with a different layout, is the new
; live stobj a fresh object (expected) or the old vector reinterpreted?

(defstobj ub (u1 :type integer :initially 1) (u2 :type integer :initially 2))
(update-u1 99 ub)
(u1 ub)
(ubt! 1)
(defstobj ub
  (u1 :type integer :initially 5)
  (u2 :type string  :initially "x")
  (u3 :type (array t (4)) :initially nil))
(u1 ub)        ; expect 5 (fresh); 99 or garbage would mean object reuse
(u2 ub)        ; expect "x"
(u3i 0 ub)     ; expect nil
(ubp ub)       ; expect T

; logical counterpart
(thm (equal (list (u1 ub) (u2 ub) (u3i 0 ub))
            (list (u1 (create-ub)) (u2 (create-ub)) (u3i 0 (create-ub))))
     :rule-classes nil)

(quit)
