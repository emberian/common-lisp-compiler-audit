(in-package "ACL2")
(cw "@Q cst ~x0~%" (list (call-cst 3) (cst 4)))
(cw "@W cst ~x0~%" (getpropc 'cst 'attachment nil (w state)))
(cw "@END~%")
