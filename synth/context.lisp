;;;; Context envelope: the events around the definitions, drawn per book (swarm).
;;;
;;; Every feature is neutral for the meaning of the functions; it changes the
;;; state in which ACL2 translates, admits, compiles, certifies and re-loads them.
;;;   :ignore      :ok    (set-ignore-ok t) in the book
;;;                :decl  no setter; every unused binding is declared IGNORABLE
;;;   :irrelevant  t | :warn, argument of set-irrelevant-formals-ok
;;;   :setters     ((event position) ...), position :before | :mid | :after the functions
;;;   :sub         NIL | :plain (first half of the events live in an included sub-book)
;;;                | :local (an unrelated sub-book with its own defaults and macros,
;;;                included locally)
;;;   :port        T: certify in a non-empty world (portcullis.lisp, run before the book)
;;;   :stobj-inline T: the stobj is defined with :INLINE T
;;;   :all-styles  names of functions also emitted once per style in *STYLES*; the
;;;                query requires all copies to agree
;;;   :mv-as-list  (metamorphic variants only) names of MV functions emitted as
;;;                returning a list, with their callers rewritten

(defparameter *neutral-setters*
  '((set-state-ok t) (set-compile-fns t) (set-compile-fns nil)
    (set-verify-guards-eagerness 0) (set-verify-guards-eagerness 1)
    (set-verify-guards-eagerness 2)
    (set-bogus-mutual-recursion-ok t) (set-bogus-defun-hints-ok t)
    (set-ruler-extenders :all) (set-ruler-extenders :lambdas) (set-ruler-extenders :basic)
    (set-well-founded-relation o<) (set-measure-function acl2-count)
    (set-non-linearp t) (set-let*-abstractionp t) (set-match-free-default :once)
    (set-tau-auto-mode nil) (set-backchain-limit 100) (set-default-backchain-limit 100)
    (set-rewrite-stack-limit 500) (set-case-split-limitations '(100 50))
    (set-induction-depth-limit 5) (set-enforce-redundancy nil) (set-default-hints nil)
    (set-prover-step-limit 100000) (set-inhibit-warnings "Subsume")
    (set-bogus-measure-ok t)))

(defun random-context (p)
  (list :ignore (if (chance 60) :ok :decl)
        :irrelevant (if (chance 70) t :warn)
        :setters (loop for s in *neutral-setters*
                       when (chance 12) collect (list s (pick '(:before :mid :after))))
        :sub (case (rnd 6) (0 :plain) (1 :local) (t nil))
        :port (chance 20)
        :stobj-inline (chance 50)
        :all-styles (loop for f in (prog-fns p)
                          when (and (not (fn-clique f)) (not (member :st (fn-ptypes f)))
                                    (not (fn-inline f)) (chance 15))
                            collect (fn-name f))))
