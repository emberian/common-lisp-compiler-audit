(ld "df-floor.lisp")
(thm (equal (zdf-floor (to-df 5/2)) 2))
(cw "@AFTER-THM~%")
:q
(print (sb-kernel:%simple-fun-type (symbol-function 'zdf-floor)))
(print (sb-int:info :function :type 'zdf-floor))
(print (sb-int:info :function :type 'zrat-floor))
