(in-package "ACL2")

(make-event '(with-output :off :all (defconst *c1* '42)))
(make-event '(with-prover-step-limit 1000 (defconst *c2* '99)))
(make-event '(with-guard-checking-event nil (defconst *c3* '77)))
(make-event '(defconst *c4* '88))
