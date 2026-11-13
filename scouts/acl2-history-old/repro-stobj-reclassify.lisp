; NOTE-2-8 original STOBJ reclassification example from non-identical-defp.
(defun stobjless-fn (stobj-to-be)
  (declare (xargs :mode :program))
  stobj-to-be)
(defun my-callee-is-stobjless (x)
  (declare (xargs :mode :program))
  (stobjless-fn x))
(defstobj stobj-to-be
  (a-field :type integer :initially 0))
(defun stobjless-fn (stobj-to-be)
  (declare (xargs :stobjs stobj-to-be))
  stobj-to-be)
(cw "CALLER-VALUE ~x0~%" (my-callee-is-stobjless 3))
(quit)
