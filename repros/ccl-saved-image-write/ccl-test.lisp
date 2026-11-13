;;; Minimal plain-CCL reproducer, test half.  Run in the saved image:
;;;   CASE=<control|generic|hang> ./img --batch --no-init --load ccl-test.lisp
(defun page (addr) (logandc2 addr 16383))          ; Apple Silicon pages are 16K
(defun elt-addr (a i) (+ (ccl::%address-of a) -4 i)) ; data starts 4 bytes below the tagged pointer (misc-data-offset)
(let* ((code (ccl::uvref #'set-u8 0))
       (code-page (page (ccl::%address-of code)))
       (hit (or (loop for i from 0 below 40000 by 64 when (= (page (elt-addr *before* i)) code-page) return (cons *before* i))
                (loop for i from 0 below 40000 by 64 when (= (page (elt-addr *after* i)) code-page) return (cons *after* i))))
       (c (ccl:getenv "CASE")))
  (format t "@code-vector ~x code-page ~x  *before* ~x  *after* ~x~%" (ccl::%address-of code) code-page
          (ccl::%address-of *before*) (ccl::%address-of *after*))
  (unless hit (format t "@LAYOUT no element of either vector shares the code page; cannot demonstrate~%") (finish-output) (ccl:quit 3))
  (let* ((arr (car hit)) (on (cdr hit))
         (off (loop for i from 0 below 40000 by 64 unless (= (page (elt-addr arr i)) code-page) return i)))
    (format t "@on-page index ~d (elt page ~x)   off-page index ~d (elt page ~x)~%" on (page (elt-addr arr on)) off (page (elt-addr arr off)))
    (finish-output)
    (cond ((string= c "control")   ; same function, same vector, element on another page
           (set-u8 arr off 9)
           (format t "@control returned: elt=~d, nonzero elements in vector=~d~%" (aref arr off) (count 0 arr :test-not #'eql)))
          ((string= c "generic")   ; same element as the hang case, but stored by out-of-line code
           (funcall 'ccl::%aset1 arr on 9)
           (format t "@generic returned: elt=~d, nonzero elements in vector=~d~%" (aref arr on) (count 0 arr :test-not #'eql)))
          ((string= c "hang")      ; store instruction and target on the same page
           (set-u8 arr on 9)
           (format t "@hang-case returned (bug NOT reproduced): elt=~d~%" (aref arr on))))))
(finish-output)
(ccl:quit 0)
