; Probe 2: raw-vs-logic matrix over stobj field types (v2).
(defun my-even (x) (declare (xargs :guard t)) (and (integerp x) (evenp x)))

(defstobj m
  (f-i1    :type (integer -5 10)      :initially 0)
  (f-i2    :type (integer 0 *)        :initially 3)
  (f-s63   :type (signed-byte 63)     :initially 0)
  (f-s64   :type (signed-byte 64)     :initially 0)
  (f-u64   :type (unsigned-byte 64)   :initially 0)
  (f-u62   :type (unsigned-byte 62)   :initially 0)
  (f-rat   :type rational             :initially 1/3)
  (f-chr   :type character            :initially #\a)
  (f-str   :type string               :initially "abc")
  (f-sym   :type symbol               :initially foo)
  (f-or    :type (or integer string)  :initially 7)
  (f-mem   :type (member foo bar baz) :initially foo)
  (f-sat   :type (satisfies my-even)  :initially 0)
  (f-bit   :type bit                  :initially 0))

(defstobj arr
  (a-i8    :type (array (signed-byte 8) (5))     :initially -128)
  (a-u32   :type (array (unsigned-byte 32) (5))  :initially 4294967295)
  (a-s64   :type (array (signed-byte 64) (5))    :initially 0)
  (a-str   :type (array string (5))              :initially "xy")
  (a-t     :type (array t (5))                   :initially nil)
  (a-res   :type (array (integer 0 9) (3))       :initially 2 :resizable t))

(defun rd-m (m)
  (declare (xargs :stobjs m :verify-guards t))
  (list (f-i1 m) (f-i2 m) (f-s63 m) (f-s64 m) (f-u64 m) (f-u62 m)
        (f-rat m) (f-chr m) (f-str m) (f-sym m) (f-or m) (f-mem m)
        (f-sat m) (f-bit m)))

(defun rd-arr (arr)
  (declare (xargs :stobjs arr :verify-guards t
                  :guard (and (arrp arr)
                              (< 1 (a-res-length arr))
                              (< 4 (a-i8-length arr))
                              (< 2 (a-t-length arr)))))
  (list (a-i8i 0 arr) (a-i8i 4 arr)
        (a-u32i 0 arr)
        (a-s64i 0 arr)
        (a-stri 1 arr)
        (a-ti 2 arr)
        (a-resi 1 arr)
        (a-res-length arr)))

; ---- RAW: updates + reads on live stobjs ----
(update-f-i1 -5 m)
(update-f-i2 99 m)
(update-f-s63 4611686018427387903 m)   ; 2^62-1
(update-f-s64 9223372036854775807 m)   ; 2^63-1
(update-f-s64 -9223372036854775808 m)  ; then overwrite with -2^63
(update-f-u64 18446744073709551615 m)  ; 2^64-1
(update-f-u62 4611686018427387903 m)
(update-f-rat -22/7 m)
(update-f-chr #\Z m)
(update-f-str "hello" m)
(update-f-sym 'bar m)
(update-f-or "str-or" m)
(update-f-mem 'baz m)
(update-f-sat 42 m)
(update-f-bit 1 m)
(rd-m m)

(update-a-i8i 0 -128 arr)
(update-a-i8i 4 127 arr)
(update-a-u32i 0 4294967295 arr)
(update-a-s64i 0 -9223372036854775808 arr)
(update-a-stri 1 "zz" arr)
(update-a-ti 2 '(1 2 3) arr)
(update-a-resi 1 9 arr)
(resize-a-res 6 arr)
(update-a-resi 5 7 arr)
(a-resi 4 arr)
(rd-arr arr)

; ---- LOGICAL: same updates/reads on the logical representation ----
(defthm matrix-logical-m
 (equal (rd-m (update-f-bit 1
              (update-f-sat 42
              (update-f-mem 'baz
              (update-f-or "str-or"
              (update-f-sym 'bar
              (update-f-str "hello"
              (update-f-chr #\Z
              (update-f-rat -22/7
              (update-f-u62 4611686018427387903
              (update-f-u64 18446744073709551615
              (update-f-s64 -9223372036854775808
              (update-f-s63 4611686018427387903
              (update-f-i2 99
              (update-f-i1 -5
               (create-m))))))))))))))))
        '(-5 99 4611686018427387903 -9223372036854775808
          18446744073709551615 4611686018427387903
          -22/7 #\Z "hello" bar "str-or" baz 42 1))
 :rule-classes nil)

(defthm matrix-logical-arr
 (equal (rd-arr (update-a-resi 5 7
                 (resize-a-res 6
                 (update-a-ti 2 '(1 2 3)
                 (update-a-stri 1 "zz"
                 (update-a-s64i 0 -9223372036854775808
                 (update-a-u32i 0 4294967295
                 (update-a-i8i 4 127
                 (update-a-i8i 0 -128
                  (create-arr))))))))))
        '(-128 127 4294967295 -9223372036854775808 "zz" (1 2 3)
          2 6))
 :rule-classes nil)

(defthm matrix-logical-res-default
 (equal (a-resi 4 (update-a-resi 5 7 (resize-a-res 6 (create-arr))))
        2)
 :rule-classes nil)

(quit)
