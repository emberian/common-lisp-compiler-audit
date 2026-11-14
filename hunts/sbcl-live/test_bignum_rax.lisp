(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(format t "=== Test bignum-add-loop with la in RAX (via truncate) and lb live! ===~%")
(let* ((fn (compile nil
             '(lambda (a b x lb r)
                (declare (optimize (speed 3) (safety 0))
                         (type bignum a b r)
                         (type (unsigned-byte 64) x)
                         (type (unsigned-byte 32) lb))
                (let ((la (ldb (byte 32 0) (nth-value 0 (truncate x 3)))))
                  (sb-sys:%primitive sb-vm::bignum-add-loop a b la lb r)
                  lb)))))
  (disassemble fn)
  ;; ba = 3-word negative bignum whose word[1] (lb-1 = 1) has MSB = 0, while word[2] (la-1 = 2) has MSB = 1!
  ;; Specifically: ba = - (2^130) + 1:
  ;;   word[0] = 1
  ;;   word[1] = 0          (MSB = 0 !!)
  ;;   word[2] = -4 = #xFFFFFFFFFFFFFFFC (MSB = 1 !!)
  (let* ((ba (+ (- (ash 1 130)) 1))
         (bb (+ (ash 1 70) 7)) ; 2-word positive bignum (len = 2)
         (res (sb-bignum:%allocate-bignum 4)))
    (assert (= (sb-bignum:%bignum-length ba) 3))
    (assert (= (sb-bignum:%bignum-length bb) 2))
    (funcall fn ba bb 9 2 res) ; x=9 -> la = 9/3 = 3, lb = 2
    (let ((got (sb-bignum::%normalize-bignum res 4))
          (want (+ ba bb)))
      (format t "got : ~D (#x~X)~%want: ~D (#x~X)~%MATCH? ~A~%"
              got got want want (= got want)))))
