(in-package "ACL2")
(set-debugger-enable :never)
(include-book "centaur/misc/fast-cons-memo" :dir :system :ttags :all :uncertified-okp t)
:q
(let ((cell (cons 'orig-car 'orig-cdr)))
  (with-fast-cons-memo
    :fnname outer-test
    :return-vals (u)
    :restore-array outer-arr
    :initial-size 8
    :body (progn
            (setq outer-arr (mark-visited-cons cell :smashed-memo outer-arr))
            ;; Inner with-fast-cons-memo overwrites global *fast-cons-memo-array*,
            ;; so outer exit restores inner-arr instead of outer-arr, leaving
            ;; CELL permanently corrupted!
            (with-fast-cons-memo
              :fnname inner-test
              :return-vals (v)
              :restore-array inner-arr
              :initial-size 8
              :body :inner-done)))
  (format t "~%[FCM-AFTER-NESTED: ~S]~%" cell))
(quit)
