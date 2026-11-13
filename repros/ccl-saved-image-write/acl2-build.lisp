; Minimal ACL2 reproducer, build half: ordinary user steps only.
(defstobj zst
  (zar :type (array (unsigned-byte 8) (4)) :initially 0)
  (zsc :type (signed-byte 30) :initially 0))
(update-zari 2 7 zst)
(update-zsc 5 zst)
(cw "@before zar[2]=~x0 zsc=~x1~%" (zari 2 zst) (zsc zst))
:q
(save-exec "zimg" nil)
