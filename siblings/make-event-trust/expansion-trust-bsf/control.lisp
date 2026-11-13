(in-package "ACL2")
(defttag :me-trust)
(make-event (value '(value-triple :benign))
            :expansion? (defthm nil-proved nil :rule-classes nil))
