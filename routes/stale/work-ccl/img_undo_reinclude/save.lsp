(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(include-book "book")
:q
(save-exec "zimg" nil)
