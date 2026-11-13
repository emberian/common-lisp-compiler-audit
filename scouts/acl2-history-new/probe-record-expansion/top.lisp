(in-package "ACL2")
(include-book "sub-book-1")
(include-book "sub-book-2")
(defthm nil-is-true nil
  :hints (("Goal" :use (f-is-1 f-is-2) :in-theory nil))
  :rule-classes nil)
