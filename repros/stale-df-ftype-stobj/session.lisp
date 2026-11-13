; Same root cause as F13 (a proclaim-dfs ftype outlives undo), reached through
; a stobj field: the accessor of a double-float field is proclaimed to return a
; double-float; after undo the same field name holds an integer.
(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment error)))
(defstobj zst2 (zfld :type double-float :initially 0))
(u)
(defstobj zst2 (zfld :type (unsigned-byte 129) :initially 0))
(defun zread-nogv (zst2) (declare (xargs :stobjs zst2 :verify-guards nil)) (+ 1 (zfld zst2)))
(defun zread-gv (zst2) (declare (xargs :stobjs zst2)) (+ 1 (zfld zst2)))
(cw "@CLASS ~x0~%" (getpropc 'zread-gv 'symbol-class nil (w state)))
(cw "@LOGIC ~x0~%" (zread-nogv zst2))
(cw "@RAW ~x0~%" (zread-gv zst2))
(cw "@END~%")
