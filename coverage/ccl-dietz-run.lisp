;;; Run Paul Dietz's random integer-form tester under the CCL coverage hooks.
;;;   cd /Users/ember/dev/ansi-test && CCOV_N=20000 CCOV_OUT=/path/out.sexp \
;;;     darm64cl -n --batch --load /Users/ember/dev/compiler-audit/coverage/ccl-dietz-run.lisp
;;; The tester is loaded first and the counters are reset after the hooks go
;;; in, so the dump covers only the tester's own COMPILE calls.
(load "/Users/ember/dev/compiler-audit/dietz/load.lisp")
(load "/Users/ember/dev/compiler-audit/coverage/ccl-cov.lisp")
(in-package :cl-test)
(let* ((n (parse-integer (cl-user::env "CCOV_N" "200")))
       (size (parse-integer (cl-user::env "DIETZ_SIZE" "100")))
       (nvars (parse-integer (cl-user::env "DIETZ_NVARS" "3")))
       (out (cl-user::env "CCOV_OUT" "/Users/ember/dev/compiler-audit/coverage/data/ccl-dietz.sexp"))
       (*random-state* (make-random-state t))
       (start (get-universal-time))
       (raw nil))
  (ccov:reset)
  (setq raw (handler-bind ((warning #'muffle-warning))
              (test-random-integer-forms size nvars n :random-size t :random-nvars t)))
  (ccov:dump out)
  (format t "~&CCOV-RUN impl=~A ~A forms=~D raw-failures=~D seconds=~D calls=~S~%"
          (lisp-implementation-type) (lisp-implementation-version)
          n (length raw) (- (get-universal-time) start) ccov::*calls*))
(ccl:quit 0)
