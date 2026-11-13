; Probe 3: hash-table fields of stobjs: raw vs logic.
; Techniques: top-level raw ops on live stobj; logical evaluation via defthm
; on (create-...).  Ops: get, put (incl. duplicate key), boundp, keys, count,
; remove, clear, get?, init.  Tests: eql (default), equal, hons-equal, eq.
; Element types: t and (integer 0 9) with default; also (satisfies ...) etype
; via a total pred; also default init value on miss.

(defun small-natp (x) (declare (xargs :guard t)) (and (natp x) (< x 10) ))

(defstobj ht
  (h1 :type (hash-table eql) :initially nil)             ; default test
  (h2 :type (hash-table equal) :initially 42)
  (h3 :type (hash-table hons-equal 10))
  (h4 :type (hash-table eq nil symbol))
  (h5 :type (hash-table eql nil (integer 0 9)) :initially 7))

(defun rd-ht (ht)
  (declare (xargs :stobjs ht :verify-guards t))
  (list (h1-get 'a ht)
        (h1-get 'z ht)          ; miss -> nil default
        (h2-get "k" ht)         ; miss -> 42
        (h5-get 'q ht)          ; miss -> 7
        (h1-boundp 'a ht)
        (h1-count ht)
        (h1-keys ht)))

; ---------------- RAW ----------------
(h1-put 'a 1 ht)
(h1-put 'b 2 ht)
(h1-put 'a 10 ht)               ; duplicate key overwrite
(h2-put '(1 2) "v" ht)
(h2-put '(1 2) "w" ht)          ; equal-test duplicate
(h5-put 'x 3 ht)
(rd-ht ht)
(h1-get 'a ht)                  ; expect 10
(h2-get '(1 2) ht)              ; expect "w"
(h1-keys ht)                    ; expect (A B)
(h1-count ht)                   ; expect 2
(h5-keys ht)                    ; expect (X)
(h1-rem 'a ht)
(h1-boundp 'a ht)               ; expect nil
(h1-keys ht)                    ; expect (B)
(h1-clear ht)
(h1-count ht)                   ; expect 0
(h5-clear ht)
(h5-get 'x ht)                  ; expect default 7

; hons-equal test: put cons key, get with a fresh equal cons
(h3-put '(1 2) 'yes ht)
(h3-get '(1 2) ht)              ; expect YES (hons-copy canonicalizes)
(h3-get '(1 3) ht)              ; expect NIL

; ---------------- LOGICAL ----------------
(defthm ht-logical-1
 (equal (rd-ht (h5-put 'x 3
               (h2-put '(1 2) "w"
               (h2-put '(1 2) "v"
               (h1-put 'a 10
               (h1-put 'b 2
               (h1-put 'a 1
                (create-ht))))))))
        '(10 nil 42 7 t 2 (a b)))
 :rule-classes nil)

(defthm ht-logical-remove-clear
 (equal (list (h1-get 'a (h1-clear (h1-rem 'a (h1-put 'a 1 (create-ht)))))
              (h1-boundp 'a (h1-rem 'a (h1-put 'a 1 (create-ht))))
              (h1-keys (h1-rem 'a (h1-put 'a 1 (create-ht))))
              (h1-count (h1-clear (h1-put 'a 1 (create-ht)))))
        '(nil nil nil 0))
 :rule-classes nil)

(defthm ht-logical-hons-equal
 (equal (list (h3-get '(1 2) (h3-put '(1 2) 'yes (create-ht)))
              (h3-get '(1 3) (h3-put '(1 2) 'yes (create-ht))))
        '(yes nil))
 :rule-classes nil)

; keys after duplicate put (logical alist has two A entries; dedup expected)
(defthm ht-logical-keys-dup
 (equal (h1-keys (h1-put 'a 10 (h1-put 'a 1 (create-ht))))
        '(a))
 :rule-classes nil)

(quit)
