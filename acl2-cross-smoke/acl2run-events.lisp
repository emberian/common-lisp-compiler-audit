(in-package "ACL2")
; Logical completion needs EC-CALL to run with guard checking off.
; Raw calls below bypass *1* functions and still execute actual raw code.
(set-guard-checking :none)
(defun acl2run-unary-truncate (x)
  (declare (xargs :guard (real/rationalp x)))
  (mv (truncate x 1) (rem x 1)))

(defun mask-signed (width value)
  (declare (xargs :guard (and (unsigned-byte-p 16 width)
                              (integerp value))))
  (if (zp width)
      0
      (let ((unsigned (mod value (expt 2 width))))
        (if (logbitp (1- width) value)
            (- unsigned (expt 2 width))
            unsigned))))
:q
(defun acl2run-json-string (string)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for ch across string
          for code = (char-code ch)
          do (cond ((char= ch #\") (write-string "\\\"" out))
                   ((char= ch #\\) (write-string "\\\\" out))
                   ((< code 32) (format out "\\u~4,'0x" code))
                   (t (write-char ch out))))
    (write-char #\" out)))

(defun acl2run-emit (id phase status &key (value nil valuep) message)
  (format t "~&ACL2RUN {\"id\":~a,\"phase\":~a,\"status\":~a"
          (acl2run-json-string id)
          (acl2run-json-string phase)
          (acl2run-json-string status))
  (when valuep
    (format t ",\"value\":~a"
            (acl2run-json-string
             (write-to-string value :escape t :readably t :pretty nil
                              :circle t :case :upcase :base 10))))
  (when message
    (format t ",\"message\":~a" (acl2run-json-string message)))
  (format t "}~%")
  (finish-output))

(defun acl2run-logical (id fn)
  (handler-case
      (let ((*ev-shortcut-okp* nil))
        (multiple-value-bind (erp val latches)
            (ev-fncall-rec-logical
             fn nil nil (w *the-live-state*) (user-stobj-alist *the-live-state*)
             1000000 nil t nil nil nil nil)
          (declare (ignore latches))
          (if erp
              (acl2run-emit id "logical" "logical_error"
                            :message (write-to-string val :escape t))
              (acl2run-emit id "logical" "value" :value val))))
    (error (condition)
      (acl2run-emit id "logical" "logical_error"
                    :message (princ-to-string condition)))))

(defun acl2run-guard-violated-p (fn)
  (handler-case
      (let ((*ev-shortcut-okp* nil))
        (multiple-value-bind (erp val latches)
            (ev-fncall-rec-logical
             fn nil nil (w *the-live-state*) (user-stobj-alist *the-live-state*)
             1000000 nil nil nil nil nil nil)
          (declare (ignore latches))
          (if (and erp (search "guard" (write-to-string val :escape t)
                               :test #'char-equal))
              t
              nil)))
    (error () :error)))

(defun acl2run-raw (id fn)
  (handler-case
      (let ((values (multiple-value-list (funcall (symbol-function fn)))))
        (acl2run-emit id "raw" "value"
                      :value (if (null (cdr values)) (car values) values)))
    (error (condition)
      (acl2run-emit id "raw"
                    (if (eq (acl2run-guard-violated-p fn) t)
                        "raw_guard_crash"
                        "raw_error")
                    :message (princ-to-string condition)))))

(defun acl2run-compile-and-raw (id fn)
  (handler-case
      (multiple-value-bind (compiled warnings-p failure-p)
          (compile fn)
        (declare (ignore compiled warnings-p))
        (cond (failure-p
               (acl2run-emit id "compile" "host_compilation_failure"
                             :message "COMPILE returned failure-p")
               (acl2run-emit id "raw" "skipped"))
              (t
               (acl2run-emit id "compile" "compiled")
               (acl2run-raw id fn))))
    (error (condition)
      (acl2run-emit id "compile" "host_compilation_failure"
                    :message (princ-to-string condition))
      (acl2run-emit id "raw" "skipped"))))

(defun acl2run-run-case (id fn)
  (if (not (function-symbolp fn (w *the-live-state*)))
      (acl2run-emit id "event" "event_failure"
                    :message "DEFUN was not admitted into the ACL2 world")
      (progn
        (acl2run-emit id "event" "admitted")
        (acl2run-logical id fn)
        (acl2run-compile-and-raw id fn))))
(lp)
(defun ACL2RUN-CASE-0000 ()
  (zp nil))
:q
(acl2run-run-case "zp-nil" 'ACL2RUN-CASE-0000)
(lp)
(defun ACL2RUN-CASE-0001 ()
  (zp 1/3))
:q
(acl2run-run-case "zp-rational" 'ACL2RUN-CASE-0001)
(lp)
(defun ACL2RUN-CASE-0002 ()
  (zp "x"))
:q
(acl2run-run-case "zp-string" 'ACL2RUN-CASE-0002)
(lp)
(defun ACL2RUN-CASE-0003 ()
  (car nil))
:q
(acl2run-run-case "car-nil" 'ACL2RUN-CASE-0003)
(lp)
(defun ACL2RUN-CASE-0004 ()
  (car 1/3))
:q
(acl2run-run-case "car-rational" 'ACL2RUN-CASE-0004)
(lp)
(defun ACL2RUN-CASE-0005 ()
  (cdr nil))
:q
(acl2run-run-case "cdr-nil" 'ACL2RUN-CASE-0005)
(lp)
(defun ACL2RUN-CASE-0006 ()
  (cdr 'a))
:q
(acl2run-run-case "cdr-symbol" 'ACL2RUN-CASE-0006)
(lp)
(defun ACL2RUN-CASE-0007 ()
  (acl2run-unary-truncate 17/3))
:q
(acl2run-run-case "unary-truncate-positive" 'ACL2RUN-CASE-0007)
(lp)
(defun ACL2RUN-CASE-0008 ()
  (acl2run-unary-truncate -17/3))
:q
(acl2run-run-case "unary-truncate-negative" 'ACL2RUN-CASE-0008)
(lp)
(defun ACL2RUN-CASE-0009 ()
  (mask-signed 8 (ash -3 2)))
:q
(acl2run-run-case "mask-ash-negative" 'ACL2RUN-CASE-0009)
(lp)
(defun ACL2RUN-CASE-0010 ()
  (mask-signed 8 (ash 3 2)))
:q
(acl2run-run-case "mask-ash-positive" 'ACL2RUN-CASE-0010)
(lp)
(defun ACL2RUN-CASE-0011 ()
  (mask-signed 4 (ash 3 3)))
:q
(acl2run-run-case "mask-ash-wrap" 'ACL2RUN-CASE-0011)
(lp)
(defun ACL2RUN-CASE-0012 ()
  (mask-signed 0 (ash 3 100)))
:q
(acl2run-run-case "mask-zero" 'ACL2RUN-CASE-0012)
(lp)
(quit)
