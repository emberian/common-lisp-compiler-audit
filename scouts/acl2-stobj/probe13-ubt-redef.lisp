; Probe 13: :ubt then redefinition of a stobj with a different layout while
; the raw live object persists.  Expect: "Illegal attempt to redeclare the
; single-threaded object" unless in raw mode.

(defstobj ub (u1 :type integer :initially 1) (u2 :type integer :initially 2))
(update-u1 99 ub)
(u1 ub)

(ubt! 1)   ; undo back before the defstobj (world only; raw object persists)

; now redefine with a DIFFERENT layout (3 fields, different types)
(defstobj ub
  (u1 :type integer :initially 5)
  (u2 :type string  :initially "x")
  (u3 :type (array t (4)) :initially nil))

(quit)
