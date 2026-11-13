(set-compile-fns t)

(defun loghead (n i)
  (declare (xargs :guard (and (natp n) (integerp i))))
  (mod (ifix i) (expt 2 (nfix n))))

(defun logtail (n i)
  (declare (xargs :guard (and (natp n) (integerp i))))
  (ifix (floor (ifix i) (expt 2 (nfix n)))))

(verify-guards loghead)
(verify-guards logtail)


(defun audit-acl2-0000 () (with-guard-checking NIL (ec-call (zp '-2))))

(verify-guards audit-acl2-0000)

(cw "AUDIT-BEGIN|zp-0000|compiled~%")

(cw "AUDIT-RESULT|zp-0000|compiled|~x0~%" (audit-acl2-0000))

(cw "AUDIT-BEGIN|zp-0000|direct~%")

(cw "AUDIT-RESULT|zp-0000|direct|~x0~%" (with-guard-checking NIL (ec-call (zp '-2))))

(defun audit-acl2-0001 () (zp '0))

(verify-guards audit-acl2-0001)

(cw "AUDIT-BEGIN|zp-0001|compiled~%")

(cw "AUDIT-RESULT|zp-0001|compiled|~x0~%" (audit-acl2-0001))

(cw "AUDIT-BEGIN|zp-0001|direct~%")

(cw "AUDIT-RESULT|zp-0001|direct|~x0~%" (zp '0))

(defun audit-acl2-0002 () (zp '3))

(verify-guards audit-acl2-0002)

(cw "AUDIT-BEGIN|zp-0002|compiled~%")

(cw "AUDIT-RESULT|zp-0002|compiled|~x0~%" (audit-acl2-0002))

(cw "AUDIT-BEGIN|zp-0002|direct~%")

(cw "AUDIT-RESULT|zp-0002|direct|~x0~%" (zp '3))

(defun audit-acl2-0003 () (with-guard-checking NIL (ec-call (zp '-1/2))))

(verify-guards audit-acl2-0003)

(cw "AUDIT-BEGIN|zp-0003|compiled~%")

(cw "AUDIT-RESULT|zp-0003|compiled|~x0~%" (audit-acl2-0003))

(cw "AUDIT-BEGIN|zp-0003|direct~%")

(cw "AUDIT-RESULT|zp-0003|direct|~x0~%" (with-guard-checking NIL (ec-call (zp '-1/2))))

(defun audit-acl2-0004 () (with-guard-checking NIL (ec-call (zp '2/3))))

(verify-guards audit-acl2-0004)

(cw "AUDIT-BEGIN|zp-0004|compiled~%")

(cw "AUDIT-RESULT|zp-0004|compiled|~x0~%" (audit-acl2-0004))

(cw "AUDIT-BEGIN|zp-0004|direct~%")

(cw "AUDIT-RESULT|zp-0004|direct|~x0~%" (with-guard-checking NIL (ec-call (zp '2/3))))

(defun audit-acl2-0005 () (with-guard-checking NIL (ec-call (zp '#C(1 2)))))

(verify-guards audit-acl2-0005)

(cw "AUDIT-BEGIN|zp-0005|compiled~%")

(cw "AUDIT-RESULT|zp-0005|compiled|~x0~%" (audit-acl2-0005))

(cw "AUDIT-BEGIN|zp-0005|direct~%")

(cw "AUDIT-RESULT|zp-0005|direct|~x0~%" (with-guard-checking NIL (ec-call (zp '#C(1 2)))))

(defun audit-acl2-0006 () (with-guard-checking NIL (ec-call (zp NIL))))

(verify-guards audit-acl2-0006)

(cw "AUDIT-BEGIN|zp-0006|compiled~%")

(cw "AUDIT-RESULT|zp-0006|compiled|~x0~%" (audit-acl2-0006))

(cw "AUDIT-BEGIN|zp-0006|direct~%")

(cw "AUDIT-RESULT|zp-0006|direct|~x0~%" (with-guard-checking NIL (ec-call (zp NIL))))

(defun audit-acl2-0007 () (with-guard-checking NIL (ec-call (zp 'A))))

(verify-guards audit-acl2-0007)

(cw "AUDIT-BEGIN|zp-0007|compiled~%")

(cw "AUDIT-RESULT|zp-0007|compiled|~x0~%" (audit-acl2-0007))

(cw "AUDIT-BEGIN|zp-0007|direct~%")

(cw "AUDIT-RESULT|zp-0007|direct|~x0~%" (with-guard-checking NIL (ec-call (zp 'A))))

(defun audit-acl2-0008 () (with-guard-checking NIL (ec-call (zp '"text"))))

(verify-guards audit-acl2-0008)

(cw "AUDIT-BEGIN|zp-0008|compiled~%")

(cw "AUDIT-RESULT|zp-0008|compiled|~x0~%" (audit-acl2-0008))

(cw "AUDIT-BEGIN|zp-0008|direct~%")

(cw "AUDIT-RESULT|zp-0008|direct|~x0~%" (with-guard-checking NIL (ec-call (zp '"text"))))

(defun audit-acl2-0009 () (zip '-2))

(verify-guards audit-acl2-0009)

(cw "AUDIT-BEGIN|zip-0009|compiled~%")

(cw "AUDIT-RESULT|zip-0009|compiled|~x0~%" (audit-acl2-0009))

(cw "AUDIT-BEGIN|zip-0009|direct~%")

(cw "AUDIT-RESULT|zip-0009|direct|~x0~%" (zip '-2))

(defun audit-acl2-0010 () (zip '0))

(verify-guards audit-acl2-0010)

(cw "AUDIT-BEGIN|zip-0010|compiled~%")

(cw "AUDIT-RESULT|zip-0010|compiled|~x0~%" (audit-acl2-0010))

(cw "AUDIT-BEGIN|zip-0010|direct~%")

(cw "AUDIT-RESULT|zip-0010|direct|~x0~%" (zip '0))

(defun audit-acl2-0011 () (zip '3))

(verify-guards audit-acl2-0011)

(cw "AUDIT-BEGIN|zip-0011|compiled~%")

(cw "AUDIT-RESULT|zip-0011|compiled|~x0~%" (audit-acl2-0011))

(cw "AUDIT-BEGIN|zip-0011|direct~%")

(cw "AUDIT-RESULT|zip-0011|direct|~x0~%" (zip '3))

(defun audit-acl2-0012 () (with-guard-checking NIL (ec-call (zip '-1/2))))

(verify-guards audit-acl2-0012)

(cw "AUDIT-BEGIN|zip-0012|compiled~%")

(cw "AUDIT-RESULT|zip-0012|compiled|~x0~%" (audit-acl2-0012))

(cw "AUDIT-BEGIN|zip-0012|direct~%")

(cw "AUDIT-RESULT|zip-0012|direct|~x0~%" (with-guard-checking NIL (ec-call (zip '-1/2))))

(defun audit-acl2-0013 () (with-guard-checking NIL (ec-call (zip '2/3))))

(verify-guards audit-acl2-0013)

(cw "AUDIT-BEGIN|zip-0013|compiled~%")

(cw "AUDIT-RESULT|zip-0013|compiled|~x0~%" (audit-acl2-0013))

(cw "AUDIT-BEGIN|zip-0013|direct~%")

(cw "AUDIT-RESULT|zip-0013|direct|~x0~%" (with-guard-checking NIL (ec-call (zip '2/3))))

(defun audit-acl2-0014 () (with-guard-checking NIL (ec-call (zip '#C(1 2)))))

(verify-guards audit-acl2-0014)

(cw "AUDIT-BEGIN|zip-0014|compiled~%")

(cw "AUDIT-RESULT|zip-0014|compiled|~x0~%" (audit-acl2-0014))

(cw "AUDIT-BEGIN|zip-0014|direct~%")

(cw "AUDIT-RESULT|zip-0014|direct|~x0~%" (with-guard-checking NIL (ec-call (zip '#C(1 2)))))

(defun audit-acl2-0015 () (with-guard-checking NIL (ec-call (zip NIL))))

(verify-guards audit-acl2-0015)

(cw "AUDIT-BEGIN|zip-0015|compiled~%")

(cw "AUDIT-RESULT|zip-0015|compiled|~x0~%" (audit-acl2-0015))

(cw "AUDIT-BEGIN|zip-0015|direct~%")

(cw "AUDIT-RESULT|zip-0015|direct|~x0~%" (with-guard-checking NIL (ec-call (zip NIL))))

(defun audit-acl2-0016 () (with-guard-checking NIL (ec-call (zip 'A))))

(verify-guards audit-acl2-0016)

(cw "AUDIT-BEGIN|zip-0016|compiled~%")

(cw "AUDIT-RESULT|zip-0016|compiled|~x0~%" (audit-acl2-0016))

(cw "AUDIT-BEGIN|zip-0016|direct~%")

(cw "AUDIT-RESULT|zip-0016|direct|~x0~%" (with-guard-checking NIL (ec-call (zip 'A))))

(defun audit-acl2-0017 () (with-guard-checking NIL (ec-call (zip '"text"))))

(verify-guards audit-acl2-0017)

(cw "AUDIT-BEGIN|zip-0017|compiled~%")

(cw "AUDIT-RESULT|zip-0017|compiled|~x0~%" (audit-acl2-0017))

(cw "AUDIT-BEGIN|zip-0017|direct~%")

(cw "AUDIT-RESULT|zip-0017|direct|~x0~%" (with-guard-checking NIL (ec-call (zip '"text"))))

(defun audit-acl2-0018 () (nfix '-2))

(verify-guards audit-acl2-0018)

(cw "AUDIT-BEGIN|nfix-0018|compiled~%")

(cw "AUDIT-RESULT|nfix-0018|compiled|~x0~%" (audit-acl2-0018))

(cw "AUDIT-BEGIN|nfix-0018|direct~%")

(cw "AUDIT-RESULT|nfix-0018|direct|~x0~%" (nfix '-2))

(defun audit-acl2-0019 () (nfix '0))

(verify-guards audit-acl2-0019)

(cw "AUDIT-BEGIN|nfix-0019|compiled~%")

(cw "AUDIT-RESULT|nfix-0019|compiled|~x0~%" (audit-acl2-0019))

(cw "AUDIT-BEGIN|nfix-0019|direct~%")

(cw "AUDIT-RESULT|nfix-0019|direct|~x0~%" (nfix '0))

(defun audit-acl2-0020 () (nfix '3))

(verify-guards audit-acl2-0020)

(cw "AUDIT-BEGIN|nfix-0020|compiled~%")

(cw "AUDIT-RESULT|nfix-0020|compiled|~x0~%" (audit-acl2-0020))

(cw "AUDIT-BEGIN|nfix-0020|direct~%")

(cw "AUDIT-RESULT|nfix-0020|direct|~x0~%" (nfix '3))

(defun audit-acl2-0021 () (nfix '-1/2))

(verify-guards audit-acl2-0021)

(cw "AUDIT-BEGIN|nfix-0021|compiled~%")

(cw "AUDIT-RESULT|nfix-0021|compiled|~x0~%" (audit-acl2-0021))

(cw "AUDIT-BEGIN|nfix-0021|direct~%")

(cw "AUDIT-RESULT|nfix-0021|direct|~x0~%" (nfix '-1/2))

(defun audit-acl2-0022 () (nfix '2/3))

(verify-guards audit-acl2-0022)

(cw "AUDIT-BEGIN|nfix-0022|compiled~%")

(cw "AUDIT-RESULT|nfix-0022|compiled|~x0~%" (audit-acl2-0022))

(cw "AUDIT-BEGIN|nfix-0022|direct~%")

(cw "AUDIT-RESULT|nfix-0022|direct|~x0~%" (nfix '2/3))

(defun audit-acl2-0023 () (nfix '#C(1 2)))

(verify-guards audit-acl2-0023)

(cw "AUDIT-BEGIN|nfix-0023|compiled~%")

(cw "AUDIT-RESULT|nfix-0023|compiled|~x0~%" (audit-acl2-0023))

(cw "AUDIT-BEGIN|nfix-0023|direct~%")

(cw "AUDIT-RESULT|nfix-0023|direct|~x0~%" (nfix '#C(1 2)))

(defun audit-acl2-0024 () (nfix NIL))

(verify-guards audit-acl2-0024)

(cw "AUDIT-BEGIN|nfix-0024|compiled~%")

(cw "AUDIT-RESULT|nfix-0024|compiled|~x0~%" (audit-acl2-0024))

(cw "AUDIT-BEGIN|nfix-0024|direct~%")

(cw "AUDIT-RESULT|nfix-0024|direct|~x0~%" (nfix NIL))

(defun audit-acl2-0025 () (nfix 'A))

(verify-guards audit-acl2-0025)

(cw "AUDIT-BEGIN|nfix-0025|compiled~%")

(cw "AUDIT-RESULT|nfix-0025|compiled|~x0~%" (audit-acl2-0025))

(cw "AUDIT-BEGIN|nfix-0025|direct~%")

(cw "AUDIT-RESULT|nfix-0025|direct|~x0~%" (nfix 'A))

(defun audit-acl2-0026 () (nfix '"text"))

(verify-guards audit-acl2-0026)

(cw "AUDIT-BEGIN|nfix-0026|compiled~%")

(cw "AUDIT-RESULT|nfix-0026|compiled|~x0~%" (audit-acl2-0026))

(cw "AUDIT-BEGIN|nfix-0026|direct~%")

(cw "AUDIT-RESULT|nfix-0026|direct|~x0~%" (nfix '"text"))

(defun audit-acl2-0027 () (ifix '-2))

(verify-guards audit-acl2-0027)

(cw "AUDIT-BEGIN|ifix-0027|compiled~%")

(cw "AUDIT-RESULT|ifix-0027|compiled|~x0~%" (audit-acl2-0027))

(cw "AUDIT-BEGIN|ifix-0027|direct~%")

(cw "AUDIT-RESULT|ifix-0027|direct|~x0~%" (ifix '-2))

(defun audit-acl2-0028 () (ifix '0))

(verify-guards audit-acl2-0028)

(cw "AUDIT-BEGIN|ifix-0028|compiled~%")

(cw "AUDIT-RESULT|ifix-0028|compiled|~x0~%" (audit-acl2-0028))

(cw "AUDIT-BEGIN|ifix-0028|direct~%")

(cw "AUDIT-RESULT|ifix-0028|direct|~x0~%" (ifix '0))

(defun audit-acl2-0029 () (ifix '3))

(verify-guards audit-acl2-0029)

(cw "AUDIT-BEGIN|ifix-0029|compiled~%")

(cw "AUDIT-RESULT|ifix-0029|compiled|~x0~%" (audit-acl2-0029))

(cw "AUDIT-BEGIN|ifix-0029|direct~%")

(cw "AUDIT-RESULT|ifix-0029|direct|~x0~%" (ifix '3))

(defun audit-acl2-0030 () (ifix '-1/2))

(verify-guards audit-acl2-0030)

(cw "AUDIT-BEGIN|ifix-0030|compiled~%")

(cw "AUDIT-RESULT|ifix-0030|compiled|~x0~%" (audit-acl2-0030))

(cw "AUDIT-BEGIN|ifix-0030|direct~%")

(cw "AUDIT-RESULT|ifix-0030|direct|~x0~%" (ifix '-1/2))

(defun audit-acl2-0031 () (ifix '2/3))

(verify-guards audit-acl2-0031)

(cw "AUDIT-BEGIN|ifix-0031|compiled~%")

(cw "AUDIT-RESULT|ifix-0031|compiled|~x0~%" (audit-acl2-0031))

(cw "AUDIT-BEGIN|ifix-0031|direct~%")

(cw "AUDIT-RESULT|ifix-0031|direct|~x0~%" (ifix '2/3))

(defun audit-acl2-0032 () (ifix '#C(1 2)))

(verify-guards audit-acl2-0032)

(cw "AUDIT-BEGIN|ifix-0032|compiled~%")

(cw "AUDIT-RESULT|ifix-0032|compiled|~x0~%" (audit-acl2-0032))

(cw "AUDIT-BEGIN|ifix-0032|direct~%")

(cw "AUDIT-RESULT|ifix-0032|direct|~x0~%" (ifix '#C(1 2)))

(defun audit-acl2-0033 () (ifix NIL))

(verify-guards audit-acl2-0033)

(cw "AUDIT-BEGIN|ifix-0033|compiled~%")

(cw "AUDIT-RESULT|ifix-0033|compiled|~x0~%" (audit-acl2-0033))

(cw "AUDIT-BEGIN|ifix-0033|direct~%")

(cw "AUDIT-RESULT|ifix-0033|direct|~x0~%" (ifix NIL))

(defun audit-acl2-0034 () (ifix 'A))

(verify-guards audit-acl2-0034)

(cw "AUDIT-BEGIN|ifix-0034|compiled~%")

(cw "AUDIT-RESULT|ifix-0034|compiled|~x0~%" (audit-acl2-0034))

(cw "AUDIT-BEGIN|ifix-0034|direct~%")

(cw "AUDIT-RESULT|ifix-0034|direct|~x0~%" (ifix 'A))

(defun audit-acl2-0035 () (ifix '"text"))

(verify-guards audit-acl2-0035)

(cw "AUDIT-BEGIN|ifix-0035|compiled~%")

(cw "AUDIT-RESULT|ifix-0035|compiled|~x0~%" (audit-acl2-0035))

(cw "AUDIT-BEGIN|ifix-0035|direct~%")

(cw "AUDIT-RESULT|ifix-0035|direct|~x0~%" (ifix '"text"))

(defun audit-acl2-0036 () (fix '-2))

(verify-guards audit-acl2-0036)

(cw "AUDIT-BEGIN|fix-0036|compiled~%")

(cw "AUDIT-RESULT|fix-0036|compiled|~x0~%" (audit-acl2-0036))

(cw "AUDIT-BEGIN|fix-0036|direct~%")

(cw "AUDIT-RESULT|fix-0036|direct|~x0~%" (fix '-2))

(defun audit-acl2-0037 () (fix '0))

(verify-guards audit-acl2-0037)

(cw "AUDIT-BEGIN|fix-0037|compiled~%")

(cw "AUDIT-RESULT|fix-0037|compiled|~x0~%" (audit-acl2-0037))

(cw "AUDIT-BEGIN|fix-0037|direct~%")

(cw "AUDIT-RESULT|fix-0037|direct|~x0~%" (fix '0))

(defun audit-acl2-0038 () (fix '3))

(verify-guards audit-acl2-0038)

(cw "AUDIT-BEGIN|fix-0038|compiled~%")

(cw "AUDIT-RESULT|fix-0038|compiled|~x0~%" (audit-acl2-0038))

(cw "AUDIT-BEGIN|fix-0038|direct~%")

(cw "AUDIT-RESULT|fix-0038|direct|~x0~%" (fix '3))

(defun audit-acl2-0039 () (fix '-1/2))

(verify-guards audit-acl2-0039)

(cw "AUDIT-BEGIN|fix-0039|compiled~%")

(cw "AUDIT-RESULT|fix-0039|compiled|~x0~%" (audit-acl2-0039))

(cw "AUDIT-BEGIN|fix-0039|direct~%")

(cw "AUDIT-RESULT|fix-0039|direct|~x0~%" (fix '-1/2))

(defun audit-acl2-0040 () (fix '2/3))

(verify-guards audit-acl2-0040)

(cw "AUDIT-BEGIN|fix-0040|compiled~%")

(cw "AUDIT-RESULT|fix-0040|compiled|~x0~%" (audit-acl2-0040))

(cw "AUDIT-BEGIN|fix-0040|direct~%")

(cw "AUDIT-RESULT|fix-0040|direct|~x0~%" (fix '2/3))

(defun audit-acl2-0041 () (fix '#C(1 2)))

(verify-guards audit-acl2-0041)

(cw "AUDIT-BEGIN|fix-0041|compiled~%")

(cw "AUDIT-RESULT|fix-0041|compiled|~x0~%" (audit-acl2-0041))

(cw "AUDIT-BEGIN|fix-0041|direct~%")

(cw "AUDIT-RESULT|fix-0041|direct|~x0~%" (fix '#C(1 2)))

(defun audit-acl2-0042 () (fix NIL))

(verify-guards audit-acl2-0042)

(cw "AUDIT-BEGIN|fix-0042|compiled~%")

(cw "AUDIT-RESULT|fix-0042|compiled|~x0~%" (audit-acl2-0042))

(cw "AUDIT-BEGIN|fix-0042|direct~%")

(cw "AUDIT-RESULT|fix-0042|direct|~x0~%" (fix NIL))

(defun audit-acl2-0043 () (fix 'A))

(verify-guards audit-acl2-0043)

(cw "AUDIT-BEGIN|fix-0043|compiled~%")

(cw "AUDIT-RESULT|fix-0043|compiled|~x0~%" (audit-acl2-0043))

(cw "AUDIT-BEGIN|fix-0043|direct~%")

(cw "AUDIT-RESULT|fix-0043|direct|~x0~%" (fix 'A))

(defun audit-acl2-0044 () (fix '"text"))

(verify-guards audit-acl2-0044)

(cw "AUDIT-BEGIN|fix-0044|compiled~%")

(cw "AUDIT-RESULT|fix-0044|compiled|~x0~%" (audit-acl2-0044))

(cw "AUDIT-BEGIN|fix-0044|direct~%")

(cw "AUDIT-RESULT|fix-0044|direct|~x0~%" (fix '"text"))

(defun audit-acl2-0045 () (= '1 '1))

(verify-guards audit-acl2-0045)

(cw "AUDIT-BEGIN|=-0045|compiled~%")

(cw "AUDIT-RESULT|=-0045|compiled|~x0~%" (audit-acl2-0045))

(cw "AUDIT-BEGIN|=-0045|direct~%")

(cw "AUDIT-RESULT|=-0045|direct|~x0~%" (= '1 '1))

(defun audit-acl2-0046 () (= '1/2 '1/2))

(verify-guards audit-acl2-0046)

(cw "AUDIT-BEGIN|=-0046|compiled~%")

(cw "AUDIT-RESULT|=-0046|compiled|~x0~%" (audit-acl2-0046))

(cw "AUDIT-BEGIN|=-0046|direct~%")

(cw "AUDIT-RESULT|=-0046|direct|~x0~%" (= '1/2 '1/2))

(defun audit-acl2-0047 () (= '-2 '2))

(verify-guards audit-acl2-0047)

(cw "AUDIT-BEGIN|=-0047|compiled~%")

(cw "AUDIT-RESULT|=-0047|compiled|~x0~%" (audit-acl2-0047))

(cw "AUDIT-BEGIN|=-0047|direct~%")

(cw "AUDIT-RESULT|=-0047|direct|~x0~%" (= '-2 '2))

(defun audit-acl2-0048 () (= '#C(1 2) '#C(1 2)))

(verify-guards audit-acl2-0048)

(cw "AUDIT-BEGIN|=-0048|compiled~%")

(cw "AUDIT-RESULT|=-0048|compiled|~x0~%" (audit-acl2-0048))

(cw "AUDIT-BEGIN|=-0048|direct~%")

(cw "AUDIT-RESULT|=-0048|direct|~x0~%" (= '#C(1 2) '#C(1 2)))

(defun audit-acl2-0049 () (= '#C(1 2) '#C(1 3)))

(verify-guards audit-acl2-0049)

(cw "AUDIT-BEGIN|=-0049|compiled~%")

(cw "AUDIT-RESULT|=-0049|compiled|~x0~%" (audit-acl2-0049))

(cw "AUDIT-BEGIN|=-0049|direct~%")

(cw "AUDIT-RESULT|=-0049|direct|~x0~%" (= '#C(1 2) '#C(1 3)))

(defun audit-acl2-0050 () (= '#C(1 2) '1))

(verify-guards audit-acl2-0050)

(cw "AUDIT-BEGIN|=-0050|compiled~%")

(cw "AUDIT-RESULT|=-0050|compiled|~x0~%" (audit-acl2-0050))

(cw "AUDIT-BEGIN|=-0050|direct~%")

(cw "AUDIT-RESULT|=-0050|direct|~x0~%" (= '#C(1 2) '1))

(defun audit-acl2-0051 () (with-guard-checking NIL (ec-call (= 'A 'A))))

(verify-guards audit-acl2-0051)

(cw "AUDIT-BEGIN|=-0051|compiled~%")

(cw "AUDIT-RESULT|=-0051|compiled|~x0~%" (audit-acl2-0051))

(cw "AUDIT-BEGIN|=-0051|direct~%")

(cw "AUDIT-RESULT|=-0051|direct|~x0~%" (with-guard-checking NIL (ec-call (= 'A 'A))))

(defun audit-acl2-0052 () (with-guard-checking NIL (ec-call (= 'A '0))))

(verify-guards audit-acl2-0052)

(cw "AUDIT-BEGIN|=-0052|compiled~%")

(cw "AUDIT-RESULT|=-0052|compiled|~x0~%" (audit-acl2-0052))

(cw "AUDIT-BEGIN|=-0052|direct~%")

(cw "AUDIT-RESULT|=-0052|direct|~x0~%" (with-guard-checking NIL (ec-call (= 'A '0))))

(defun audit-acl2-0053 () (with-guard-checking NIL (ec-call (= NIL '1))))

(verify-guards audit-acl2-0053)

(cw "AUDIT-BEGIN|=-0053|compiled~%")

(cw "AUDIT-RESULT|=-0053|compiled|~x0~%" (audit-acl2-0053))

(cw "AUDIT-BEGIN|=-0053|direct~%")

(cw "AUDIT-RESULT|=-0053|direct|~x0~%" (with-guard-checking NIL (ec-call (= NIL '1))))

(defun audit-acl2-0054 () (with-guard-checking NIL (ec-call (= '"x" '0))))

(verify-guards audit-acl2-0054)

(cw "AUDIT-BEGIN|=-0054|compiled~%")

(cw "AUDIT-RESULT|=-0054|compiled|~x0~%" (audit-acl2-0054))

(cw "AUDIT-BEGIN|=-0054|direct~%")

(cw "AUDIT-RESULT|=-0054|direct|~x0~%" (with-guard-checking NIL (ec-call (= '"x" '0))))

(defun audit-acl2-0055 () (/= '1 '1))

(verify-guards audit-acl2-0055)

(cw "AUDIT-BEGIN|/=-0055|compiled~%")

(cw "AUDIT-RESULT|/=-0055|compiled|~x0~%" (audit-acl2-0055))

(cw "AUDIT-BEGIN|/=-0055|direct~%")

(cw "AUDIT-RESULT|/=-0055|direct|~x0~%" (/= '1 '1))

(defun audit-acl2-0056 () (/= '1/2 '1/2))

(verify-guards audit-acl2-0056)

(cw "AUDIT-BEGIN|/=-0056|compiled~%")

(cw "AUDIT-RESULT|/=-0056|compiled|~x0~%" (audit-acl2-0056))

(cw "AUDIT-BEGIN|/=-0056|direct~%")

(cw "AUDIT-RESULT|/=-0056|direct|~x0~%" (/= '1/2 '1/2))

(defun audit-acl2-0057 () (/= '-2 '2))

(verify-guards audit-acl2-0057)

(cw "AUDIT-BEGIN|/=-0057|compiled~%")

(cw "AUDIT-RESULT|/=-0057|compiled|~x0~%" (audit-acl2-0057))

(cw "AUDIT-BEGIN|/=-0057|direct~%")

(cw "AUDIT-RESULT|/=-0057|direct|~x0~%" (/= '-2 '2))

(defun audit-acl2-0058 () (/= '#C(1 2) '#C(1 2)))

(verify-guards audit-acl2-0058)

(cw "AUDIT-BEGIN|/=-0058|compiled~%")

(cw "AUDIT-RESULT|/=-0058|compiled|~x0~%" (audit-acl2-0058))

(cw "AUDIT-BEGIN|/=-0058|direct~%")

(cw "AUDIT-RESULT|/=-0058|direct|~x0~%" (/= '#C(1 2) '#C(1 2)))

(defun audit-acl2-0059 () (/= '#C(1 2) '#C(1 3)))

(verify-guards audit-acl2-0059)

(cw "AUDIT-BEGIN|/=-0059|compiled~%")

(cw "AUDIT-RESULT|/=-0059|compiled|~x0~%" (audit-acl2-0059))

(cw "AUDIT-BEGIN|/=-0059|direct~%")

(cw "AUDIT-RESULT|/=-0059|direct|~x0~%" (/= '#C(1 2) '#C(1 3)))

(defun audit-acl2-0060 () (/= '#C(1 2) '1))

(verify-guards audit-acl2-0060)

(cw "AUDIT-BEGIN|/=-0060|compiled~%")

(cw "AUDIT-RESULT|/=-0060|compiled|~x0~%" (audit-acl2-0060))

(cw "AUDIT-BEGIN|/=-0060|direct~%")

(cw "AUDIT-RESULT|/=-0060|direct|~x0~%" (/= '#C(1 2) '1))

(defun audit-acl2-0061 () (with-guard-checking NIL (ec-call (/= 'A 'A))))

(verify-guards audit-acl2-0061)

(cw "AUDIT-BEGIN|/=-0061|compiled~%")

(cw "AUDIT-RESULT|/=-0061|compiled|~x0~%" (audit-acl2-0061))

(cw "AUDIT-BEGIN|/=-0061|direct~%")

(cw "AUDIT-RESULT|/=-0061|direct|~x0~%" (with-guard-checking NIL (ec-call (/= 'A 'A))))

(defun audit-acl2-0062 () (with-guard-checking NIL (ec-call (/= 'A '0))))

(verify-guards audit-acl2-0062)

(cw "AUDIT-BEGIN|/=-0062|compiled~%")

(cw "AUDIT-RESULT|/=-0062|compiled|~x0~%" (audit-acl2-0062))

(cw "AUDIT-BEGIN|/=-0062|direct~%")

(cw "AUDIT-RESULT|/=-0062|direct|~x0~%" (with-guard-checking NIL (ec-call (/= 'A '0))))

(defun audit-acl2-0063 () (with-guard-checking NIL (ec-call (/= NIL '1))))

(verify-guards audit-acl2-0063)

(cw "AUDIT-BEGIN|/=-0063|compiled~%")

(cw "AUDIT-RESULT|/=-0063|compiled|~x0~%" (audit-acl2-0063))

(cw "AUDIT-BEGIN|/=-0063|direct~%")

(cw "AUDIT-RESULT|/=-0063|direct|~x0~%" (with-guard-checking NIL (ec-call (/= NIL '1))))

(defun audit-acl2-0064 () (with-guard-checking NIL (ec-call (/= '"x" '0))))

(verify-guards audit-acl2-0064)

(cw "AUDIT-BEGIN|/=-0064|compiled~%")

(cw "AUDIT-RESULT|/=-0064|compiled|~x0~%" (audit-acl2-0064))

(cw "AUDIT-BEGIN|/=-0064|direct~%")

(cw "AUDIT-RESULT|/=-0064|direct|~x0~%" (with-guard-checking NIL (ec-call (/= '"x" '0))))

(defun audit-acl2-0065 () (car NIL))

(verify-guards audit-acl2-0065)

(cw "AUDIT-BEGIN|car-0065|compiled~%")

(cw "AUDIT-RESULT|car-0065|compiled|~x0~%" (audit-acl2-0065))

(cw "AUDIT-BEGIN|car-0065|direct~%")

(cw "AUDIT-RESULT|car-0065|direct|~x0~%" (car NIL))

(defun audit-acl2-0066 () (car '(1 2 3)))

(verify-guards audit-acl2-0066)

(cw "AUDIT-BEGIN|car-0066|compiled~%")

(cw "AUDIT-RESULT|car-0066|compiled|~x0~%" (audit-acl2-0066))

(cw "AUDIT-BEGIN|car-0066|direct~%")

(cw "AUDIT-RESULT|car-0066|direct|~x0~%" (car '(1 2 3)))

(defun audit-acl2-0067 () (car '(1 2 . 3)))

(verify-guards audit-acl2-0067)

(cw "AUDIT-BEGIN|car-0067|compiled~%")

(cw "AUDIT-RESULT|car-0067|compiled|~x0~%" (audit-acl2-0067))

(cw "AUDIT-BEGIN|car-0067|direct~%")

(cw "AUDIT-RESULT|car-0067|direct|~x0~%" (car '(1 2 . 3)))

(defun audit-acl2-0068 () (with-guard-checking NIL (ec-call (car '7))))

(verify-guards audit-acl2-0068)

(cw "AUDIT-BEGIN|car-0068|compiled~%")

(cw "AUDIT-RESULT|car-0068|compiled|~x0~%" (audit-acl2-0068))

(cw "AUDIT-BEGIN|car-0068|direct~%")

(cw "AUDIT-RESULT|car-0068|direct|~x0~%" (with-guard-checking NIL (ec-call (car '7))))

(defun audit-acl2-0069 () (with-guard-checking NIL (ec-call (car 'A))))

(verify-guards audit-acl2-0069)

(cw "AUDIT-BEGIN|car-0069|compiled~%")

(cw "AUDIT-RESULT|car-0069|compiled|~x0~%" (audit-acl2-0069))

(cw "AUDIT-BEGIN|car-0069|direct~%")

(cw "AUDIT-RESULT|car-0069|direct|~x0~%" (with-guard-checking NIL (ec-call (car 'A))))

(defun audit-acl2-0070 () (with-guard-checking NIL (ec-call (car '"atom"))))

(verify-guards audit-acl2-0070)

(cw "AUDIT-BEGIN|car-0070|compiled~%")

(cw "AUDIT-RESULT|car-0070|compiled|~x0~%" (audit-acl2-0070))

(cw "AUDIT-BEGIN|car-0070|direct~%")

(cw "AUDIT-RESULT|car-0070|direct|~x0~%" (with-guard-checking NIL (ec-call (car '"atom"))))

(defun audit-acl2-0071 () (cdr NIL))

(verify-guards audit-acl2-0071)

(cw "AUDIT-BEGIN|cdr-0071|compiled~%")

(cw "AUDIT-RESULT|cdr-0071|compiled|~x0~%" (audit-acl2-0071))

(cw "AUDIT-BEGIN|cdr-0071|direct~%")

(cw "AUDIT-RESULT|cdr-0071|direct|~x0~%" (cdr NIL))

(defun audit-acl2-0072 () (cdr '(1 2 3)))

(verify-guards audit-acl2-0072)

(cw "AUDIT-BEGIN|cdr-0072|compiled~%")

(cw "AUDIT-RESULT|cdr-0072|compiled|~x0~%" (audit-acl2-0072))

(cw "AUDIT-BEGIN|cdr-0072|direct~%")

(cw "AUDIT-RESULT|cdr-0072|direct|~x0~%" (cdr '(1 2 3)))

(defun audit-acl2-0073 () (cdr '(1 2 . 3)))

(verify-guards audit-acl2-0073)

(cw "AUDIT-BEGIN|cdr-0073|compiled~%")

(cw "AUDIT-RESULT|cdr-0073|compiled|~x0~%" (audit-acl2-0073))

(cw "AUDIT-BEGIN|cdr-0073|direct~%")

(cw "AUDIT-RESULT|cdr-0073|direct|~x0~%" (cdr '(1 2 . 3)))

(defun audit-acl2-0074 () (with-guard-checking NIL (ec-call (cdr '7))))

(verify-guards audit-acl2-0074)

(cw "AUDIT-BEGIN|cdr-0074|compiled~%")

(cw "AUDIT-RESULT|cdr-0074|compiled|~x0~%" (audit-acl2-0074))

(cw "AUDIT-BEGIN|cdr-0074|direct~%")

(cw "AUDIT-RESULT|cdr-0074|direct|~x0~%" (with-guard-checking NIL (ec-call (cdr '7))))

(defun audit-acl2-0075 () (with-guard-checking NIL (ec-call (cdr 'A))))

(verify-guards audit-acl2-0075)

(cw "AUDIT-BEGIN|cdr-0075|compiled~%")

(cw "AUDIT-RESULT|cdr-0075|compiled|~x0~%" (audit-acl2-0075))

(cw "AUDIT-BEGIN|cdr-0075|direct~%")

(cw "AUDIT-RESULT|cdr-0075|direct|~x0~%" (with-guard-checking NIL (ec-call (cdr 'A))))

(defun audit-acl2-0076 () (with-guard-checking NIL (ec-call (cdr '"atom"))))

(verify-guards audit-acl2-0076)

(cw "AUDIT-BEGIN|cdr-0076|compiled~%")

(cw "AUDIT-RESULT|cdr-0076|compiled|~x0~%" (audit-acl2-0076))

(cw "AUDIT-BEGIN|cdr-0076|direct~%")

(cw "AUDIT-RESULT|cdr-0076|direct|~x0~%" (with-guard-checking NIL (ec-call (cdr '"atom"))))

(defun audit-acl2-0077 () (len NIL))

(verify-guards audit-acl2-0077)

(cw "AUDIT-BEGIN|len-0077|compiled~%")

(cw "AUDIT-RESULT|len-0077|compiled|~x0~%" (audit-acl2-0077))

(cw "AUDIT-BEGIN|len-0077|direct~%")

(cw "AUDIT-RESULT|len-0077|direct|~x0~%" (len NIL))

(defun audit-acl2-0078 () (len '(1)))

(verify-guards audit-acl2-0078)

(cw "AUDIT-BEGIN|len-0078|compiled~%")

(cw "AUDIT-RESULT|len-0078|compiled|~x0~%" (audit-acl2-0078))

(cw "AUDIT-BEGIN|len-0078|direct~%")

(cw "AUDIT-RESULT|len-0078|direct|~x0~%" (len '(1)))

(defun audit-acl2-0079 () (len '(1 2 3)))

(verify-guards audit-acl2-0079)

(cw "AUDIT-BEGIN|len-0079|compiled~%")

(cw "AUDIT-RESULT|len-0079|compiled|~x0~%" (audit-acl2-0079))

(cw "AUDIT-BEGIN|len-0079|direct~%")

(cw "AUDIT-RESULT|len-0079|direct|~x0~%" (len '(1 2 3)))

(defun audit-acl2-0080 () (len '(1 . 2)))

(verify-guards audit-acl2-0080)

(cw "AUDIT-BEGIN|len-0080|compiled~%")

(cw "AUDIT-RESULT|len-0080|compiled|~x0~%" (audit-acl2-0080))

(cw "AUDIT-BEGIN|len-0080|direct~%")

(cw "AUDIT-RESULT|len-0080|direct|~x0~%" (len '(1 . 2)))

(defun audit-acl2-0081 () (len '(1 2 . 3)))

(verify-guards audit-acl2-0081)

(cw "AUDIT-BEGIN|len-0081|compiled~%")

(cw "AUDIT-RESULT|len-0081|compiled|~x0~%" (audit-acl2-0081))

(cw "AUDIT-BEGIN|len-0081|direct~%")

(cw "AUDIT-RESULT|len-0081|direct|~x0~%" (len '(1 2 . 3)))

(defun audit-acl2-0082 () (len '9))

(verify-guards audit-acl2-0082)

(cw "AUDIT-BEGIN|len-0082|compiled~%")

(cw "AUDIT-RESULT|len-0082|compiled|~x0~%" (audit-acl2-0082))

(cw "AUDIT-BEGIN|len-0082|direct~%")

(cw "AUDIT-RESULT|len-0082|direct|~x0~%" (len '9))

(defun audit-acl2-0083 () (len 'A))

(verify-guards audit-acl2-0083)

(cw "AUDIT-BEGIN|len-0083|compiled~%")

(cw "AUDIT-RESULT|len-0083|compiled|~x0~%" (audit-acl2-0083))

(cw "AUDIT-BEGIN|len-0083|direct~%")

(cw "AUDIT-RESULT|len-0083|direct|~x0~%" (len 'A))

(defun audit-acl2-0084 () (len '""))

(verify-guards audit-acl2-0084)

(cw "AUDIT-BEGIN|len-0084|compiled~%")

(cw "AUDIT-RESULT|len-0084|compiled|~x0~%" (audit-acl2-0084))

(cw "AUDIT-BEGIN|len-0084|direct~%")

(cw "AUDIT-RESULT|len-0084|direct|~x0~%" (len '""))

(defun audit-acl2-0085 () (len '"abc"))

(verify-guards audit-acl2-0085)

(cw "AUDIT-BEGIN|len-0085|compiled~%")

(cw "AUDIT-RESULT|len-0085|compiled|~x0~%" (audit-acl2-0085))

(cw "AUDIT-BEGIN|len-0085|direct~%")

(cw "AUDIT-RESULT|len-0085|direct|~x0~%" (len '"abc"))

(defun audit-acl2-0086 () (len '"a\"b\\c"))

(verify-guards audit-acl2-0086)

(cw "AUDIT-BEGIN|len-0086|compiled~%")

(cw "AUDIT-RESULT|len-0086|compiled|~x0~%" (audit-acl2-0086))

(cw "AUDIT-BEGIN|len-0086|direct~%")

(cw "AUDIT-RESULT|len-0086|direct|~x0~%" (len '"a\"b\\c"))

(defun audit-acl2-0087 () (mod '-7 '-3))

(verify-guards audit-acl2-0087)

(cw "AUDIT-BEGIN|mod-0087|compiled~%")

(cw "AUDIT-RESULT|mod-0087|compiled|~x0~%" (audit-acl2-0087))

(cw "AUDIT-BEGIN|mod-0087|direct~%")

(cw "AUDIT-RESULT|mod-0087|direct|~x0~%" (mod '-7 '-3))

(defun audit-acl2-0088 () (mod '-7 '-2/3))

(verify-guards audit-acl2-0088)

(cw "AUDIT-BEGIN|mod-0088|compiled~%")

(cw "AUDIT-RESULT|mod-0088|compiled|~x0~%" (audit-acl2-0088))

(cw "AUDIT-BEGIN|mod-0088|direct~%")

(cw "AUDIT-RESULT|mod-0088|direct|~x0~%" (mod '-7 '-2/3))

(defun audit-acl2-0089 () (mod '-7 '2/3))

(verify-guards audit-acl2-0089)

(cw "AUDIT-BEGIN|mod-0089|compiled~%")

(cw "AUDIT-RESULT|mod-0089|compiled|~x0~%" (audit-acl2-0089))

(cw "AUDIT-BEGIN|mod-0089|direct~%")

(cw "AUDIT-RESULT|mod-0089|direct|~x0~%" (mod '-7 '2/3))

(defun audit-acl2-0090 () (mod '-7 '3))

(verify-guards audit-acl2-0090)

(cw "AUDIT-BEGIN|mod-0090|compiled~%")

(cw "AUDIT-RESULT|mod-0090|compiled|~x0~%" (audit-acl2-0090))

(cw "AUDIT-BEGIN|mod-0090|direct~%")

(cw "AUDIT-RESULT|mod-0090|direct|~x0~%" (mod '-7 '3))

(defun audit-acl2-0091 () (with-guard-checking NIL (ec-call (mod '-7 '0))))

(verify-guards audit-acl2-0091)

(cw "AUDIT-BEGIN|mod-0091|compiled~%")

(cw "AUDIT-RESULT|mod-0091|compiled|~x0~%" (audit-acl2-0091))

(cw "AUDIT-BEGIN|mod-0091|direct~%")

(cw "AUDIT-RESULT|mod-0091|direct|~x0~%" (with-guard-checking NIL (ec-call (mod '-7 '0))))

(defun audit-acl2-0092 () (mod '-5/2 '-3))

(verify-guards audit-acl2-0092)

(cw "AUDIT-BEGIN|mod-0092|compiled~%")

(cw "AUDIT-RESULT|mod-0092|compiled|~x0~%" (audit-acl2-0092))

(cw "AUDIT-BEGIN|mod-0092|direct~%")

(cw "AUDIT-RESULT|mod-0092|direct|~x0~%" (mod '-5/2 '-3))

(defun audit-acl2-0093 () (mod '-5/2 '-2/3))

(verify-guards audit-acl2-0093)

(cw "AUDIT-BEGIN|mod-0093|compiled~%")

(cw "AUDIT-RESULT|mod-0093|compiled|~x0~%" (audit-acl2-0093))

(cw "AUDIT-BEGIN|mod-0093|direct~%")

(cw "AUDIT-RESULT|mod-0093|direct|~x0~%" (mod '-5/2 '-2/3))

(defun audit-acl2-0094 () (mod '-5/2 '2/3))

(verify-guards audit-acl2-0094)

(cw "AUDIT-BEGIN|mod-0094|compiled~%")

(cw "AUDIT-RESULT|mod-0094|compiled|~x0~%" (audit-acl2-0094))

(cw "AUDIT-BEGIN|mod-0094|direct~%")

(cw "AUDIT-RESULT|mod-0094|direct|~x0~%" (mod '-5/2 '2/3))

(defun audit-acl2-0095 () (mod '-5/2 '3))

(verify-guards audit-acl2-0095)

(cw "AUDIT-BEGIN|mod-0095|compiled~%")

(cw "AUDIT-RESULT|mod-0095|compiled|~x0~%" (audit-acl2-0095))

(cw "AUDIT-BEGIN|mod-0095|direct~%")

(cw "AUDIT-RESULT|mod-0095|direct|~x0~%" (mod '-5/2 '3))

(defun audit-acl2-0096 () (with-guard-checking NIL (ec-call (mod '-5/2 '0))))

(verify-guards audit-acl2-0096)

(cw "AUDIT-BEGIN|mod-0096|compiled~%")

(cw "AUDIT-RESULT|mod-0096|compiled|~x0~%" (audit-acl2-0096))

(cw "AUDIT-BEGIN|mod-0096|direct~%")

(cw "AUDIT-RESULT|mod-0096|direct|~x0~%" (with-guard-checking NIL (ec-call (mod '-5/2 '0))))

(defun audit-acl2-0097 () (mod '0 '-3))

(verify-guards audit-acl2-0097)

(cw "AUDIT-BEGIN|mod-0097|compiled~%")

(cw "AUDIT-RESULT|mod-0097|compiled|~x0~%" (audit-acl2-0097))

(cw "AUDIT-BEGIN|mod-0097|direct~%")

(cw "AUDIT-RESULT|mod-0097|direct|~x0~%" (mod '0 '-3))

(defun audit-acl2-0098 () (mod '0 '-2/3))

(verify-guards audit-acl2-0098)

(cw "AUDIT-BEGIN|mod-0098|compiled~%")

(cw "AUDIT-RESULT|mod-0098|compiled|~x0~%" (audit-acl2-0098))

(cw "AUDIT-BEGIN|mod-0098|direct~%")

(cw "AUDIT-RESULT|mod-0098|direct|~x0~%" (mod '0 '-2/3))

(defun audit-acl2-0099 () (mod '0 '2/3))

(verify-guards audit-acl2-0099)

(cw "AUDIT-BEGIN|mod-0099|compiled~%")

(cw "AUDIT-RESULT|mod-0099|compiled|~x0~%" (audit-acl2-0099))

(cw "AUDIT-BEGIN|mod-0099|direct~%")

(cw "AUDIT-RESULT|mod-0099|direct|~x0~%" (mod '0 '2/3))

(defun audit-acl2-0100 () (mod '0 '3))

(verify-guards audit-acl2-0100)

(cw "AUDIT-BEGIN|mod-0100|compiled~%")

(cw "AUDIT-RESULT|mod-0100|compiled|~x0~%" (audit-acl2-0100))

(cw "AUDIT-BEGIN|mod-0100|direct~%")

(cw "AUDIT-RESULT|mod-0100|direct|~x0~%" (mod '0 '3))

(defun audit-acl2-0101 () (with-guard-checking NIL (ec-call (mod '0 '0))))

(verify-guards audit-acl2-0101)

(cw "AUDIT-BEGIN|mod-0101|compiled~%")

(cw "AUDIT-RESULT|mod-0101|compiled|~x0~%" (audit-acl2-0101))

(cw "AUDIT-BEGIN|mod-0101|direct~%")

(cw "AUDIT-RESULT|mod-0101|direct|~x0~%" (with-guard-checking NIL (ec-call (mod '0 '0))))

(defun audit-acl2-0102 () (mod '5/2 '-3))

(verify-guards audit-acl2-0102)

(cw "AUDIT-BEGIN|mod-0102|compiled~%")

(cw "AUDIT-RESULT|mod-0102|compiled|~x0~%" (audit-acl2-0102))

(cw "AUDIT-BEGIN|mod-0102|direct~%")

(cw "AUDIT-RESULT|mod-0102|direct|~x0~%" (mod '5/2 '-3))

(defun audit-acl2-0103 () (mod '5/2 '-2/3))

(verify-guards audit-acl2-0103)

(cw "AUDIT-BEGIN|mod-0103|compiled~%")

(cw "AUDIT-RESULT|mod-0103|compiled|~x0~%" (audit-acl2-0103))

(cw "AUDIT-BEGIN|mod-0103|direct~%")

(cw "AUDIT-RESULT|mod-0103|direct|~x0~%" (mod '5/2 '-2/3))

(defun audit-acl2-0104 () (mod '5/2 '2/3))

(verify-guards audit-acl2-0104)

(cw "AUDIT-BEGIN|mod-0104|compiled~%")

(cw "AUDIT-RESULT|mod-0104|compiled|~x0~%" (audit-acl2-0104))

(cw "AUDIT-BEGIN|mod-0104|direct~%")

(cw "AUDIT-RESULT|mod-0104|direct|~x0~%" (mod '5/2 '2/3))

(defun audit-acl2-0105 () (mod '5/2 '3))

(verify-guards audit-acl2-0105)

(cw "AUDIT-BEGIN|mod-0105|compiled~%")

(cw "AUDIT-RESULT|mod-0105|compiled|~x0~%" (audit-acl2-0105))

(cw "AUDIT-BEGIN|mod-0105|direct~%")

(cw "AUDIT-RESULT|mod-0105|direct|~x0~%" (mod '5/2 '3))

(defun audit-acl2-0106 () (with-guard-checking NIL (ec-call (mod '5/2 '0))))

(verify-guards audit-acl2-0106)

(cw "AUDIT-BEGIN|mod-0106|compiled~%")

(cw "AUDIT-RESULT|mod-0106|compiled|~x0~%" (audit-acl2-0106))

(cw "AUDIT-BEGIN|mod-0106|direct~%")

(cw "AUDIT-RESULT|mod-0106|direct|~x0~%" (with-guard-checking NIL (ec-call (mod '5/2 '0))))

(defun audit-acl2-0107 () (mod '7 '-3))

(verify-guards audit-acl2-0107)

(cw "AUDIT-BEGIN|mod-0107|compiled~%")

(cw "AUDIT-RESULT|mod-0107|compiled|~x0~%" (audit-acl2-0107))

(cw "AUDIT-BEGIN|mod-0107|direct~%")

(cw "AUDIT-RESULT|mod-0107|direct|~x0~%" (mod '7 '-3))

(defun audit-acl2-0108 () (mod '7 '-2/3))

(verify-guards audit-acl2-0108)

(cw "AUDIT-BEGIN|mod-0108|compiled~%")

(cw "AUDIT-RESULT|mod-0108|compiled|~x0~%" (audit-acl2-0108))

(cw "AUDIT-BEGIN|mod-0108|direct~%")

(cw "AUDIT-RESULT|mod-0108|direct|~x0~%" (mod '7 '-2/3))

(defun audit-acl2-0109 () (mod '7 '2/3))

(verify-guards audit-acl2-0109)

(cw "AUDIT-BEGIN|mod-0109|compiled~%")

(cw "AUDIT-RESULT|mod-0109|compiled|~x0~%" (audit-acl2-0109))

(cw "AUDIT-BEGIN|mod-0109|direct~%")

(cw "AUDIT-RESULT|mod-0109|direct|~x0~%" (mod '7 '2/3))

(defun audit-acl2-0110 () (mod '7 '3))

(verify-guards audit-acl2-0110)

(cw "AUDIT-BEGIN|mod-0110|compiled~%")

(cw "AUDIT-RESULT|mod-0110|compiled|~x0~%" (audit-acl2-0110))

(cw "AUDIT-BEGIN|mod-0110|direct~%")

(cw "AUDIT-RESULT|mod-0110|direct|~x0~%" (mod '7 '3))

(defun audit-acl2-0111 () (with-guard-checking NIL (ec-call (mod '7 '0))))

(verify-guards audit-acl2-0111)

(cw "AUDIT-BEGIN|mod-0111|compiled~%")

(cw "AUDIT-RESULT|mod-0111|compiled|~x0~%" (audit-acl2-0111))

(cw "AUDIT-BEGIN|mod-0111|direct~%")

(cw "AUDIT-RESULT|mod-0111|direct|~x0~%" (with-guard-checking NIL (ec-call (mod '7 '0))))

(defun audit-acl2-0112 () (rem '-7 '-3))

(verify-guards audit-acl2-0112)

(cw "AUDIT-BEGIN|rem-0112|compiled~%")

(cw "AUDIT-RESULT|rem-0112|compiled|~x0~%" (audit-acl2-0112))

(cw "AUDIT-BEGIN|rem-0112|direct~%")

(cw "AUDIT-RESULT|rem-0112|direct|~x0~%" (rem '-7 '-3))

(defun audit-acl2-0113 () (rem '-7 '-2/3))

(verify-guards audit-acl2-0113)

(cw "AUDIT-BEGIN|rem-0113|compiled~%")

(cw "AUDIT-RESULT|rem-0113|compiled|~x0~%" (audit-acl2-0113))

(cw "AUDIT-BEGIN|rem-0113|direct~%")

(cw "AUDIT-RESULT|rem-0113|direct|~x0~%" (rem '-7 '-2/3))

(defun audit-acl2-0114 () (rem '-7 '2/3))

(verify-guards audit-acl2-0114)

(cw "AUDIT-BEGIN|rem-0114|compiled~%")

(cw "AUDIT-RESULT|rem-0114|compiled|~x0~%" (audit-acl2-0114))

(cw "AUDIT-BEGIN|rem-0114|direct~%")

(cw "AUDIT-RESULT|rem-0114|direct|~x0~%" (rem '-7 '2/3))

(defun audit-acl2-0115 () (rem '-7 '3))

(verify-guards audit-acl2-0115)

(cw "AUDIT-BEGIN|rem-0115|compiled~%")

(cw "AUDIT-RESULT|rem-0115|compiled|~x0~%" (audit-acl2-0115))

(cw "AUDIT-BEGIN|rem-0115|direct~%")

(cw "AUDIT-RESULT|rem-0115|direct|~x0~%" (rem '-7 '3))

(defun audit-acl2-0116 () (with-guard-checking NIL (ec-call (rem '-7 '0))))

(verify-guards audit-acl2-0116)

(cw "AUDIT-BEGIN|rem-0116|compiled~%")

(cw "AUDIT-RESULT|rem-0116|compiled|~x0~%" (audit-acl2-0116))

(cw "AUDIT-BEGIN|rem-0116|direct~%")

(cw "AUDIT-RESULT|rem-0116|direct|~x0~%" (with-guard-checking NIL (ec-call (rem '-7 '0))))

(defun audit-acl2-0117 () (rem '-5/2 '-3))

(verify-guards audit-acl2-0117)

(cw "AUDIT-BEGIN|rem-0117|compiled~%")

(cw "AUDIT-RESULT|rem-0117|compiled|~x0~%" (audit-acl2-0117))

(cw "AUDIT-BEGIN|rem-0117|direct~%")

(cw "AUDIT-RESULT|rem-0117|direct|~x0~%" (rem '-5/2 '-3))

(defun audit-acl2-0118 () (rem '-5/2 '-2/3))

(verify-guards audit-acl2-0118)

(cw "AUDIT-BEGIN|rem-0118|compiled~%")

(cw "AUDIT-RESULT|rem-0118|compiled|~x0~%" (audit-acl2-0118))

(cw "AUDIT-BEGIN|rem-0118|direct~%")

(cw "AUDIT-RESULT|rem-0118|direct|~x0~%" (rem '-5/2 '-2/3))

(defun audit-acl2-0119 () (rem '-5/2 '2/3))

(verify-guards audit-acl2-0119)

(cw "AUDIT-BEGIN|rem-0119|compiled~%")

(cw "AUDIT-RESULT|rem-0119|compiled|~x0~%" (audit-acl2-0119))

(cw "AUDIT-BEGIN|rem-0119|direct~%")

(cw "AUDIT-RESULT|rem-0119|direct|~x0~%" (rem '-5/2 '2/3))

(defun audit-acl2-0120 () (rem '-5/2 '3))

(verify-guards audit-acl2-0120)

(cw "AUDIT-BEGIN|rem-0120|compiled~%")

(cw "AUDIT-RESULT|rem-0120|compiled|~x0~%" (audit-acl2-0120))

(cw "AUDIT-BEGIN|rem-0120|direct~%")

(cw "AUDIT-RESULT|rem-0120|direct|~x0~%" (rem '-5/2 '3))

(defun audit-acl2-0121 () (with-guard-checking NIL (ec-call (rem '-5/2 '0))))

(verify-guards audit-acl2-0121)

(cw "AUDIT-BEGIN|rem-0121|compiled~%")

(cw "AUDIT-RESULT|rem-0121|compiled|~x0~%" (audit-acl2-0121))

(cw "AUDIT-BEGIN|rem-0121|direct~%")

(cw "AUDIT-RESULT|rem-0121|direct|~x0~%" (with-guard-checking NIL (ec-call (rem '-5/2 '0))))

(defun audit-acl2-0122 () (rem '0 '-3))

(verify-guards audit-acl2-0122)

(cw "AUDIT-BEGIN|rem-0122|compiled~%")

(cw "AUDIT-RESULT|rem-0122|compiled|~x0~%" (audit-acl2-0122))

(cw "AUDIT-BEGIN|rem-0122|direct~%")

(cw "AUDIT-RESULT|rem-0122|direct|~x0~%" (rem '0 '-3))

(defun audit-acl2-0123 () (rem '0 '-2/3))

(verify-guards audit-acl2-0123)

(cw "AUDIT-BEGIN|rem-0123|compiled~%")

(cw "AUDIT-RESULT|rem-0123|compiled|~x0~%" (audit-acl2-0123))

(cw "AUDIT-BEGIN|rem-0123|direct~%")

(cw "AUDIT-RESULT|rem-0123|direct|~x0~%" (rem '0 '-2/3))

(defun audit-acl2-0124 () (rem '0 '2/3))

(verify-guards audit-acl2-0124)

(cw "AUDIT-BEGIN|rem-0124|compiled~%")

(cw "AUDIT-RESULT|rem-0124|compiled|~x0~%" (audit-acl2-0124))

(cw "AUDIT-BEGIN|rem-0124|direct~%")

(cw "AUDIT-RESULT|rem-0124|direct|~x0~%" (rem '0 '2/3))

(defun audit-acl2-0125 () (rem '0 '3))

(verify-guards audit-acl2-0125)

(cw "AUDIT-BEGIN|rem-0125|compiled~%")

(cw "AUDIT-RESULT|rem-0125|compiled|~x0~%" (audit-acl2-0125))

(cw "AUDIT-BEGIN|rem-0125|direct~%")

(cw "AUDIT-RESULT|rem-0125|direct|~x0~%" (rem '0 '3))

(defun audit-acl2-0126 () (with-guard-checking NIL (ec-call (rem '0 '0))))

(verify-guards audit-acl2-0126)

(cw "AUDIT-BEGIN|rem-0126|compiled~%")

(cw "AUDIT-RESULT|rem-0126|compiled|~x0~%" (audit-acl2-0126))

(cw "AUDIT-BEGIN|rem-0126|direct~%")

(cw "AUDIT-RESULT|rem-0126|direct|~x0~%" (with-guard-checking NIL (ec-call (rem '0 '0))))

(defun audit-acl2-0127 () (rem '5/2 '-3))

(verify-guards audit-acl2-0127)

(cw "AUDIT-BEGIN|rem-0127|compiled~%")

(cw "AUDIT-RESULT|rem-0127|compiled|~x0~%" (audit-acl2-0127))

(cw "AUDIT-BEGIN|rem-0127|direct~%")

(cw "AUDIT-RESULT|rem-0127|direct|~x0~%" (rem '5/2 '-3))

(defun audit-acl2-0128 () (rem '5/2 '-2/3))

(verify-guards audit-acl2-0128)

(cw "AUDIT-BEGIN|rem-0128|compiled~%")

(cw "AUDIT-RESULT|rem-0128|compiled|~x0~%" (audit-acl2-0128))

(cw "AUDIT-BEGIN|rem-0128|direct~%")

(cw "AUDIT-RESULT|rem-0128|direct|~x0~%" (rem '5/2 '-2/3))

(defun audit-acl2-0129 () (rem '5/2 '2/3))

(verify-guards audit-acl2-0129)

(cw "AUDIT-BEGIN|rem-0129|compiled~%")

(cw "AUDIT-RESULT|rem-0129|compiled|~x0~%" (audit-acl2-0129))

(cw "AUDIT-BEGIN|rem-0129|direct~%")

(cw "AUDIT-RESULT|rem-0129|direct|~x0~%" (rem '5/2 '2/3))

(defun audit-acl2-0130 () (rem '5/2 '3))

(verify-guards audit-acl2-0130)

(cw "AUDIT-BEGIN|rem-0130|compiled~%")

(cw "AUDIT-RESULT|rem-0130|compiled|~x0~%" (audit-acl2-0130))

(cw "AUDIT-BEGIN|rem-0130|direct~%")

(cw "AUDIT-RESULT|rem-0130|direct|~x0~%" (rem '5/2 '3))

(defun audit-acl2-0131 () (with-guard-checking NIL (ec-call (rem '5/2 '0))))

(verify-guards audit-acl2-0131)

(cw "AUDIT-BEGIN|rem-0131|compiled~%")

(cw "AUDIT-RESULT|rem-0131|compiled|~x0~%" (audit-acl2-0131))

(cw "AUDIT-BEGIN|rem-0131|direct~%")

(cw "AUDIT-RESULT|rem-0131|direct|~x0~%" (with-guard-checking NIL (ec-call (rem '5/2 '0))))

(defun audit-acl2-0132 () (rem '7 '-3))

(verify-guards audit-acl2-0132)

(cw "AUDIT-BEGIN|rem-0132|compiled~%")

(cw "AUDIT-RESULT|rem-0132|compiled|~x0~%" (audit-acl2-0132))

(cw "AUDIT-BEGIN|rem-0132|direct~%")

(cw "AUDIT-RESULT|rem-0132|direct|~x0~%" (rem '7 '-3))

(defun audit-acl2-0133 () (rem '7 '-2/3))

(verify-guards audit-acl2-0133)

(cw "AUDIT-BEGIN|rem-0133|compiled~%")

(cw "AUDIT-RESULT|rem-0133|compiled|~x0~%" (audit-acl2-0133))

(cw "AUDIT-BEGIN|rem-0133|direct~%")

(cw "AUDIT-RESULT|rem-0133|direct|~x0~%" (rem '7 '-2/3))

(defun audit-acl2-0134 () (rem '7 '2/3))

(verify-guards audit-acl2-0134)

(cw "AUDIT-BEGIN|rem-0134|compiled~%")

(cw "AUDIT-RESULT|rem-0134|compiled|~x0~%" (audit-acl2-0134))

(cw "AUDIT-BEGIN|rem-0134|direct~%")

(cw "AUDIT-RESULT|rem-0134|direct|~x0~%" (rem '7 '2/3))

(defun audit-acl2-0135 () (rem '7 '3))

(verify-guards audit-acl2-0135)

(cw "AUDIT-BEGIN|rem-0135|compiled~%")

(cw "AUDIT-RESULT|rem-0135|compiled|~x0~%" (audit-acl2-0135))

(cw "AUDIT-BEGIN|rem-0135|direct~%")

(cw "AUDIT-RESULT|rem-0135|direct|~x0~%" (rem '7 '3))

(defun audit-acl2-0136 () (with-guard-checking NIL (ec-call (rem '7 '0))))

(verify-guards audit-acl2-0136)

(cw "AUDIT-BEGIN|rem-0136|compiled~%")

(cw "AUDIT-RESULT|rem-0136|compiled|~x0~%" (audit-acl2-0136))

(cw "AUDIT-BEGIN|rem-0136|direct~%")

(cw "AUDIT-RESULT|rem-0136|direct|~x0~%" (with-guard-checking NIL (ec-call (rem '7 '0))))

(defun audit-acl2-0137 () (nonnegative-integer-quotient '0 '1))

(verify-guards audit-acl2-0137)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0137|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0137|compiled|~x0~%" (audit-acl2-0137))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0137|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0137|direct|~x0~%" (nonnegative-integer-quotient '0 '1))

(defun audit-acl2-0138 () (nonnegative-integer-quotient '1 '2))

(verify-guards audit-acl2-0138)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0138|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0138|compiled|~x0~%" (audit-acl2-0138))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0138|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0138|direct|~x0~%" (nonnegative-integer-quotient '1 '2))

(defun audit-acl2-0139 () (nonnegative-integer-quotient '7 '3))

(verify-guards audit-acl2-0139)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0139|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0139|compiled|~x0~%" (audit-acl2-0139))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0139|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0139|direct|~x0~%" (nonnegative-integer-quotient '7 '3))

(defun audit-acl2-0140 () (nonnegative-integer-quotient '8 '3))

(verify-guards audit-acl2-0140)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0140|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0140|compiled|~x0~%" (audit-acl2-0140))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0140|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0140|direct|~x0~%" (nonnegative-integer-quotient '8 '3))

(defun audit-acl2-0141 () (nonnegative-integer-quotient '1180591620717411303433 '7))

(verify-guards audit-acl2-0141)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0141|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0141|compiled|~x0~%" (audit-acl2-0141))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0141|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0141|direct|~x0~%" (nonnegative-integer-quotient '1180591620717411303433 '7))

(defun audit-acl2-0142 () (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '7 '0))))

(verify-guards audit-acl2-0142)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0142|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0142|compiled|~x0~%" (audit-acl2-0142))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0142|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0142|direct|~x0~%" (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '7 '0))))

(defun audit-acl2-0143 () (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '-7 '2))))

(verify-guards audit-acl2-0143)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0143|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0143|compiled|~x0~%" (audit-acl2-0143))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0143|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0143|direct|~x0~%" (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '-7 '2))))

(defun audit-acl2-0144 () (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '7 '-2))))

(verify-guards audit-acl2-0144)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0144|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0144|compiled|~x0~%" (audit-acl2-0144))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0144|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0144|direct|~x0~%" (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '7 '-2))))

(defun audit-acl2-0145 () (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '1/2 '2))))

(verify-guards audit-acl2-0145)

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0145|compiled~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0145|compiled|~x0~%" (audit-acl2-0145))

(cw "AUDIT-BEGIN|nonnegative-integer-quotient-0145|direct~%")

(cw "AUDIT-RESULT|nonnegative-integer-quotient-0145|direct|~x0~%" (with-guard-checking NIL (ec-call (nonnegative-integer-quotient '1/2 '2))))

(defun audit-acl2-0146 () (expt '-2 '-3))

(verify-guards audit-acl2-0146)

(cw "AUDIT-BEGIN|expt-0146|compiled~%")

(cw "AUDIT-RESULT|expt-0146|compiled|~x0~%" (audit-acl2-0146))

(cw "AUDIT-BEGIN|expt-0146|direct~%")

(cw "AUDIT-RESULT|expt-0146|direct|~x0~%" (expt '-2 '-3))

(defun audit-acl2-0147 () (expt '-2 '3))

(verify-guards audit-acl2-0147)

(cw "AUDIT-BEGIN|expt-0147|compiled~%")

(cw "AUDIT-RESULT|expt-0147|compiled|~x0~%" (audit-acl2-0147))

(cw "AUDIT-BEGIN|expt-0147|direct~%")

(cw "AUDIT-RESULT|expt-0147|direct|~x0~%" (expt '-2 '3))

(defun audit-acl2-0148 () (expt '-1 '-4))

(verify-guards audit-acl2-0148)

(cw "AUDIT-BEGIN|expt-0148|compiled~%")

(cw "AUDIT-RESULT|expt-0148|compiled|~x0~%" (audit-acl2-0148))

(cw "AUDIT-BEGIN|expt-0148|direct~%")

(cw "AUDIT-RESULT|expt-0148|direct|~x0~%" (expt '-1 '-4))

(defun audit-acl2-0149 () (expt '-1 '5))

(verify-guards audit-acl2-0149)

(cw "AUDIT-BEGIN|expt-0149|compiled~%")

(cw "AUDIT-RESULT|expt-0149|compiled|~x0~%" (audit-acl2-0149))

(cw "AUDIT-BEGIN|expt-0149|direct~%")

(cw "AUDIT-RESULT|expt-0149|direct|~x0~%" (expt '-1 '5))

(defun audit-acl2-0150 () (expt '-1/2 '-2))

(verify-guards audit-acl2-0150)

(cw "AUDIT-BEGIN|expt-0150|compiled~%")

(cw "AUDIT-RESULT|expt-0150|compiled|~x0~%" (audit-acl2-0150))

(cw "AUDIT-BEGIN|expt-0150|direct~%")

(cw "AUDIT-RESULT|expt-0150|direct|~x0~%" (expt '-1/2 '-2))

(defun audit-acl2-0151 () (expt '-1/2 '3))

(verify-guards audit-acl2-0151)

(cw "AUDIT-BEGIN|expt-0151|compiled~%")

(cw "AUDIT-RESULT|expt-0151|compiled|~x0~%" (audit-acl2-0151))

(cw "AUDIT-BEGIN|expt-0151|direct~%")

(cw "AUDIT-RESULT|expt-0151|direct|~x0~%" (expt '-1/2 '3))

(defun audit-acl2-0152 () (expt '0 '0))

(verify-guards audit-acl2-0152)

(cw "AUDIT-BEGIN|expt-0152|compiled~%")

(cw "AUDIT-RESULT|expt-0152|compiled|~x0~%" (audit-acl2-0152))

(cw "AUDIT-BEGIN|expt-0152|direct~%")

(cw "AUDIT-RESULT|expt-0152|direct|~x0~%" (expt '0 '0))

(defun audit-acl2-0153 () (expt '0 '3))

(verify-guards audit-acl2-0153)

(cw "AUDIT-BEGIN|expt-0153|compiled~%")

(cw "AUDIT-RESULT|expt-0153|compiled|~x0~%" (audit-acl2-0153))

(cw "AUDIT-BEGIN|expt-0153|direct~%")

(cw "AUDIT-RESULT|expt-0153|direct|~x0~%" (expt '0 '3))

(defun audit-acl2-0154 () (with-guard-checking NIL (ec-call (expt '0 '-1))))

(verify-guards audit-acl2-0154)

(cw "AUDIT-BEGIN|expt-0154|compiled~%")

(cw "AUDIT-RESULT|expt-0154|compiled|~x0~%" (audit-acl2-0154))

(cw "AUDIT-BEGIN|expt-0154|direct~%")

(cw "AUDIT-RESULT|expt-0154|direct|~x0~%" (with-guard-checking NIL (ec-call (expt '0 '-1))))

(defun audit-acl2-0155 () (expt '1/2 '-3))

(verify-guards audit-acl2-0155)

(cw "AUDIT-BEGIN|expt-0155|compiled~%")

(cw "AUDIT-RESULT|expt-0155|compiled|~x0~%" (audit-acl2-0155))

(cw "AUDIT-BEGIN|expt-0155|direct~%")

(cw "AUDIT-RESULT|expt-0155|direct|~x0~%" (expt '1/2 '-3))

(defun audit-acl2-0156 () (expt '2 '0))

(verify-guards audit-acl2-0156)

(cw "AUDIT-BEGIN|expt-0156|compiled~%")

(cw "AUDIT-RESULT|expt-0156|compiled|~x0~%" (audit-acl2-0156))

(cw "AUDIT-BEGIN|expt-0156|direct~%")

(cw "AUDIT-RESULT|expt-0156|direct|~x0~%" (expt '2 '0))

(defun audit-acl2-0157 () (expt '2 '10))

(verify-guards audit-acl2-0157)

(cw "AUDIT-BEGIN|expt-0157|compiled~%")

(cw "AUDIT-RESULT|expt-0157|compiled|~x0~%" (audit-acl2-0157))

(cw "AUDIT-BEGIN|expt-0157|direct~%")

(cw "AUDIT-RESULT|expt-0157|direct|~x0~%" (expt '2 '10))

(defun audit-acl2-0158 () (expt '#C(1 1) '2))

(verify-guards audit-acl2-0158)

(cw "AUDIT-BEGIN|expt-0158|compiled~%")

(cw "AUDIT-RESULT|expt-0158|compiled|~x0~%" (audit-acl2-0158))

(cw "AUDIT-BEGIN|expt-0158|direct~%")

(cw "AUDIT-RESULT|expt-0158|direct|~x0~%" (expt '#C(1 1) '2))

(defun audit-acl2-0159 () (expt '#C(1 1) '-2))

(verify-guards audit-acl2-0159)

(cw "AUDIT-BEGIN|expt-0159|compiled~%")

(cw "AUDIT-RESULT|expt-0159|compiled|~x0~%" (audit-acl2-0159))

(cw "AUDIT-BEGIN|expt-0159|direct~%")

(cw "AUDIT-RESULT|expt-0159|direct|~x0~%" (expt '#C(1 1) '-2))

(defun audit-acl2-0160 () (expt '#C(1/2 -1/3) '3))

(verify-guards audit-acl2-0160)

(cw "AUDIT-BEGIN|expt-0160|compiled~%")

(cw "AUDIT-RESULT|expt-0160|compiled|~x0~%" (audit-acl2-0160))

(cw "AUDIT-BEGIN|expt-0160|direct~%")

(cw "AUDIT-RESULT|expt-0160|direct|~x0~%" (expt '#C(1/2 -1/3) '3))

(defun audit-acl2-0161 () (expt '#C(2 -1) '-1))

(verify-guards audit-acl2-0161)

(cw "AUDIT-BEGIN|expt-0161|compiled~%")

(cw "AUDIT-RESULT|expt-0161|compiled|~x0~%" (audit-acl2-0161))

(cw "AUDIT-BEGIN|expt-0161|direct~%")

(cw "AUDIT-RESULT|expt-0161|direct|~x0~%" (expt '#C(2 -1) '-1))

(defun audit-acl2-0162 () (loghead '0 '-65))

(verify-guards audit-acl2-0162)

(cw "AUDIT-BEGIN|loghead-0162|compiled~%")

(cw "AUDIT-RESULT|loghead-0162|compiled|~x0~%" (audit-acl2-0162))

(cw "AUDIT-BEGIN|loghead-0162|direct~%")

(cw "AUDIT-RESULT|loghead-0162|direct|~x0~%" (loghead '0 '-65))

(defun audit-acl2-0163 () (loghead '0 '-64))

(verify-guards audit-acl2-0163)

(cw "AUDIT-BEGIN|loghead-0163|compiled~%")

(cw "AUDIT-RESULT|loghead-0163|compiled|~x0~%" (audit-acl2-0163))

(cw "AUDIT-BEGIN|loghead-0163|direct~%")

(cw "AUDIT-RESULT|loghead-0163|direct|~x0~%" (loghead '0 '-64))

(defun audit-acl2-0164 () (loghead '0 '-17))

(verify-guards audit-acl2-0164)

(cw "AUDIT-BEGIN|loghead-0164|compiled~%")

(cw "AUDIT-RESULT|loghead-0164|compiled|~x0~%" (audit-acl2-0164))

(cw "AUDIT-BEGIN|loghead-0164|direct~%")

(cw "AUDIT-RESULT|loghead-0164|direct|~x0~%" (loghead '0 '-17))

(defun audit-acl2-0165 () (loghead '0 '-1))

(verify-guards audit-acl2-0165)

(cw "AUDIT-BEGIN|loghead-0165|compiled~%")

(cw "AUDIT-RESULT|loghead-0165|compiled|~x0~%" (audit-acl2-0165))

(cw "AUDIT-BEGIN|loghead-0165|direct~%")

(cw "AUDIT-RESULT|loghead-0165|direct|~x0~%" (loghead '0 '-1))

(defun audit-acl2-0166 () (loghead '0 '0))

(verify-guards audit-acl2-0166)

(cw "AUDIT-BEGIN|loghead-0166|compiled~%")

(cw "AUDIT-RESULT|loghead-0166|compiled|~x0~%" (audit-acl2-0166))

(cw "AUDIT-BEGIN|loghead-0166|direct~%")

(cw "AUDIT-RESULT|loghead-0166|direct|~x0~%" (loghead '0 '0))

(defun audit-acl2-0167 () (loghead '0 '1))

(verify-guards audit-acl2-0167)

(cw "AUDIT-BEGIN|loghead-0167|compiled~%")

(cw "AUDIT-RESULT|loghead-0167|compiled|~x0~%" (audit-acl2-0167))

(cw "AUDIT-BEGIN|loghead-0167|direct~%")

(cw "AUDIT-RESULT|loghead-0167|direct|~x0~%" (loghead '0 '1))

(defun audit-acl2-0168 () (loghead '0 '17))

(verify-guards audit-acl2-0168)

(cw "AUDIT-BEGIN|loghead-0168|compiled~%")

(cw "AUDIT-RESULT|loghead-0168|compiled|~x0~%" (audit-acl2-0168))

(cw "AUDIT-BEGIN|loghead-0168|direct~%")

(cw "AUDIT-RESULT|loghead-0168|direct|~x0~%" (loghead '0 '17))

(defun audit-acl2-0169 () (loghead '0 '63))

(verify-guards audit-acl2-0169)

(cw "AUDIT-BEGIN|loghead-0169|compiled~%")

(cw "AUDIT-RESULT|loghead-0169|compiled|~x0~%" (audit-acl2-0169))

(cw "AUDIT-BEGIN|loghead-0169|direct~%")

(cw "AUDIT-RESULT|loghead-0169|direct|~x0~%" (loghead '0 '63))

(defun audit-acl2-0170 () (loghead '0 '64))

(verify-guards audit-acl2-0170)

(cw "AUDIT-BEGIN|loghead-0170|compiled~%")

(cw "AUDIT-RESULT|loghead-0170|compiled|~x0~%" (audit-acl2-0170))

(cw "AUDIT-BEGIN|loghead-0170|direct~%")

(cw "AUDIT-RESULT|loghead-0170|direct|~x0~%" (loghead '0 '64))

(defun audit-acl2-0171 () (loghead '1 '-65))

(verify-guards audit-acl2-0171)

(cw "AUDIT-BEGIN|loghead-0171|compiled~%")

(cw "AUDIT-RESULT|loghead-0171|compiled|~x0~%" (audit-acl2-0171))

(cw "AUDIT-BEGIN|loghead-0171|direct~%")

(cw "AUDIT-RESULT|loghead-0171|direct|~x0~%" (loghead '1 '-65))

(defun audit-acl2-0172 () (loghead '1 '-64))

(verify-guards audit-acl2-0172)

(cw "AUDIT-BEGIN|loghead-0172|compiled~%")

(cw "AUDIT-RESULT|loghead-0172|compiled|~x0~%" (audit-acl2-0172))

(cw "AUDIT-BEGIN|loghead-0172|direct~%")

(cw "AUDIT-RESULT|loghead-0172|direct|~x0~%" (loghead '1 '-64))

(defun audit-acl2-0173 () (loghead '1 '-17))

(verify-guards audit-acl2-0173)

(cw "AUDIT-BEGIN|loghead-0173|compiled~%")

(cw "AUDIT-RESULT|loghead-0173|compiled|~x0~%" (audit-acl2-0173))

(cw "AUDIT-BEGIN|loghead-0173|direct~%")

(cw "AUDIT-RESULT|loghead-0173|direct|~x0~%" (loghead '1 '-17))

(defun audit-acl2-0174 () (loghead '1 '-1))

(verify-guards audit-acl2-0174)

(cw "AUDIT-BEGIN|loghead-0174|compiled~%")

(cw "AUDIT-RESULT|loghead-0174|compiled|~x0~%" (audit-acl2-0174))

(cw "AUDIT-BEGIN|loghead-0174|direct~%")

(cw "AUDIT-RESULT|loghead-0174|direct|~x0~%" (loghead '1 '-1))

(defun audit-acl2-0175 () (loghead '1 '0))

(verify-guards audit-acl2-0175)

(cw "AUDIT-BEGIN|loghead-0175|compiled~%")

(cw "AUDIT-RESULT|loghead-0175|compiled|~x0~%" (audit-acl2-0175))

(cw "AUDIT-BEGIN|loghead-0175|direct~%")

(cw "AUDIT-RESULT|loghead-0175|direct|~x0~%" (loghead '1 '0))

(defun audit-acl2-0176 () (loghead '1 '1))

(verify-guards audit-acl2-0176)

(cw "AUDIT-BEGIN|loghead-0176|compiled~%")

(cw "AUDIT-RESULT|loghead-0176|compiled|~x0~%" (audit-acl2-0176))

(cw "AUDIT-BEGIN|loghead-0176|direct~%")

(cw "AUDIT-RESULT|loghead-0176|direct|~x0~%" (loghead '1 '1))

(defun audit-acl2-0177 () (loghead '1 '17))

(verify-guards audit-acl2-0177)

(cw "AUDIT-BEGIN|loghead-0177|compiled~%")

(cw "AUDIT-RESULT|loghead-0177|compiled|~x0~%" (audit-acl2-0177))

(cw "AUDIT-BEGIN|loghead-0177|direct~%")

(cw "AUDIT-RESULT|loghead-0177|direct|~x0~%" (loghead '1 '17))

(defun audit-acl2-0178 () (loghead '1 '63))

(verify-guards audit-acl2-0178)

(cw "AUDIT-BEGIN|loghead-0178|compiled~%")

(cw "AUDIT-RESULT|loghead-0178|compiled|~x0~%" (audit-acl2-0178))

(cw "AUDIT-BEGIN|loghead-0178|direct~%")

(cw "AUDIT-RESULT|loghead-0178|direct|~x0~%" (loghead '1 '63))

(defun audit-acl2-0179 () (loghead '1 '64))

(verify-guards audit-acl2-0179)

(cw "AUDIT-BEGIN|loghead-0179|compiled~%")

(cw "AUDIT-RESULT|loghead-0179|compiled|~x0~%" (audit-acl2-0179))

(cw "AUDIT-BEGIN|loghead-0179|direct~%")

(cw "AUDIT-RESULT|loghead-0179|direct|~x0~%" (loghead '1 '64))

(defun audit-acl2-0180 () (loghead '3 '-65))

(verify-guards audit-acl2-0180)

(cw "AUDIT-BEGIN|loghead-0180|compiled~%")

(cw "AUDIT-RESULT|loghead-0180|compiled|~x0~%" (audit-acl2-0180))

(cw "AUDIT-BEGIN|loghead-0180|direct~%")

(cw "AUDIT-RESULT|loghead-0180|direct|~x0~%" (loghead '3 '-65))

(defun audit-acl2-0181 () (loghead '3 '-64))

(verify-guards audit-acl2-0181)

(cw "AUDIT-BEGIN|loghead-0181|compiled~%")

(cw "AUDIT-RESULT|loghead-0181|compiled|~x0~%" (audit-acl2-0181))

(cw "AUDIT-BEGIN|loghead-0181|direct~%")

(cw "AUDIT-RESULT|loghead-0181|direct|~x0~%" (loghead '3 '-64))

(defun audit-acl2-0182 () (loghead '3 '-17))

(verify-guards audit-acl2-0182)

(cw "AUDIT-BEGIN|loghead-0182|compiled~%")

(cw "AUDIT-RESULT|loghead-0182|compiled|~x0~%" (audit-acl2-0182))

(cw "AUDIT-BEGIN|loghead-0182|direct~%")

(cw "AUDIT-RESULT|loghead-0182|direct|~x0~%" (loghead '3 '-17))

(defun audit-acl2-0183 () (loghead '3 '-1))

(verify-guards audit-acl2-0183)

(cw "AUDIT-BEGIN|loghead-0183|compiled~%")

(cw "AUDIT-RESULT|loghead-0183|compiled|~x0~%" (audit-acl2-0183))

(cw "AUDIT-BEGIN|loghead-0183|direct~%")

(cw "AUDIT-RESULT|loghead-0183|direct|~x0~%" (loghead '3 '-1))

(defun audit-acl2-0184 () (loghead '3 '0))

(verify-guards audit-acl2-0184)

(cw "AUDIT-BEGIN|loghead-0184|compiled~%")

(cw "AUDIT-RESULT|loghead-0184|compiled|~x0~%" (audit-acl2-0184))

(cw "AUDIT-BEGIN|loghead-0184|direct~%")

(cw "AUDIT-RESULT|loghead-0184|direct|~x0~%" (loghead '3 '0))

(defun audit-acl2-0185 () (loghead '3 '1))

(verify-guards audit-acl2-0185)

(cw "AUDIT-BEGIN|loghead-0185|compiled~%")

(cw "AUDIT-RESULT|loghead-0185|compiled|~x0~%" (audit-acl2-0185))

(cw "AUDIT-BEGIN|loghead-0185|direct~%")

(cw "AUDIT-RESULT|loghead-0185|direct|~x0~%" (loghead '3 '1))

(defun audit-acl2-0186 () (loghead '3 '17))

(verify-guards audit-acl2-0186)

(cw "AUDIT-BEGIN|loghead-0186|compiled~%")

(cw "AUDIT-RESULT|loghead-0186|compiled|~x0~%" (audit-acl2-0186))

(cw "AUDIT-BEGIN|loghead-0186|direct~%")

(cw "AUDIT-RESULT|loghead-0186|direct|~x0~%" (loghead '3 '17))

(defun audit-acl2-0187 () (loghead '3 '63))

(verify-guards audit-acl2-0187)

(cw "AUDIT-BEGIN|loghead-0187|compiled~%")

(cw "AUDIT-RESULT|loghead-0187|compiled|~x0~%" (audit-acl2-0187))

(cw "AUDIT-BEGIN|loghead-0187|direct~%")

(cw "AUDIT-RESULT|loghead-0187|direct|~x0~%" (loghead '3 '63))

(defun audit-acl2-0188 () (loghead '3 '64))

(verify-guards audit-acl2-0188)

(cw "AUDIT-BEGIN|loghead-0188|compiled~%")

(cw "AUDIT-RESULT|loghead-0188|compiled|~x0~%" (audit-acl2-0188))

(cw "AUDIT-BEGIN|loghead-0188|direct~%")

(cw "AUDIT-RESULT|loghead-0188|direct|~x0~%" (loghead '3 '64))

(defun audit-acl2-0189 () (loghead '6 '-65))

(verify-guards audit-acl2-0189)

(cw "AUDIT-BEGIN|loghead-0189|compiled~%")

(cw "AUDIT-RESULT|loghead-0189|compiled|~x0~%" (audit-acl2-0189))

(cw "AUDIT-BEGIN|loghead-0189|direct~%")

(cw "AUDIT-RESULT|loghead-0189|direct|~x0~%" (loghead '6 '-65))

(defun audit-acl2-0190 () (loghead '6 '-64))

(verify-guards audit-acl2-0190)

(cw "AUDIT-BEGIN|loghead-0190|compiled~%")

(cw "AUDIT-RESULT|loghead-0190|compiled|~x0~%" (audit-acl2-0190))

(cw "AUDIT-BEGIN|loghead-0190|direct~%")

(cw "AUDIT-RESULT|loghead-0190|direct|~x0~%" (loghead '6 '-64))

(defun audit-acl2-0191 () (loghead '6 '-17))

(verify-guards audit-acl2-0191)

(cw "AUDIT-BEGIN|loghead-0191|compiled~%")

(cw "AUDIT-RESULT|loghead-0191|compiled|~x0~%" (audit-acl2-0191))

(cw "AUDIT-BEGIN|loghead-0191|direct~%")

(cw "AUDIT-RESULT|loghead-0191|direct|~x0~%" (loghead '6 '-17))

(defun audit-acl2-0192 () (loghead '6 '-1))

(verify-guards audit-acl2-0192)

(cw "AUDIT-BEGIN|loghead-0192|compiled~%")

(cw "AUDIT-RESULT|loghead-0192|compiled|~x0~%" (audit-acl2-0192))

(cw "AUDIT-BEGIN|loghead-0192|direct~%")

(cw "AUDIT-RESULT|loghead-0192|direct|~x0~%" (loghead '6 '-1))

(defun audit-acl2-0193 () (loghead '6 '0))

(verify-guards audit-acl2-0193)

(cw "AUDIT-BEGIN|loghead-0193|compiled~%")

(cw "AUDIT-RESULT|loghead-0193|compiled|~x0~%" (audit-acl2-0193))

(cw "AUDIT-BEGIN|loghead-0193|direct~%")

(cw "AUDIT-RESULT|loghead-0193|direct|~x0~%" (loghead '6 '0))

(defun audit-acl2-0194 () (loghead '6 '1))

(verify-guards audit-acl2-0194)

(cw "AUDIT-BEGIN|loghead-0194|compiled~%")

(cw "AUDIT-RESULT|loghead-0194|compiled|~x0~%" (audit-acl2-0194))

(cw "AUDIT-BEGIN|loghead-0194|direct~%")

(cw "AUDIT-RESULT|loghead-0194|direct|~x0~%" (loghead '6 '1))

(defun audit-acl2-0195 () (loghead '6 '17))

(verify-guards audit-acl2-0195)

(cw "AUDIT-BEGIN|loghead-0195|compiled~%")

(cw "AUDIT-RESULT|loghead-0195|compiled|~x0~%" (audit-acl2-0195))

(cw "AUDIT-BEGIN|loghead-0195|direct~%")

(cw "AUDIT-RESULT|loghead-0195|direct|~x0~%" (loghead '6 '17))

(defun audit-acl2-0196 () (loghead '6 '63))

(verify-guards audit-acl2-0196)

(cw "AUDIT-BEGIN|loghead-0196|compiled~%")

(cw "AUDIT-RESULT|loghead-0196|compiled|~x0~%" (audit-acl2-0196))

(cw "AUDIT-BEGIN|loghead-0196|direct~%")

(cw "AUDIT-RESULT|loghead-0196|direct|~x0~%" (loghead '6 '63))

(defun audit-acl2-0197 () (loghead '6 '64))

(verify-guards audit-acl2-0197)

(cw "AUDIT-BEGIN|loghead-0197|compiled~%")

(cw "AUDIT-RESULT|loghead-0197|compiled|~x0~%" (audit-acl2-0197))

(cw "AUDIT-BEGIN|loghead-0197|direct~%")

(cw "AUDIT-RESULT|loghead-0197|direct|~x0~%" (loghead '6 '64))

(defun audit-acl2-0198 () (loghead '7 '-65))

(verify-guards audit-acl2-0198)

(cw "AUDIT-BEGIN|loghead-0198|compiled~%")

(cw "AUDIT-RESULT|loghead-0198|compiled|~x0~%" (audit-acl2-0198))

(cw "AUDIT-BEGIN|loghead-0198|direct~%")

(cw "AUDIT-RESULT|loghead-0198|direct|~x0~%" (loghead '7 '-65))

(defun audit-acl2-0199 () (loghead '7 '-64))

(verify-guards audit-acl2-0199)

(cw "AUDIT-BEGIN|loghead-0199|compiled~%")

(cw "AUDIT-RESULT|loghead-0199|compiled|~x0~%" (audit-acl2-0199))

(cw "AUDIT-BEGIN|loghead-0199|direct~%")

(cw "AUDIT-RESULT|loghead-0199|direct|~x0~%" (loghead '7 '-64))

(defun audit-acl2-0200 () (loghead '7 '-17))

(verify-guards audit-acl2-0200)

(cw "AUDIT-BEGIN|loghead-0200|compiled~%")

(cw "AUDIT-RESULT|loghead-0200|compiled|~x0~%" (audit-acl2-0200))

(cw "AUDIT-BEGIN|loghead-0200|direct~%")

(cw "AUDIT-RESULT|loghead-0200|direct|~x0~%" (loghead '7 '-17))

(defun audit-acl2-0201 () (loghead '7 '-1))

(verify-guards audit-acl2-0201)

(cw "AUDIT-BEGIN|loghead-0201|compiled~%")

(cw "AUDIT-RESULT|loghead-0201|compiled|~x0~%" (audit-acl2-0201))

(cw "AUDIT-BEGIN|loghead-0201|direct~%")

(cw "AUDIT-RESULT|loghead-0201|direct|~x0~%" (loghead '7 '-1))

(defun audit-acl2-0202 () (loghead '7 '0))

(verify-guards audit-acl2-0202)

(cw "AUDIT-BEGIN|loghead-0202|compiled~%")

(cw "AUDIT-RESULT|loghead-0202|compiled|~x0~%" (audit-acl2-0202))

(cw "AUDIT-BEGIN|loghead-0202|direct~%")

(cw "AUDIT-RESULT|loghead-0202|direct|~x0~%" (loghead '7 '0))

(defun audit-acl2-0203 () (loghead '7 '1))

(verify-guards audit-acl2-0203)

(cw "AUDIT-BEGIN|loghead-0203|compiled~%")

(cw "AUDIT-RESULT|loghead-0203|compiled|~x0~%" (audit-acl2-0203))

(cw "AUDIT-BEGIN|loghead-0203|direct~%")

(cw "AUDIT-RESULT|loghead-0203|direct|~x0~%" (loghead '7 '1))

(defun audit-acl2-0204 () (loghead '7 '17))

(verify-guards audit-acl2-0204)

(cw "AUDIT-BEGIN|loghead-0204|compiled~%")

(cw "AUDIT-RESULT|loghead-0204|compiled|~x0~%" (audit-acl2-0204))

(cw "AUDIT-BEGIN|loghead-0204|direct~%")

(cw "AUDIT-RESULT|loghead-0204|direct|~x0~%" (loghead '7 '17))

(defun audit-acl2-0205 () (loghead '7 '63))

(verify-guards audit-acl2-0205)

(cw "AUDIT-BEGIN|loghead-0205|compiled~%")

(cw "AUDIT-RESULT|loghead-0205|compiled|~x0~%" (audit-acl2-0205))

(cw "AUDIT-BEGIN|loghead-0205|direct~%")

(cw "AUDIT-RESULT|loghead-0205|direct|~x0~%" (loghead '7 '63))

(defun audit-acl2-0206 () (loghead '7 '64))

(verify-guards audit-acl2-0206)

(cw "AUDIT-BEGIN|loghead-0206|compiled~%")

(cw "AUDIT-RESULT|loghead-0206|compiled|~x0~%" (audit-acl2-0206))

(cw "AUDIT-BEGIN|loghead-0206|direct~%")

(cw "AUDIT-RESULT|loghead-0206|direct|~x0~%" (loghead '7 '64))

(defun audit-acl2-0207 () (loghead '64 '-65))

(verify-guards audit-acl2-0207)

(cw "AUDIT-BEGIN|loghead-0207|compiled~%")

(cw "AUDIT-RESULT|loghead-0207|compiled|~x0~%" (audit-acl2-0207))

(cw "AUDIT-BEGIN|loghead-0207|direct~%")

(cw "AUDIT-RESULT|loghead-0207|direct|~x0~%" (loghead '64 '-65))

(defun audit-acl2-0208 () (loghead '64 '-64))

(verify-guards audit-acl2-0208)

(cw "AUDIT-BEGIN|loghead-0208|compiled~%")

(cw "AUDIT-RESULT|loghead-0208|compiled|~x0~%" (audit-acl2-0208))

(cw "AUDIT-BEGIN|loghead-0208|direct~%")

(cw "AUDIT-RESULT|loghead-0208|direct|~x0~%" (loghead '64 '-64))

(defun audit-acl2-0209 () (loghead '64 '-17))

(verify-guards audit-acl2-0209)

(cw "AUDIT-BEGIN|loghead-0209|compiled~%")

(cw "AUDIT-RESULT|loghead-0209|compiled|~x0~%" (audit-acl2-0209))

(cw "AUDIT-BEGIN|loghead-0209|direct~%")

(cw "AUDIT-RESULT|loghead-0209|direct|~x0~%" (loghead '64 '-17))

(defun audit-acl2-0210 () (loghead '64 '-1))

(verify-guards audit-acl2-0210)

(cw "AUDIT-BEGIN|loghead-0210|compiled~%")

(cw "AUDIT-RESULT|loghead-0210|compiled|~x0~%" (audit-acl2-0210))

(cw "AUDIT-BEGIN|loghead-0210|direct~%")

(cw "AUDIT-RESULT|loghead-0210|direct|~x0~%" (loghead '64 '-1))

(defun audit-acl2-0211 () (loghead '64 '0))

(verify-guards audit-acl2-0211)

(cw "AUDIT-BEGIN|loghead-0211|compiled~%")

(cw "AUDIT-RESULT|loghead-0211|compiled|~x0~%" (audit-acl2-0211))

(cw "AUDIT-BEGIN|loghead-0211|direct~%")

(cw "AUDIT-RESULT|loghead-0211|direct|~x0~%" (loghead '64 '0))

(defun audit-acl2-0212 () (loghead '64 '1))

(verify-guards audit-acl2-0212)

(cw "AUDIT-BEGIN|loghead-0212|compiled~%")

(cw "AUDIT-RESULT|loghead-0212|compiled|~x0~%" (audit-acl2-0212))

(cw "AUDIT-BEGIN|loghead-0212|direct~%")

(cw "AUDIT-RESULT|loghead-0212|direct|~x0~%" (loghead '64 '1))

(defun audit-acl2-0213 () (loghead '64 '17))

(verify-guards audit-acl2-0213)

(cw "AUDIT-BEGIN|loghead-0213|compiled~%")

(cw "AUDIT-RESULT|loghead-0213|compiled|~x0~%" (audit-acl2-0213))

(cw "AUDIT-BEGIN|loghead-0213|direct~%")

(cw "AUDIT-RESULT|loghead-0213|direct|~x0~%" (loghead '64 '17))

(defun audit-acl2-0214 () (loghead '64 '63))

(verify-guards audit-acl2-0214)

(cw "AUDIT-BEGIN|loghead-0214|compiled~%")

(cw "AUDIT-RESULT|loghead-0214|compiled|~x0~%" (audit-acl2-0214))

(cw "AUDIT-BEGIN|loghead-0214|direct~%")

(cw "AUDIT-RESULT|loghead-0214|direct|~x0~%" (loghead '64 '63))

(defun audit-acl2-0215 () (loghead '64 '64))

(verify-guards audit-acl2-0215)

(cw "AUDIT-BEGIN|loghead-0215|compiled~%")

(cw "AUDIT-RESULT|loghead-0215|compiled|~x0~%" (audit-acl2-0215))

(cw "AUDIT-BEGIN|loghead-0215|direct~%")

(cw "AUDIT-RESULT|loghead-0215|direct|~x0~%" (loghead '64 '64))

(defun audit-acl2-0216 () (with-guard-checking NIL (ec-call (loghead '-1 '17))))

(verify-guards audit-acl2-0216)

(cw "AUDIT-BEGIN|loghead-0216|compiled~%")

(cw "AUDIT-RESULT|loghead-0216|compiled|~x0~%" (audit-acl2-0216))

(cw "AUDIT-BEGIN|loghead-0216|direct~%")

(cw "AUDIT-RESULT|loghead-0216|direct|~x0~%" (with-guard-checking NIL (ec-call (loghead '-1 '17))))

(defun audit-acl2-0217 () (with-guard-checking NIL (ec-call (loghead '1/2 '17))))

(verify-guards audit-acl2-0217)

(cw "AUDIT-BEGIN|loghead-0217|compiled~%")

(cw "AUDIT-RESULT|loghead-0217|compiled|~x0~%" (audit-acl2-0217))

(cw "AUDIT-BEGIN|loghead-0217|direct~%")

(cw "AUDIT-RESULT|loghead-0217|direct|~x0~%" (with-guard-checking NIL (ec-call (loghead '1/2 '17))))

(defun audit-acl2-0218 () (with-guard-checking NIL (ec-call (loghead '2 'A))))

(verify-guards audit-acl2-0218)

(cw "AUDIT-BEGIN|loghead-0218|compiled~%")

(cw "AUDIT-RESULT|loghead-0218|compiled|~x0~%" (audit-acl2-0218))

(cw "AUDIT-BEGIN|loghead-0218|direct~%")

(cw "AUDIT-RESULT|loghead-0218|direct|~x0~%" (with-guard-checking NIL (ec-call (loghead '2 'A))))

(defun audit-acl2-0219 () (logtail '0 '-65))

(verify-guards audit-acl2-0219)

(cw "AUDIT-BEGIN|logtail-0219|compiled~%")

(cw "AUDIT-RESULT|logtail-0219|compiled|~x0~%" (audit-acl2-0219))

(cw "AUDIT-BEGIN|logtail-0219|direct~%")

(cw "AUDIT-RESULT|logtail-0219|direct|~x0~%" (logtail '0 '-65))

(defun audit-acl2-0220 () (logtail '0 '-64))

(verify-guards audit-acl2-0220)

(cw "AUDIT-BEGIN|logtail-0220|compiled~%")

(cw "AUDIT-RESULT|logtail-0220|compiled|~x0~%" (audit-acl2-0220))

(cw "AUDIT-BEGIN|logtail-0220|direct~%")

(cw "AUDIT-RESULT|logtail-0220|direct|~x0~%" (logtail '0 '-64))

(defun audit-acl2-0221 () (logtail '0 '-17))

(verify-guards audit-acl2-0221)

(cw "AUDIT-BEGIN|logtail-0221|compiled~%")

(cw "AUDIT-RESULT|logtail-0221|compiled|~x0~%" (audit-acl2-0221))

(cw "AUDIT-BEGIN|logtail-0221|direct~%")

(cw "AUDIT-RESULT|logtail-0221|direct|~x0~%" (logtail '0 '-17))

(defun audit-acl2-0222 () (logtail '0 '-1))

(verify-guards audit-acl2-0222)

(cw "AUDIT-BEGIN|logtail-0222|compiled~%")

(cw "AUDIT-RESULT|logtail-0222|compiled|~x0~%" (audit-acl2-0222))

(cw "AUDIT-BEGIN|logtail-0222|direct~%")

(cw "AUDIT-RESULT|logtail-0222|direct|~x0~%" (logtail '0 '-1))

(defun audit-acl2-0223 () (logtail '0 '0))

(verify-guards audit-acl2-0223)

(cw "AUDIT-BEGIN|logtail-0223|compiled~%")

(cw "AUDIT-RESULT|logtail-0223|compiled|~x0~%" (audit-acl2-0223))

(cw "AUDIT-BEGIN|logtail-0223|direct~%")

(cw "AUDIT-RESULT|logtail-0223|direct|~x0~%" (logtail '0 '0))

(defun audit-acl2-0224 () (logtail '0 '1))

(verify-guards audit-acl2-0224)

(cw "AUDIT-BEGIN|logtail-0224|compiled~%")

(cw "AUDIT-RESULT|logtail-0224|compiled|~x0~%" (audit-acl2-0224))

(cw "AUDIT-BEGIN|logtail-0224|direct~%")

(cw "AUDIT-RESULT|logtail-0224|direct|~x0~%" (logtail '0 '1))

(defun audit-acl2-0225 () (logtail '0 '17))

(verify-guards audit-acl2-0225)

(cw "AUDIT-BEGIN|logtail-0225|compiled~%")

(cw "AUDIT-RESULT|logtail-0225|compiled|~x0~%" (audit-acl2-0225))

(cw "AUDIT-BEGIN|logtail-0225|direct~%")

(cw "AUDIT-RESULT|logtail-0225|direct|~x0~%" (logtail '0 '17))

(defun audit-acl2-0226 () (logtail '0 '63))

(verify-guards audit-acl2-0226)

(cw "AUDIT-BEGIN|logtail-0226|compiled~%")

(cw "AUDIT-RESULT|logtail-0226|compiled|~x0~%" (audit-acl2-0226))

(cw "AUDIT-BEGIN|logtail-0226|direct~%")

(cw "AUDIT-RESULT|logtail-0226|direct|~x0~%" (logtail '0 '63))

(defun audit-acl2-0227 () (logtail '0 '64))

(verify-guards audit-acl2-0227)

(cw "AUDIT-BEGIN|logtail-0227|compiled~%")

(cw "AUDIT-RESULT|logtail-0227|compiled|~x0~%" (audit-acl2-0227))

(cw "AUDIT-BEGIN|logtail-0227|direct~%")

(cw "AUDIT-RESULT|logtail-0227|direct|~x0~%" (logtail '0 '64))

(defun audit-acl2-0228 () (logtail '1 '-65))

(verify-guards audit-acl2-0228)

(cw "AUDIT-BEGIN|logtail-0228|compiled~%")

(cw "AUDIT-RESULT|logtail-0228|compiled|~x0~%" (audit-acl2-0228))

(cw "AUDIT-BEGIN|logtail-0228|direct~%")

(cw "AUDIT-RESULT|logtail-0228|direct|~x0~%" (logtail '1 '-65))

(defun audit-acl2-0229 () (logtail '1 '-64))

(verify-guards audit-acl2-0229)

(cw "AUDIT-BEGIN|logtail-0229|compiled~%")

(cw "AUDIT-RESULT|logtail-0229|compiled|~x0~%" (audit-acl2-0229))

(cw "AUDIT-BEGIN|logtail-0229|direct~%")

(cw "AUDIT-RESULT|logtail-0229|direct|~x0~%" (logtail '1 '-64))

(defun audit-acl2-0230 () (logtail '1 '-17))

(verify-guards audit-acl2-0230)

(cw "AUDIT-BEGIN|logtail-0230|compiled~%")

(cw "AUDIT-RESULT|logtail-0230|compiled|~x0~%" (audit-acl2-0230))

(cw "AUDIT-BEGIN|logtail-0230|direct~%")

(cw "AUDIT-RESULT|logtail-0230|direct|~x0~%" (logtail '1 '-17))

(defun audit-acl2-0231 () (logtail '1 '-1))

(verify-guards audit-acl2-0231)

(cw "AUDIT-BEGIN|logtail-0231|compiled~%")

(cw "AUDIT-RESULT|logtail-0231|compiled|~x0~%" (audit-acl2-0231))

(cw "AUDIT-BEGIN|logtail-0231|direct~%")

(cw "AUDIT-RESULT|logtail-0231|direct|~x0~%" (logtail '1 '-1))

(defun audit-acl2-0232 () (logtail '1 '0))

(verify-guards audit-acl2-0232)

(cw "AUDIT-BEGIN|logtail-0232|compiled~%")

(cw "AUDIT-RESULT|logtail-0232|compiled|~x0~%" (audit-acl2-0232))

(cw "AUDIT-BEGIN|logtail-0232|direct~%")

(cw "AUDIT-RESULT|logtail-0232|direct|~x0~%" (logtail '1 '0))

(defun audit-acl2-0233 () (logtail '1 '1))

(verify-guards audit-acl2-0233)

(cw "AUDIT-BEGIN|logtail-0233|compiled~%")

(cw "AUDIT-RESULT|logtail-0233|compiled|~x0~%" (audit-acl2-0233))

(cw "AUDIT-BEGIN|logtail-0233|direct~%")

(cw "AUDIT-RESULT|logtail-0233|direct|~x0~%" (logtail '1 '1))

(defun audit-acl2-0234 () (logtail '1 '17))

(verify-guards audit-acl2-0234)

(cw "AUDIT-BEGIN|logtail-0234|compiled~%")

(cw "AUDIT-RESULT|logtail-0234|compiled|~x0~%" (audit-acl2-0234))

(cw "AUDIT-BEGIN|logtail-0234|direct~%")

(cw "AUDIT-RESULT|logtail-0234|direct|~x0~%" (logtail '1 '17))

(defun audit-acl2-0235 () (logtail '1 '63))

(verify-guards audit-acl2-0235)

(cw "AUDIT-BEGIN|logtail-0235|compiled~%")

(cw "AUDIT-RESULT|logtail-0235|compiled|~x0~%" (audit-acl2-0235))

(cw "AUDIT-BEGIN|logtail-0235|direct~%")

(cw "AUDIT-RESULT|logtail-0235|direct|~x0~%" (logtail '1 '63))

(defun audit-acl2-0236 () (logtail '1 '64))

(verify-guards audit-acl2-0236)

(cw "AUDIT-BEGIN|logtail-0236|compiled~%")

(cw "AUDIT-RESULT|logtail-0236|compiled|~x0~%" (audit-acl2-0236))

(cw "AUDIT-BEGIN|logtail-0236|direct~%")

(cw "AUDIT-RESULT|logtail-0236|direct|~x0~%" (logtail '1 '64))

(defun audit-acl2-0237 () (logtail '3 '-65))

(verify-guards audit-acl2-0237)

(cw "AUDIT-BEGIN|logtail-0237|compiled~%")

(cw "AUDIT-RESULT|logtail-0237|compiled|~x0~%" (audit-acl2-0237))

(cw "AUDIT-BEGIN|logtail-0237|direct~%")

(cw "AUDIT-RESULT|logtail-0237|direct|~x0~%" (logtail '3 '-65))

(defun audit-acl2-0238 () (logtail '3 '-64))

(verify-guards audit-acl2-0238)

(cw "AUDIT-BEGIN|logtail-0238|compiled~%")

(cw "AUDIT-RESULT|logtail-0238|compiled|~x0~%" (audit-acl2-0238))

(cw "AUDIT-BEGIN|logtail-0238|direct~%")

(cw "AUDIT-RESULT|logtail-0238|direct|~x0~%" (logtail '3 '-64))

(defun audit-acl2-0239 () (logtail '3 '-17))

(verify-guards audit-acl2-0239)

(cw "AUDIT-BEGIN|logtail-0239|compiled~%")

(cw "AUDIT-RESULT|logtail-0239|compiled|~x0~%" (audit-acl2-0239))

(cw "AUDIT-BEGIN|logtail-0239|direct~%")

(cw "AUDIT-RESULT|logtail-0239|direct|~x0~%" (logtail '3 '-17))

(defun audit-acl2-0240 () (logtail '3 '-1))

(verify-guards audit-acl2-0240)

(cw "AUDIT-BEGIN|logtail-0240|compiled~%")

(cw "AUDIT-RESULT|logtail-0240|compiled|~x0~%" (audit-acl2-0240))

(cw "AUDIT-BEGIN|logtail-0240|direct~%")

(cw "AUDIT-RESULT|logtail-0240|direct|~x0~%" (logtail '3 '-1))

(defun audit-acl2-0241 () (logtail '3 '0))

(verify-guards audit-acl2-0241)

(cw "AUDIT-BEGIN|logtail-0241|compiled~%")

(cw "AUDIT-RESULT|logtail-0241|compiled|~x0~%" (audit-acl2-0241))

(cw "AUDIT-BEGIN|logtail-0241|direct~%")

(cw "AUDIT-RESULT|logtail-0241|direct|~x0~%" (logtail '3 '0))

(defun audit-acl2-0242 () (logtail '3 '1))

(verify-guards audit-acl2-0242)

(cw "AUDIT-BEGIN|logtail-0242|compiled~%")

(cw "AUDIT-RESULT|logtail-0242|compiled|~x0~%" (audit-acl2-0242))

(cw "AUDIT-BEGIN|logtail-0242|direct~%")

(cw "AUDIT-RESULT|logtail-0242|direct|~x0~%" (logtail '3 '1))

(defun audit-acl2-0243 () (logtail '3 '17))

(verify-guards audit-acl2-0243)

(cw "AUDIT-BEGIN|logtail-0243|compiled~%")

(cw "AUDIT-RESULT|logtail-0243|compiled|~x0~%" (audit-acl2-0243))

(cw "AUDIT-BEGIN|logtail-0243|direct~%")

(cw "AUDIT-RESULT|logtail-0243|direct|~x0~%" (logtail '3 '17))

(defun audit-acl2-0244 () (logtail '3 '63))

(verify-guards audit-acl2-0244)

(cw "AUDIT-BEGIN|logtail-0244|compiled~%")

(cw "AUDIT-RESULT|logtail-0244|compiled|~x0~%" (audit-acl2-0244))

(cw "AUDIT-BEGIN|logtail-0244|direct~%")

(cw "AUDIT-RESULT|logtail-0244|direct|~x0~%" (logtail '3 '63))

(defun audit-acl2-0245 () (logtail '3 '64))

(verify-guards audit-acl2-0245)

(cw "AUDIT-BEGIN|logtail-0245|compiled~%")

(cw "AUDIT-RESULT|logtail-0245|compiled|~x0~%" (audit-acl2-0245))

(cw "AUDIT-BEGIN|logtail-0245|direct~%")

(cw "AUDIT-RESULT|logtail-0245|direct|~x0~%" (logtail '3 '64))

(defun audit-acl2-0246 () (logtail '6 '-65))

(verify-guards audit-acl2-0246)

(cw "AUDIT-BEGIN|logtail-0246|compiled~%")

(cw "AUDIT-RESULT|logtail-0246|compiled|~x0~%" (audit-acl2-0246))

(cw "AUDIT-BEGIN|logtail-0246|direct~%")

(cw "AUDIT-RESULT|logtail-0246|direct|~x0~%" (logtail '6 '-65))

(defun audit-acl2-0247 () (logtail '6 '-64))

(verify-guards audit-acl2-0247)

(cw "AUDIT-BEGIN|logtail-0247|compiled~%")

(cw "AUDIT-RESULT|logtail-0247|compiled|~x0~%" (audit-acl2-0247))

(cw "AUDIT-BEGIN|logtail-0247|direct~%")

(cw "AUDIT-RESULT|logtail-0247|direct|~x0~%" (logtail '6 '-64))

(defun audit-acl2-0248 () (logtail '6 '-17))

(verify-guards audit-acl2-0248)

(cw "AUDIT-BEGIN|logtail-0248|compiled~%")

(cw "AUDIT-RESULT|logtail-0248|compiled|~x0~%" (audit-acl2-0248))

(cw "AUDIT-BEGIN|logtail-0248|direct~%")

(cw "AUDIT-RESULT|logtail-0248|direct|~x0~%" (logtail '6 '-17))

(defun audit-acl2-0249 () (logtail '6 '-1))

(verify-guards audit-acl2-0249)

(cw "AUDIT-BEGIN|logtail-0249|compiled~%")

(cw "AUDIT-RESULT|logtail-0249|compiled|~x0~%" (audit-acl2-0249))

(cw "AUDIT-BEGIN|logtail-0249|direct~%")

(cw "AUDIT-RESULT|logtail-0249|direct|~x0~%" (logtail '6 '-1))

(defun audit-acl2-0250 () (logtail '6 '0))

(verify-guards audit-acl2-0250)

(cw "AUDIT-BEGIN|logtail-0250|compiled~%")

(cw "AUDIT-RESULT|logtail-0250|compiled|~x0~%" (audit-acl2-0250))

(cw "AUDIT-BEGIN|logtail-0250|direct~%")

(cw "AUDIT-RESULT|logtail-0250|direct|~x0~%" (logtail '6 '0))

(defun audit-acl2-0251 () (logtail '6 '1))

(verify-guards audit-acl2-0251)

(cw "AUDIT-BEGIN|logtail-0251|compiled~%")

(cw "AUDIT-RESULT|logtail-0251|compiled|~x0~%" (audit-acl2-0251))

(cw "AUDIT-BEGIN|logtail-0251|direct~%")

(cw "AUDIT-RESULT|logtail-0251|direct|~x0~%" (logtail '6 '1))

(defun audit-acl2-0252 () (logtail '6 '17))

(verify-guards audit-acl2-0252)

(cw "AUDIT-BEGIN|logtail-0252|compiled~%")

(cw "AUDIT-RESULT|logtail-0252|compiled|~x0~%" (audit-acl2-0252))

(cw "AUDIT-BEGIN|logtail-0252|direct~%")

(cw "AUDIT-RESULT|logtail-0252|direct|~x0~%" (logtail '6 '17))

(defun audit-acl2-0253 () (logtail '6 '63))

(verify-guards audit-acl2-0253)

(cw "AUDIT-BEGIN|logtail-0253|compiled~%")

(cw "AUDIT-RESULT|logtail-0253|compiled|~x0~%" (audit-acl2-0253))

(cw "AUDIT-BEGIN|logtail-0253|direct~%")

(cw "AUDIT-RESULT|logtail-0253|direct|~x0~%" (logtail '6 '63))

(defun audit-acl2-0254 () (logtail '6 '64))

(verify-guards audit-acl2-0254)

(cw "AUDIT-BEGIN|logtail-0254|compiled~%")

(cw "AUDIT-RESULT|logtail-0254|compiled|~x0~%" (audit-acl2-0254))

(cw "AUDIT-BEGIN|logtail-0254|direct~%")

(cw "AUDIT-RESULT|logtail-0254|direct|~x0~%" (logtail '6 '64))

(defun audit-acl2-0255 () (logtail '7 '-65))

(verify-guards audit-acl2-0255)

(cw "AUDIT-BEGIN|logtail-0255|compiled~%")

(cw "AUDIT-RESULT|logtail-0255|compiled|~x0~%" (audit-acl2-0255))

(cw "AUDIT-BEGIN|logtail-0255|direct~%")

(cw "AUDIT-RESULT|logtail-0255|direct|~x0~%" (logtail '7 '-65))

(defun audit-acl2-0256 () (logtail '7 '-64))

(verify-guards audit-acl2-0256)

(cw "AUDIT-BEGIN|logtail-0256|compiled~%")

(cw "AUDIT-RESULT|logtail-0256|compiled|~x0~%" (audit-acl2-0256))

(cw "AUDIT-BEGIN|logtail-0256|direct~%")

(cw "AUDIT-RESULT|logtail-0256|direct|~x0~%" (logtail '7 '-64))

(defun audit-acl2-0257 () (logtail '7 '-17))

(verify-guards audit-acl2-0257)

(cw "AUDIT-BEGIN|logtail-0257|compiled~%")

(cw "AUDIT-RESULT|logtail-0257|compiled|~x0~%" (audit-acl2-0257))

(cw "AUDIT-BEGIN|logtail-0257|direct~%")

(cw "AUDIT-RESULT|logtail-0257|direct|~x0~%" (logtail '7 '-17))

(defun audit-acl2-0258 () (logtail '7 '-1))

(verify-guards audit-acl2-0258)

(cw "AUDIT-BEGIN|logtail-0258|compiled~%")

(cw "AUDIT-RESULT|logtail-0258|compiled|~x0~%" (audit-acl2-0258))

(cw "AUDIT-BEGIN|logtail-0258|direct~%")

(cw "AUDIT-RESULT|logtail-0258|direct|~x0~%" (logtail '7 '-1))

(defun audit-acl2-0259 () (logtail '7 '0))

(verify-guards audit-acl2-0259)

(cw "AUDIT-BEGIN|logtail-0259|compiled~%")

(cw "AUDIT-RESULT|logtail-0259|compiled|~x0~%" (audit-acl2-0259))

(cw "AUDIT-BEGIN|logtail-0259|direct~%")

(cw "AUDIT-RESULT|logtail-0259|direct|~x0~%" (logtail '7 '0))

(defun audit-acl2-0260 () (logtail '7 '1))

(verify-guards audit-acl2-0260)

(cw "AUDIT-BEGIN|logtail-0260|compiled~%")

(cw "AUDIT-RESULT|logtail-0260|compiled|~x0~%" (audit-acl2-0260))

(cw "AUDIT-BEGIN|logtail-0260|direct~%")

(cw "AUDIT-RESULT|logtail-0260|direct|~x0~%" (logtail '7 '1))

(defun audit-acl2-0261 () (logtail '7 '17))

(verify-guards audit-acl2-0261)

(cw "AUDIT-BEGIN|logtail-0261|compiled~%")

(cw "AUDIT-RESULT|logtail-0261|compiled|~x0~%" (audit-acl2-0261))

(cw "AUDIT-BEGIN|logtail-0261|direct~%")

(cw "AUDIT-RESULT|logtail-0261|direct|~x0~%" (logtail '7 '17))

(defun audit-acl2-0262 () (logtail '7 '63))

(verify-guards audit-acl2-0262)

(cw "AUDIT-BEGIN|logtail-0262|compiled~%")

(cw "AUDIT-RESULT|logtail-0262|compiled|~x0~%" (audit-acl2-0262))

(cw "AUDIT-BEGIN|logtail-0262|direct~%")

(cw "AUDIT-RESULT|logtail-0262|direct|~x0~%" (logtail '7 '63))

(defun audit-acl2-0263 () (logtail '7 '64))

(verify-guards audit-acl2-0263)

(cw "AUDIT-BEGIN|logtail-0263|compiled~%")

(cw "AUDIT-RESULT|logtail-0263|compiled|~x0~%" (audit-acl2-0263))

(cw "AUDIT-BEGIN|logtail-0263|direct~%")

(cw "AUDIT-RESULT|logtail-0263|direct|~x0~%" (logtail '7 '64))

(defun audit-acl2-0264 () (logtail '64 '-65))

(verify-guards audit-acl2-0264)

(cw "AUDIT-BEGIN|logtail-0264|compiled~%")

(cw "AUDIT-RESULT|logtail-0264|compiled|~x0~%" (audit-acl2-0264))

(cw "AUDIT-BEGIN|logtail-0264|direct~%")

(cw "AUDIT-RESULT|logtail-0264|direct|~x0~%" (logtail '64 '-65))

(defun audit-acl2-0265 () (logtail '64 '-64))

(verify-guards audit-acl2-0265)

(cw "AUDIT-BEGIN|logtail-0265|compiled~%")

(cw "AUDIT-RESULT|logtail-0265|compiled|~x0~%" (audit-acl2-0265))

(cw "AUDIT-BEGIN|logtail-0265|direct~%")

(cw "AUDIT-RESULT|logtail-0265|direct|~x0~%" (logtail '64 '-64))

(defun audit-acl2-0266 () (logtail '64 '-17))

(verify-guards audit-acl2-0266)

(cw "AUDIT-BEGIN|logtail-0266|compiled~%")

(cw "AUDIT-RESULT|logtail-0266|compiled|~x0~%" (audit-acl2-0266))

(cw "AUDIT-BEGIN|logtail-0266|direct~%")

(cw "AUDIT-RESULT|logtail-0266|direct|~x0~%" (logtail '64 '-17))

(defun audit-acl2-0267 () (logtail '64 '-1))

(verify-guards audit-acl2-0267)

(cw "AUDIT-BEGIN|logtail-0267|compiled~%")

(cw "AUDIT-RESULT|logtail-0267|compiled|~x0~%" (audit-acl2-0267))

(cw "AUDIT-BEGIN|logtail-0267|direct~%")

(cw "AUDIT-RESULT|logtail-0267|direct|~x0~%" (logtail '64 '-1))

(defun audit-acl2-0268 () (logtail '64 '0))

(verify-guards audit-acl2-0268)

(cw "AUDIT-BEGIN|logtail-0268|compiled~%")

(cw "AUDIT-RESULT|logtail-0268|compiled|~x0~%" (audit-acl2-0268))

(cw "AUDIT-BEGIN|logtail-0268|direct~%")

(cw "AUDIT-RESULT|logtail-0268|direct|~x0~%" (logtail '64 '0))

(defun audit-acl2-0269 () (logtail '64 '1))

(verify-guards audit-acl2-0269)

(cw "AUDIT-BEGIN|logtail-0269|compiled~%")

(cw "AUDIT-RESULT|logtail-0269|compiled|~x0~%" (audit-acl2-0269))

(cw "AUDIT-BEGIN|logtail-0269|direct~%")

(cw "AUDIT-RESULT|logtail-0269|direct|~x0~%" (logtail '64 '1))

(defun audit-acl2-0270 () (logtail '64 '17))

(verify-guards audit-acl2-0270)

(cw "AUDIT-BEGIN|logtail-0270|compiled~%")

(cw "AUDIT-RESULT|logtail-0270|compiled|~x0~%" (audit-acl2-0270))

(cw "AUDIT-BEGIN|logtail-0270|direct~%")

(cw "AUDIT-RESULT|logtail-0270|direct|~x0~%" (logtail '64 '17))

(defun audit-acl2-0271 () (logtail '64 '63))

(verify-guards audit-acl2-0271)

(cw "AUDIT-BEGIN|logtail-0271|compiled~%")

(cw "AUDIT-RESULT|logtail-0271|compiled|~x0~%" (audit-acl2-0271))

(cw "AUDIT-BEGIN|logtail-0271|direct~%")

(cw "AUDIT-RESULT|logtail-0271|direct|~x0~%" (logtail '64 '63))

(defun audit-acl2-0272 () (logtail '64 '64))

(verify-guards audit-acl2-0272)

(cw "AUDIT-BEGIN|logtail-0272|compiled~%")

(cw "AUDIT-RESULT|logtail-0272|compiled|~x0~%" (audit-acl2-0272))

(cw "AUDIT-BEGIN|logtail-0272|direct~%")

(cw "AUDIT-RESULT|logtail-0272|direct|~x0~%" (logtail '64 '64))

(defun audit-acl2-0273 () (with-guard-checking NIL (ec-call (logtail '-1 '17))))

(verify-guards audit-acl2-0273)

(cw "AUDIT-BEGIN|logtail-0273|compiled~%")

(cw "AUDIT-RESULT|logtail-0273|compiled|~x0~%" (audit-acl2-0273))

(cw "AUDIT-BEGIN|logtail-0273|direct~%")

(cw "AUDIT-RESULT|logtail-0273|direct|~x0~%" (with-guard-checking NIL (ec-call (logtail '-1 '17))))

(defun audit-acl2-0274 () (with-guard-checking NIL (ec-call (logtail '1/2 '17))))

(verify-guards audit-acl2-0274)

(cw "AUDIT-BEGIN|logtail-0274|compiled~%")

(cw "AUDIT-RESULT|logtail-0274|compiled|~x0~%" (audit-acl2-0274))

(cw "AUDIT-BEGIN|logtail-0274|direct~%")

(cw "AUDIT-RESULT|logtail-0274|direct|~x0~%" (with-guard-checking NIL (ec-call (logtail '1/2 '17))))

(defun audit-acl2-0275 () (with-guard-checking NIL (ec-call (logtail '2 'A))))

(verify-guards audit-acl2-0275)

(cw "AUDIT-BEGIN|logtail-0275|compiled~%")

(cw "AUDIT-RESULT|logtail-0275|compiled|~x0~%" (audit-acl2-0275))

(cw "AUDIT-BEGIN|logtail-0275|direct~%")

(cw "AUDIT-RESULT|logtail-0275|direct|~x0~%" (with-guard-checking NIL (ec-call (logtail '2 'A))))

(defun audit-acl2-0276 () (< '-1 '0))

(verify-guards audit-acl2-0276)

(cw "AUDIT-BEGIN|lexicographic-<-0276|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0276|compiled|~x0~%" (audit-acl2-0276))

(cw "AUDIT-BEGIN|lexicographic-<-0276|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0276|direct|~x0~%" (< '-1 '0))

(defun audit-acl2-0277 () (< '0 '1/2))

(verify-guards audit-acl2-0277)

(cw "AUDIT-BEGIN|lexicographic-<-0277|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0277|compiled|~x0~%" (audit-acl2-0277))

(cw "AUDIT-BEGIN|lexicographic-<-0277|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0277|direct|~x0~%" (< '0 '1/2))

(defun audit-acl2-0278 () (< '1/2 '2))

(verify-guards audit-acl2-0278)

(cw "AUDIT-BEGIN|lexicographic-<-0278|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0278|compiled|~x0~%" (audit-acl2-0278))

(cw "AUDIT-BEGIN|lexicographic-<-0278|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0278|direct|~x0~%" (< '1/2 '2))

(defun audit-acl2-0279 () (with-guard-checking NIL (ec-call (< '2 '#C(-1 1)))))

(verify-guards audit-acl2-0279)

(cw "AUDIT-BEGIN|lexicographic-<-0279|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0279|compiled|~x0~%" (audit-acl2-0279))

(cw "AUDIT-BEGIN|lexicographic-<-0279|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0279|direct|~x0~%" (with-guard-checking NIL (ec-call (< '2 '#C(-1 1)))))

(defun audit-acl2-0280 () (with-guard-checking NIL (ec-call (< '#C(-1 1) '#C(0 -1)))))

(verify-guards audit-acl2-0280)

(cw "AUDIT-BEGIN|lexicographic-<-0280|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0280|compiled|~x0~%" (audit-acl2-0280))

(cw "AUDIT-BEGIN|lexicographic-<-0280|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0280|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(-1 1) '#C(0 -1)))))

(defun audit-acl2-0281 () (with-guard-checking NIL (ec-call (< '#C(0 -1) '#C(0 1)))))

(verify-guards audit-acl2-0281)

(cw "AUDIT-BEGIN|lexicographic-<-0281|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0281|compiled|~x0~%" (audit-acl2-0281))

(cw "AUDIT-BEGIN|lexicographic-<-0281|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0281|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(0 -1) '#C(0 1)))))

(defun audit-acl2-0282 () (with-guard-checking NIL (ec-call (< '#C(0 1) '#C(1/2 -2)))))

(verify-guards audit-acl2-0282)

(cw "AUDIT-BEGIN|lexicographic-<-0282|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0282|compiled|~x0~%" (audit-acl2-0282))

(cw "AUDIT-BEGIN|lexicographic-<-0282|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0282|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(0 1) '#C(1/2 -2)))))

(defun audit-acl2-0283 () (with-guard-checking NIL (ec-call (< '#C(1/2 -2) '#C(1/2 -1)))))

(verify-guards audit-acl2-0283)

(cw "AUDIT-BEGIN|lexicographic-<-0283|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0283|compiled|~x0~%" (audit-acl2-0283))

(cw "AUDIT-BEGIN|lexicographic-<-0283|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0283|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1/2 -2) '#C(1/2 -1)))))

(defun audit-acl2-0284 () (with-guard-checking NIL (ec-call (< '#C(1/2 -1) '#C(1/2 0)))))

(verify-guards audit-acl2-0284)

(cw "AUDIT-BEGIN|lexicographic-<-0284|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0284|compiled|~x0~%" (audit-acl2-0284))

(cw "AUDIT-BEGIN|lexicographic-<-0284|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0284|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1/2 -1) '#C(1/2 0)))))

(defun audit-acl2-0285 () (with-guard-checking NIL (ec-call (< '#C(1/2 0) '#C(1/2 1)))))

(verify-guards audit-acl2-0285)

(cw "AUDIT-BEGIN|lexicographic-<-0285|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0285|compiled|~x0~%" (audit-acl2-0285))

(cw "AUDIT-BEGIN|lexicographic-<-0285|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0285|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1/2 0) '#C(1/2 1)))))

(defun audit-acl2-0286 () (with-guard-checking NIL (ec-call (< '#C(1/2 1) '#C(2 -100)))))

(verify-guards audit-acl2-0286)

(cw "AUDIT-BEGIN|lexicographic-<-0286|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0286|compiled|~x0~%" (audit-acl2-0286))

(cw "AUDIT-BEGIN|lexicographic-<-0286|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0286|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1/2 1) '#C(2 -100)))))

(defun audit-acl2-0287 () (with-guard-checking NIL (ec-call (< '#C(2 -100) '-1))))

(verify-guards audit-acl2-0287)

(cw "AUDIT-BEGIN|lexicographic-<-0287|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0287|compiled|~x0~%" (audit-acl2-0287))

(cw "AUDIT-BEGIN|lexicographic-<-0287|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0287|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(2 -100) '-1))))

(defun audit-acl2-0288 () (with-guard-checking NIL (ec-call (< '#C(1 2) '#C(1 3)))))

(verify-guards audit-acl2-0288)

(cw "AUDIT-BEGIN|lexicographic-<-0288|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0288|compiled|~x0~%" (audit-acl2-0288))

(cw "AUDIT-BEGIN|lexicographic-<-0288|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0288|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1 2) '#C(1 3)))))

(defun audit-acl2-0289 () (with-guard-checking NIL (ec-call (< '#C(1 3) '#C(1 2)))))

(verify-guards audit-acl2-0289)

(cw "AUDIT-BEGIN|lexicographic-<-0289|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0289|compiled|~x0~%" (audit-acl2-0289))

(cw "AUDIT-BEGIN|lexicographic-<-0289|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0289|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1 3) '#C(1 2)))))

(defun audit-acl2-0290 () (with-guard-checking NIL (ec-call (< '#C(1 2) '2))))

(verify-guards audit-acl2-0290)

(cw "AUDIT-BEGIN|lexicographic-<-0290|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0290|compiled|~x0~%" (audit-acl2-0290))

(cw "AUDIT-BEGIN|lexicographic-<-0290|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0290|direct|~x0~%" (with-guard-checking NIL (ec-call (< '#C(1 2) '2))))

(defun audit-acl2-0291 () (< '1 '2))

(verify-guards audit-acl2-0291)

(cw "AUDIT-BEGIN|lexicographic-<-0291|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0291|compiled|~x0~%" (audit-acl2-0291))

(cw "AUDIT-BEGIN|lexicographic-<-0291|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0291|direct|~x0~%" (< '1 '2))

(defun audit-acl2-0292 () (< '2 '2))

(verify-guards audit-acl2-0292)

(cw "AUDIT-BEGIN|lexicographic-<-0292|compiled~%")

(cw "AUDIT-RESULT|lexicographic-<-0292|compiled|~x0~%" (audit-acl2-0292))

(cw "AUDIT-BEGIN|lexicographic-<-0292|direct~%")

(cw "AUDIT-RESULT|lexicographic-<-0292|direct|~x0~%" (< '2 '2))

(defun audit-acl2-0293 () (return-last 'PROGN (nfix '-3) (len '"abcd")))

(verify-guards audit-acl2-0293)

(cw "AUDIT-BEGIN|return-last-0293|compiled~%")

(cw "AUDIT-RESULT|return-last-0293|compiled|~x0~%" (audit-acl2-0293))

(cw "AUDIT-BEGIN|return-last-0293|direct~%")

(cw "AUDIT-RESULT|return-last-0293|direct|~x0~%" (return-last 'PROGN (nfix '-3) (len '"abcd")))

(defun audit-acl2-0294 () (return-last 'PROGN (zip '0) (mbe :LOGIC (ifix '9) :EXEC (nfix '9))))

(verify-guards audit-acl2-0294)

(cw "AUDIT-BEGIN|return-last-0294|compiled~%")

(cw "AUDIT-RESULT|return-last-0294|compiled|~x0~%" (audit-acl2-0294))

(cw "AUDIT-BEGIN|return-last-0294|direct~%")

(cw "AUDIT-RESULT|return-last-0294|direct|~x0~%" (return-last 'PROGN (zip '0) (mbe :LOGIC (ifix '9) :EXEC (nfix '9))))

(defun audit-acl2-0295 () (prog2$ (zp '0) (loghead '4 '-1)))

(verify-guards audit-acl2-0295)

(cw "AUDIT-BEGIN|prog2$-0295|compiled~%")

(cw "AUDIT-RESULT|prog2$-0295|compiled|~x0~%" (audit-acl2-0295))

(cw "AUDIT-BEGIN|prog2$-0295|direct~%")

(cw "AUDIT-RESULT|prog2$-0295|direct|~x0~%" (prog2$ (zp '0) (loghead '4 '-1)))

(defun audit-acl2-0296 () (return-last 'PROGN (nfix '2) (prog2$ (ifix '1/2) (len '(1 . 2)))))

(verify-guards audit-acl2-0296)

(cw "AUDIT-BEGIN|prog2$-0296|compiled~%")

(cw "AUDIT-RESULT|prog2$-0296|compiled|~x0~%" (audit-acl2-0296))

(cw "AUDIT-BEGIN|prog2$-0296|direct~%")

(cw "AUDIT-RESULT|prog2$-0296|direct|~x0~%" (return-last 'PROGN (nfix '2) (prog2$ (ifix '1/2) (len '(1 . 2)))))

(defun audit-acl2-0297 () (mbe :LOGIC (+ '1 '2) :EXEC (- '6 '3)))

(verify-guards audit-acl2-0297)

(cw "AUDIT-BEGIN|mbe-0297|compiled~%")

(cw "AUDIT-RESULT|mbe-0297|compiled|~x0~%" (audit-acl2-0297))

(cw "AUDIT-BEGIN|mbe-0297|direct~%")

(cw "AUDIT-RESULT|mbe-0297|direct|~x0~%" (mbe :LOGIC (+ '1 '2) :EXEC (- '6 '3)))

(defun audit-acl2-0298 () (mbe :EXEC (logtail '3 '64) :LOGIC (nonnegative-integer-quotient '64 '8)))

(verify-guards audit-acl2-0298)

(cw "AUDIT-BEGIN|mbe-0298|compiled~%")

(cw "AUDIT-RESULT|mbe-0298|compiled|~x0~%" (audit-acl2-0298))

(cw "AUDIT-BEGIN|mbe-0298|direct~%")

(cw "AUDIT-RESULT|mbe-0298|direct|~x0~%" (mbe :EXEC (logtail '3 '64) :LOGIC (nonnegative-integer-quotient '64 '8)))

(defun audit-acl2-0299 () (if (zp '0) (mbe :LOGIC (fix 'A) :EXEC (ifix 'A)) '99))

(verify-guards audit-acl2-0299)

(cw "AUDIT-BEGIN|mbe-0299|compiled~%")

(cw "AUDIT-RESULT|mbe-0299|compiled|~x0~%" (audit-acl2-0299))

(cw "AUDIT-BEGIN|mbe-0299|direct~%")

(cw "AUDIT-RESULT|mbe-0299|direct|~x0~%" (if (zp '0) (mbe :LOGIC (fix 'A) :EXEC (ifix 'A)) '99))

(defun audit-acl2-0300 () (non-exec (expt '2 '8)))

(verify-guards audit-acl2-0300)

(cw "AUDIT-BEGIN|non-exec-0300|compiled~%")

(cw "AUDIT-RESULT|non-exec-0300|compiled|~x0~%" (audit-acl2-0300))

(cw "AUDIT-BEGIN|non-exec-0300|direct~%")

(cw "AUDIT-RESULT|non-exec-0300|direct|~x0~%" (non-exec (expt '2 '8)))

(defun audit-acl2-0301 () (if (zp '0) (nfix '3) (non-exec (len '"unreachable"))))

(verify-guards audit-acl2-0301)

(cw "AUDIT-BEGIN|non-exec-0301|compiled~%")

(cw "AUDIT-RESULT|non-exec-0301|compiled|~x0~%" (audit-acl2-0301))

(cw "AUDIT-BEGIN|non-exec-0301|direct~%")

(cw "AUDIT-RESULT|non-exec-0301|direct|~x0~%" (if (zp '0) (nfix '3) (non-exec (len '"unreachable"))))

(defun audit-acl2-0302 () (if (zp '1) '0 (non-exec (+ '20 '22))))

(verify-guards audit-acl2-0302)

(cw "AUDIT-BEGIN|non-exec-0302|compiled~%")

(cw "AUDIT-RESULT|non-exec-0302|compiled|~x0~%" (audit-acl2-0302))

(cw "AUDIT-BEGIN|non-exec-0302|direct~%")

(cw "AUDIT-RESULT|non-exec-0302|direct|~x0~%" (if (zp '1) '0 (non-exec (+ '20 '22))))

(quit)
