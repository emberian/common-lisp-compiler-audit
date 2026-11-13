(in-package "ACL2")
; NOTE-8-6 original guard-theorem route with a non-standard ACL2 character.
(defconst *nonstandard-name* (coerce (list (code-char 255)) 'string))
(assert-event (equal (char-code (code-char 255)) 255))
(defthm bad-open-input (implies (state-p state) nil) :rule-classes nil
  :hints (("Goal" :use (:instance (:guard-theorem open-input-channel)
                                  (file-name *nonstandard-name*)
                                  (typ :character)
                                  (state-state state)))))
(defthm bad-open-output (implies (state-p state) nil) :rule-classes nil
  :hints (("Goal" :use (:instance (:guard-theorem open-output-channel)
                                  (file-name *nonstandard-name*)
                                  (typ :character)
                                  (state-state state)))))
(quit)
