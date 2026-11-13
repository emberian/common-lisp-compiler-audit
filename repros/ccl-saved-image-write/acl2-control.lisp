; Run in the saved image: everything except an array write.
(cw "@read zar[2]=~x0 zsc=~x1~%" (zari 2 zst) (zsc zst))
(update-zsc 6 zst)
(cw "@scalar-write zsc=~x0~%" (zsc zst))
:q
#+ccl
(let* ((arr (svref (cdr (assoc 'acl2::zst acl2::*user-stobj-alist*)) 0))
       (pg (lambda (x) (logandc2 (ccl::%address-of x) 16383))))
  (format t "@pages array=~x update-zari-code=~x~%" (funcall pg arr) (funcall pg (ccl::uvref #'acl2::update-zari 0))))
(acl2::exit-lisp)
