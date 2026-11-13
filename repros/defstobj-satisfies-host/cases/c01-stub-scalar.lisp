(defstub p (x) nil)
(defstobj st (fld :type (or null (satisfies p)) :initially nil))
(cw "RESULT ~x0~%" (fld st))
