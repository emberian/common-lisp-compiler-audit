(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "tools/plev-ccl" :dir :system :ttags :all)
(include-book "tools/advise" :dir :system :ttags :all)

(defun my-id (x)
  (declare (xargs :guard t))
  x)

;; 1. advise-raw.lsp: advisedp$-fn discards (eval `(ccl::advisedp ...)) and
;;    unconditionally returns NIL on CCL; on SBCL it is #-Clozure-only so
;;    advisedp$ falls through to the stub hard error.
(advise$ 'my-id 'x :when :before :name 'test-adv)
(cw "~%[ADVISEDP-RESULT: ~x0]~%" (advisedp$ 'my-id :when :before :name 'test-adv))

;; 2. plev-ccl-raw.lsp: plev-fn sets *print-length* to 'not-an-integer without
;;    type validation, corrupting the host CL printer.
(plev :length 'not-an-integer)
(cw "~%[AFTER-PLEV: ~x0]~%" '(1 2 3))
(quit)
