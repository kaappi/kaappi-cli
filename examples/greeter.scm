;;; Example CLI app with subcommands
(import (scheme base) (scheme write) (kaappi cli))

(define app
  (cli "greeter" "A friendly greeting tool"
    (flag "-l" "--loud" "Use uppercase")
    (option "-n" "--times" "Repeat N times" 1)
    (argument "name" "Name to greet")
    (command "farewell" "Say goodbye"
      (argument "name" "Name"))))

(run-cli app
  `((#f . ,(lambda (result)
             (let ((name (or (cdr (car (parsed-args result))) "World"))
                   (loud (parsed-flag? result "loud"))
                   (times (parsed-ref result "times")))
               (let loop ((i 0))
                 (when (< i times)
                   (let ((msg (string-append "Hello, " name "!")))
                     (display (if loud (string-upcase msg) msg))
                     (newline))
                   (loop (+ i 1)))))))
    ("farewell" . ,(lambda (result)
                     (let* ((sub (parsed-sub result))
                            (name (if sub
                                      (cdr (car (parsed-args sub)))
                                      "World")))
                       (display "Goodbye, ")
                       (display name)
                       (display "!")
                       (newline))))))

(define (string-upcase s)
  (let* ((len (string-length s))
         (out (make-string len)))
    (let loop ((i 0))
      (when (< i len)
        (string-set! out i (char-upcase (string-ref s i)))
        (loop (+ i 1))))
    out))
