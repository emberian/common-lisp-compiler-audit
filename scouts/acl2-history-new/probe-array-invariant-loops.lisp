(in-package "ACL2")
; 7.2 array invariant-risk: direct original and newer loop$ routes.
(defconst *ab*
  (list (compress1 'a '((:header :dimensions (4) :maximum-length 6
                                 :default 0 :name a)
                        (0 . 0) (1 . 0) (2 . 0) (3 . 0)))
        (compress1 'b '((:header :dimensions (4) :maximum-length 6
                                 :default 9 :name b)
                        (0 . 9) (1 . 9) (2 . 9) (3 . 9)))))
(defconst *b* (cadr *ab*))
(defthm lemma (equal (aref1 'b *b* 0) 9) :rule-classes nil)
(defun poke-direct (i v)
  (declare (xargs :mode :program))
  (aset1 'a (car *ab*) i v))
(value-triple (poke-direct 10 'boom-direct))
(assert-event (equal (aref1 'b *b* 0) 9))

(defun poke-for (i v)
  (declare (xargs :mode :program))
  (loop$ for j from 0 to 0 collect (prog2$ j (aset1 'a (car *ab*) i v))))
(value-triple (poke-for 10 'boom-for))
(assert-event (equal (aref1 'b *b* 0) 9))

(defun poke-do (i v)
  (declare (xargs :mode :program))
  (loop$ with ans = nil
         do (progn (setq ans (aset1 'a (car *ab*) i v))
                   (return ans))))
(value-triple (poke-do 10 'boom-do))
(assert-event (equal (aref1 'b *b* 0) 9))
(quit)
