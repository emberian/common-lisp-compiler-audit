(in-package "ACL2")
(make-event
 (mv-let (chan state)
   (open-input-channel "payload.lsp" :object state)
   (mv-let (eofp form state)
     (read-object chan state)
     (declare (ignore eofp))
     (pprogn (close-input-channel chan state)
             (value form)))))
