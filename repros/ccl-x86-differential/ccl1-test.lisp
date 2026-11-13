(in-package :cl-user)
;;; CCL-1 x86-64 re-test, test half. Run in the saved image:
;;;   TYPE=u8 ./img1 --batch --no-init --load ccl1-test.lisp
;;; Sweeps every element with an inline (purified) store compiled before the save,
;;; then reads every element back inline and compares. A hang => the arm64 bug
;;; reproduces (timeout kills us). A mismatch => silent wrong value (soundness).

(defun page (raw) (logandc2 raw 4095))

(defun code-page-of (fn)
  (page (ccl::%address-of (ccl::uvref fn 0))))

(let* ((type (ccl:getenv "TYPE"))
       (spec (cond
               ((string= type "u8")  (list (gethash 'u8a *vecs*) #'set-u8 #'get-u8
                                           (lambda (i) (logand i 255)) 1))
               ((string= type "bit") (list (gethash 'bitv *vecs*) #'set-bit #'get-bit
                                           (lambda (i) (logand i 1)) 1/8))
               ((string= type "u32") (list (gethash 'u32a *vecs*) #'set-u32 #'get-u32
                                           (lambda (i) (logand (* i 2654435761) #xffffffff)) 4))
               ((string= type "u64") (list (gethash 'u64a *vecs*) #'set-u64 #'get-u64
                                           (lambda (i) (logand (+ (* i 6364136223846793005) 1) #xffffffffffffffff)) 8))
               ((string= type "s8")  (list (gethash 's8a *vecs*) #'set-s8 #'get-s8
                                           (lambda (i) (- (logand i 255) 128)) 1))
               ((string= type "sf")  (list (gethash 'sfa *vecs*) #'set-sf #'get-sf
                                           (lambda (i) (coerce i 'single-float)) 4))
               ((string= type "df")  (list (gethash 'dfa *vecs*) #'set-df #'get-df
                                           (lambda (i) (coerce i 'double-float)) 8))
               (t (format t "unknown TYPE ~s~%" type) (finish-output) (ccl:quit 2)))))
  (destructuring-bind (vec setf getf valf ebytes) spec
    (let* ((n (length vec))
           (cp (code-page-of setf))
           (dstart (+ (ccl::%address-of vec) -5))
           (dend (+ dstart (ceiling (* n ebytes))))
           (overlap (<= (page dstart) cp (page dend))))
      (format t "@TYPE ~a  n=~a  vec-data=~x..~x  set-code-page=~x  shares-code-page=~a~%"
              type n dstart dend cp overlap)
      (finish-output)
      ;; write sweep (this is where the arm64 bug hangs)
      (dotimes (i n)
        (funcall setf vec i (funcall valf i)))
      (format t "@write-sweep returned (no hang)~%")
      (finish-output)
      ;; read sweep + compare
      (let ((bad 0) (first-bad nil))
        (dotimes (i n)
          (let ((got (funcall getf vec i))
                (want (funcall valf i)))
            (unless (eql got want)
              (incf bad)
              (unless first-bad (setf first-bad (list i want got))))))
        (format t "@verify mismatches=~a~a~%" bad
                (if first-bad (format nil "  first: idx=~a want=~a got=~a"
                                      (first first-bad) (second first-bad) (third first-bad)) ""))
        (finish-output)
        (ccl:quit (if (zerop bad) 0 1))))))
