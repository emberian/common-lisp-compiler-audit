(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "centaur/misc/fast-cons-memo" :dir :system :ttags :all :uncertified-okp t)
:q
(setf *debugger-hook* nil)
(let ((cell (cons 'orig-car 'orig-cdr)))
  (with-fast-cons-memo
    :fnname outer-test
    :return-vals (u)
    :restore-array outer-arr
    :initial-size 8
    :body (progn
            (setq outer-arr (mark-visited-cons cell :smashed-memo outer-arr))
            (with-fast-cons-memo
              :fnname inner-test
              :return-vals (v)
              :restore-array inner-arr
              :initial-size 8
              :body :inner-done)))
  (format t "~%[FCM-AFTER-NESTED: ~S]~%" cell))
(quit)
