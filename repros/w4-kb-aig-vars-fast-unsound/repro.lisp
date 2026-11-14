(in-package "ACL2")
(set-debugger-enable :never)
(ld "std/package.lsp" :dir :system)
(defpkg "FTY" (union-eq *acl2-exports* *common-lisp-symbols-from-main-lisp-package*))
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(include-book "centaur/aig/aig-vars-fast" :dir :system :ttags :all :uncertified-okp t)

;; 1. Soundness bug (a): aig-vars-unordered-list returns NIL on atom 'a in :logic,
;;    but raw Lisp branches on (true-listp x) and returns '(A) on 'a!
(defthm nil-proved-avul-atom
  nil
  :rule-classes nil
  :hints (("Goal"
           :use ((:instance (:executable-counterpart aig-vars-unordered-list)
                            (x 'a)))
           :in-theory (enable aig-vars-unordered-list))))

;; 2. Soundness bug (b): missing hons-copy + :test 'eql hash-table deduplication
;;    returns 2 duplicate strings on (list (coerce '(#\v) 'string) "v"), whereas :logic returns 1.
(defthm nil-proved-avul-strings
  nil
  :rule-classes nil
  :hints (("Goal"
           :use ((:instance (:executable-counterpart len)
                            (x (aig-vars-unordered-list
                                (list (coerce '(#\v) 'string) "v")))))
           :in-theory (enable aig-vars-unordered-list))))

;; 3. Guard-verified raw Lisp crash on valid cons AIG variables ((nil . 2) . (nil . 1))
;;    via alphorder-sort -> atom< -> bad-atom<=.
(defun trigger-bad-atom (x)
  (declare (xargs :guard t))
  (aig-vars-fast x))

;; 4. Guard-verified raw Lisp zero-length array OOB in aigtab-collect-vars when queue=nil.
(defun trigger-empty-queue ()
  (declare (xargs :guard t))
  (aigtab-collect-vars nil nil))

(cw "~%[AVUL-ATOM-RAW: ~x0]~%" (aig-vars-unordered-list 'a))
(cw "~%[AVUL-STRINGS-RAW: ~x0]~%" (aig-vars-unordered-list (list (coerce '(#\v) 'string) "v")))
:q
(handler-case (acl2::trigger-bad-atom '((nil . 2) . (nil . 1)))
  (error (e) (format t "~%[AIG-BAD-ATOM-CRASH: ~A]~%" e)))
(handler-case (acl2::trigger-empty-queue)
  (error (e) (format t "~%[AIGTAB-EMPTY-QUEUE-CRASH: ~A]~%" e)))
(quit)
