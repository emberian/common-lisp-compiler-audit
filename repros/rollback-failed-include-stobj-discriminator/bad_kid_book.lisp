(in-package "ACL2")

(defstobj kid (bad-fld :type integer :initially 0)
  :renaming ((create-kid create-bogus-st)))
