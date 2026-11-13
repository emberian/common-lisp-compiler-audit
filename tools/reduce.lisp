;;; Test-case reducer for files of Lisp forms.
;;;
;;; Usage: sbcl --script reduce.lisp INPUT OUTPUT PREDICATE
;;;
;;; PREDICATE is an executable called with one argument, a candidate file; exit
;;; status 0 means the candidate is still interesting.  The reducer keeps the
;;; first top-level form (the in-package) and repeats two passes to a fixpoint:
;;;   1. drop top-level forms, in halving chunks then singly;
;;;   2. simplify inside the survivors: replace a subterm by one of its own
;;;      subterms, or by 0, NIL or T.
;;; Every accepted step is written to OUTPUT, so an interrupted run still leaves
;;; the smallest candidate found so far.

(defpackage :zr (:use :cl))
(in-package :zr)

(defvar *output*) (defvar *predicate*) (defvar *tests* 0)

(defun write-forms (forms path)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (let ((*package* (find-package :zr)) (*print-pretty* nil) (*print-case* :downcase)
          (*print-right-margin* 1000000))
      (dolist (f forms) (format s "~S~%" f)))))

(defun size (x) (if (consp x) (+ 1 (size (car x)) (size (cdr x))) 1))

(defun interesting-p (forms)
  (incf *tests*)
  (let ((candidate (format nil "~A.candidate" *output*)))
    (write-forms forms candidate)
    (zerop (sb-ext:process-exit-code
            (sb-ext:run-program *predicate* (list candidate) :output nil :error nil)))))

(defun accept (forms)
  (write-forms forms *output*)
  (format t "~&  kept: ~D forms, size ~D (~D tests)~%" (length forms) (size forms) *tests*)
  (finish-output)
  forms)

(defun drop-forms (forms)
  "Remove top-level forms after the first, by chunks of decreasing size."
  (let ((chunk (max 1 (floor (1- (length forms)) 2))))
    (loop
      (let ((i 1) (progress nil))
        (loop while (< i (length forms))
              do (let ((candidate (append (subseq forms 0 i)
                                          (subseq forms (min (length forms) (+ i chunk))))))
                   (if (and (< (length candidate) (length forms)) (interesting-p candidate))
                       (setf forms (accept candidate) progress t)
                       (incf i chunk))))
        (cond ((and (= chunk 1) (not progress)) (return forms))
              ((> chunk 1) (setf chunk (max 1 (floor chunk 2)))))))))

(defun replacements (term)
  "Simpler terms to try in place of TERM, smallest first."
  (remove-duplicates
   (append (unless (member term '(0 nil t)) (list 0 nil t))
           (when (consp term)
             (sort (copy-list (remove-if-not (lambda (x) (or (consp x) (integerp x) (symbolp x)))
                                             (cdr term)))
                   #'< :key #'size)))
   :test #'equal))

(defun subterm-paths (tree &optional path)
  "Paths (lists of CDR-then-CAR indices) to every argument position, outermost first."
  (when (and (consp tree) (listp (cdr tree)))
    (loop for arg in (cdr tree) for i from 1
          for p = (append path (list i))
          collect p
          append (when (and (consp arg) (ignore-errors (list-length arg)))
                   (subterm-paths arg p)))))

(defun get-at (tree path) (if path (get-at (nth (car path) tree) (cdr path)) tree))
(defun put-at (tree path new)
  (if path
      (let ((copy (copy-list tree)))
        (setf (nth (car path) copy) (put-at (nth (car path) tree) (cdr path) new))
        copy)
      new))

(defun simplify-forms (forms)
  (let ((progress nil))
    (loop for fi from 1 below (length forms)
          do (let ((restart t))
               (loop while restart
                     do (setf restart nil)
                        (block scan
                          (dolist (path (subterm-paths (nth fi forms)))
                            (let ((old (ignore-errors (get-at (nth fi forms) path))))
                              (dolist (new (replacements old))
                                (unless (or (equal new old) (>= (size new) (size old)))
                                  (let ((candidate (copy-list forms)))
                                    (setf (nth fi candidate) (put-at (nth fi forms) path new))
                                    (when (interesting-p candidate)
                                      (setf forms (accept candidate) progress t restart t)
                                      (return-from scan)))))))))))
    (values forms progress)))

(let* ((args (last sb-ext:*posix-argv* 3))
       (*output* (second args)) (*predicate* (third args))
       (forms (with-open-file (s (first args))
                (let ((*package* (find-package :zr)))
                  (loop for f = (read s nil :eof) until (eq f :eof) collect f)))))
  (format t "start: ~D forms, size ~D~%" (length forms) (size forms))
  (unless (interesting-p forms)
    (format t "the input is not interesting; nothing to reduce~%")
    (sb-ext:exit :code 2 :abort t))
  (accept forms)
  (loop
    (setf forms (drop-forms forms))
    (multiple-value-bind (new progress) (simplify-forms forms)
      (setf forms new)
      (unless progress (return))))
  (format t "done: ~D forms, size ~D, ~D tests~%" (length forms) (size forms) *tests*))
