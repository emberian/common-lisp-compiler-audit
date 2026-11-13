(in-package "ACL2")
(make-event
 (mv-let (ch state) (open-input-channel "data.txt" :object state)
   (mv-let (eof obj state) (read-object ch state)
     (declare (ignore eof))
     (let ((state (close-input-channel ch state)))
       (value `(defconst *payload* ',obj)))))
 :check-expansion t)
