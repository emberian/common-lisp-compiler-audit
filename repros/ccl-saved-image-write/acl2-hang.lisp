; Run in the saved image: one array write to the stobj that existed before save-exec.
(update-zari 1 9 zst)
(cw "@array-write returned zar=~x0~%" (list (zari 0 zst) (zari 1 zst) (zari 2 zst) (zari 3 zst)))
(quit)
