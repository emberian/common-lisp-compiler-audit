(in-package "ACL2")

(cw "~%=== H42 CERTIFICATE HASH INCLUDES PORTCULLIS AND EXPANSION ===~%")
(assign book-hash-alistp nil)
(mv-let (erp1 base state)
  (book-hash nil "ignored-book-name" nil nil nil nil state)
  (mv-let (erp2 changed-portcullis state)
    (book-hash nil "ignored-book-name"
               '((add-include-book-dir :x "/tmp")) nil nil nil state)
    (mv-let (erp3 changed-expansion state)
      (book-hash nil "ignored-book-name" nil '((0 . (defstobj s fld))) nil nil
                 state)
      (mv (list (list erp1 base)
                (list erp2 changed-portcullis)
                (list erp3 changed-expansion)
                :portcullis-equal (equal base changed-portcullis)
                :expansion-equal (equal base changed-expansion))
          state))))

(quit)
