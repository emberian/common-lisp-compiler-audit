;; Reproducer for SMTLink symbol collision (case-folding + package-dropping)
;; and quoted-symbol symbol-index shadowing bug.
;; Sources:
;;   books/projects/smtlink/trusted/z3-py/names.lisp:45-167
;;   books/projects/smtlink/trusted/z3-py/translate-type.lisp:37-40
;;   books/projects/smtlink/trusted/z3-py/translator.lisp:408-427
(in-package "ACL2")

;; Exact symbol-mangling logic from names.lisp + translate-type.lisp
(defconst *smt-special-list*
  '((#\_ . (#\_ #\u #\s #\c #\_))
    (#\- . (#\_ #\s #\u #\b #\_))
    (#\+ . (#\_ #\a #\d #\d #\_))
    (#\* . (#\_ #\m #\l #\t #\_))
    (#\/ . (#\_ #\d #\i #\v #\_))
    (#\< . (#\_ #\l #\t #\_))
    (#\> . (#\_ #\g #\t #\_))
    (#\= . (#\_ #\e #\q #\l #\_))
    (#\! . (#\_ #\e #\x #\c #\_))
    (#\@ . (#\_ #\a #\t #\_))
    (#\# . (#\_ #\h #\s #\h #\_))
    (#\$ . (#\_ #\d #\l #\r #\_))
    (#\% . (#\_ #\p #\c #\t #\_))
    (#\^ . (#\_ #\c #\a #\r #\_))
    (#\& . (#\_ #\a #\m #\p #\_))))

(defun char-is-num (c) (and (<= 48 (char-code c)) (<= (char-code c) 57)))
(defun char-is-let (c)
  (or (and (<= 65 (char-code c)) (<= (char-code c) 90))
      (and (<= 97 (char-code c)) (<= (char-code c) 122))))

(defun nat-hex-chars (n)
  (explode-nonnegative-integer (nfix n) 16 nil))

(defun mangle-char (c)
  (cond ((or (char-is-num c) (char-is-let c)) (list c))
        ((assoc c *smt-special-list*) (cdr (assoc c *smt-special-list*)))
        (t (append '(#\_) (nat-hex-chars (char-code c)) '(#\_)))))

(defun mangle-chars (lst)
  (if (endp lst) nil (append (mangle-char (car lst)) (mangle-chars (cdr lst)))))

(defun smt-lisp-to-python-names (var)
  (let* ((s (if (stringp var) var (symbol-name var)))
         (cs (coerce s 'list)))
    (coerce (cond ((endp cs) nil)
                  ((char-is-num (car cs)) (cons #\_ (mangle-chars cs)))
                  (t (mangle-chars cs)))
            'string)))

(defun smt-translate-symbol (sym)
  (string-downcase (smt-lisp-to-python-names sym)))

;; Exact quoted-symbol indexing bug from translator.lisp:408-427
;; Notice outer frame returns (generate-symbol-enumeration a.symbol-index),
;; NOT symbol-index-rest, when processing ('quote ...) in expr-lst!
(defun gen-sym-enum (idx)
  (coerce (append (coerce "gensym_" 'list)
                  (nat-hex-chars idx))
          'string))

(defun translate-quoted-pair (syms avoid-list symbol-index symbol-list symbol-map)
  (if (endp syms)
      (mv nil symbol-list symbol-index symbol-map)
    (let ((the-sym (car syms)))
      (mv-let (rest-trans symbols-rest symbol-index-rest symbol-map-rest)
        (translate-quoted-pair (cdr syms) avoid-list symbol-index symbol-list symbol-map)
        (let ((looked (assoc-eq the-sym symbol-map-rest)))
          (if looked
              (mv (cons (cdr looked) rest-trans) symbols-rest symbol-index-rest symbol-map-rest)
            (if (member-eq the-sym avoid-list)
                ;; Buggy line translator.lisp:417 uses `symbol-index` instead of `symbol-index-rest`!
                (let* ((new-sym (gen-sym-enum symbol-index))
                       (new-index (1+ symbol-index-rest)))
                  (mv (cons new-sym rest-trans)
                      (cons new-sym symbols-rest)
                      new-index
                      (cons (cons the-sym new-sym) symbol-map-rest)))
              (let ((new-sym (smt-translate-symbol the-sym)))
                (mv (cons new-sym rest-trans)
                    (cons new-sym symbols-rest)
                    symbol-index-rest
                    (cons (cons the-sym new-sym) symbol-map-rest))))))))))

(defpkg "OTHER-PKG" '(bar))

(defthm case-and-pkg-collisions
  (and (not (equal '|x| 'x))
       (equal (smt-translate-symbol '|x|) (smt-translate-symbol 'x))
       (not (equal 'acl2::x 'other-pkg::x))
       (equal (smt-translate-symbol 'acl2::x) (smt-translate-symbol 'other-pkg::x)))
  :rule-classes nil)

(defthm quoted-symbol-index-collision
  (mv-let (trans syms idx smap)
    (translate-quoted-pair '(foo bar) '(foo bar) 0 nil nil)
    (declare (ignore syms idx smap))
    (and (not (equal 'foo 'bar))
         (equal (car trans) "gensym_0")
         (equal (cadr trans) "gensym_0")))
  :rule-classes nil)
