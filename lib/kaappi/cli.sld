;;; (kaappi cli) — CLI framework
;;;
;;; Declarative argument parsing, subcommands, and help generation.

(define-library (kaappi cli)
  (import (scheme base) (scheme write) (scheme char)
          (scheme process-context) (scheme cxr))
  (export cli flag option argument command
          parsed-ref parsed-flag? parsed-args parsed-command parsed-sub
          run-cli run-cli-parse generate-help)
  (begin

    ;; =================================================================
    ;; Spec builders
    ;; =================================================================

    ;; (flag "-v" "--verbose" "Enable verbose")
    (define (flag short long description)
      (list 'flag short long description))

    ;; (option "-n" "--count" "Number" 10) — default 10, type inferred
    ;; (option "-o" "--output" "File")     — default #f
    (define (option short long description . args)
      (let ((default (if (pair? args) (car args) #f)))
        (list 'option short long description default)))

    ;; (argument "file" "Input file")
    (define (argument name description)
      (list 'argument name description))

    ;; (command "init" "Initialize" (argument "name" "Project name"))
    (define (command name description . specs)
      (list 'command name description specs))

    ;; Spec accessors
    (define (spec-type s) (car s))
    (define (opt-short s) (cadr s))
    (define (opt-long s) (caddr s))
    (define (opt-desc s) (cadddr s))
    (define (opt-default s) (list-ref s 4))
    (define (arg-name s) (cadr s))
    (define (arg-desc s) (caddr s))
    (define (cmd-name s) (cadr s))
    (define (cmd-desc s) (caddr s))
    (define (cmd-specs s) (cadddr s))

    (define (list-ref lst n)
      (if (= n 0) (car lst) (list-ref (cdr lst) (- n 1))))

    (define (is-flag? s) (eq? (spec-type s) 'flag))

    (define (opt-long-name s)
      (let ((long (opt-long s)))
        (substring long 2 (string-length long))))

    ;; =================================================================
    ;; CLI definition + parsed result
    ;; =================================================================

    (define (cli name description . specs)
      (list 'cli name description specs))

    (define (cli-name c) (cadr c))
    (define (cli-desc c) (caddr c))
    (define (cli-specs c) (cadddr c))

    (define (make-parsed opts args cmd sub)
      (list 'parsed opts args cmd sub))

    (define (parsed-ref result name)
      (let ((pair (assoc name (cadr result))))
        (if pair (cdr pair) #f)))

    (define (parsed-flag? result name)
      (eq? #t (parsed-ref result name)))

    (define (parsed-args result) (caddr result))

    (define (parsed-command result) (cadddr result))

    (define (parsed-sub result) (list-ref result 4))

    ;; =================================================================
    ;; Parser
    ;; =================================================================

    (define (parse-args specs argv)
      (let ((options (filter (lambda (s) (or (eq? (spec-type s) 'option)
                                             (eq? (spec-type s) 'flag))) specs))
            (arguments (filter (lambda (s) (eq? (spec-type s) 'argument)) specs))
            (commands (filter (lambda (s) (eq? (spec-type s) 'command)) specs)))

        (let loop ((argv argv)
                   (opts (map (lambda (o)
                                (cons (opt-long-name o)
                                      (if (is-flag? o) #f (opt-default o))))
                              options))
                   (pos-args '())
                   (found-cmd #f)
                   (cmd-argv '()))

          (if (null? argv)
              (make-parsed opts
                (match-positional arguments (reverse pos-args))
                found-cmd
                (if found-cmd
                    (let ((cs (find-command commands found-cmd)))
                      (if cs (parse-args (cmd-specs cs) (reverse cmd-argv)) #f))
                    #f))

              (let ((arg (car argv)) (rest (cdr argv)))
                (cond
                  (found-cmd
                   (loop rest opts pos-args found-cmd (cons arg cmd-argv)))

                  ((or (equal? arg "--help") (equal? arg "-h"))
                   (make-parsed (cons (cons "help" #t) opts) '() #f #f))

                  ;; --name=value
                  ((and (> (string-length arg) 2)
                        (equal? (substring arg 0 2) "--")
                        (str-has? arg #\=))
                   (let* ((ep (str-idx arg #\=))
                          (name (substring arg 0 ep))
                          (val (substring arg (+ ep 1) (string-length arg)))
                          (o (find-opt-long options name)))
                     (if o
                         (loop rest (set-opt opts (opt-long-name o)
                                     (coerce val (opt-default o)))
                               pos-args found-cmd cmd-argv)
                         (loop rest opts pos-args found-cmd cmd-argv))))

                  ;; --name [value]
                  ((and (> (string-length arg) 2)
                        (equal? (substring arg 0 2) "--"))
                   (let ((o (find-opt-long options arg)))
                     (if o
                         (if (is-flag? o)
                             (loop rest (set-opt opts (opt-long-name o) #t)
                                   pos-args found-cmd cmd-argv)
                             (if (pair? rest)
                                 (loop (cdr rest)
                                       (set-opt opts (opt-long-name o)
                                         (coerce (car rest) (opt-default o)))
                                       pos-args found-cmd cmd-argv)
                                 (loop rest opts pos-args found-cmd cmd-argv)))
                         (loop rest opts pos-args found-cmd cmd-argv))))

                  ;; -x [value]
                  ((and (= (string-length arg) 2) (char=? (string-ref arg 0) #\-))
                   (let ((o (find-opt-short options arg)))
                     (if o
                         (if (is-flag? o)
                             (loop rest (set-opt opts (opt-long-name o) #t)
                                   pos-args found-cmd cmd-argv)
                             (if (pair? rest)
                                 (loop (cdr rest)
                                       (set-opt opts (opt-long-name o)
                                         (coerce (car rest) (opt-default o)))
                                       pos-args found-cmd cmd-argv)
                                 (loop rest opts pos-args found-cmd cmd-argv)))
                         (loop rest opts pos-args found-cmd cmd-argv))))

                  ;; command?
                  ((find-command commands arg)
                   (loop rest opts pos-args arg cmd-argv))

                  ;; positional
                  (else
                   (loop rest opts (cons arg pos-args)
                         found-cmd cmd-argv))))))))

    ;; =================================================================
    ;; Helpers
    ;; =================================================================

    (define (filter pred lst)
      (cond ((null? lst) '())
            ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
            (else (filter pred (cdr lst)))))

    (define (find-opt-long opts name)
      (let loop ((os opts))
        (cond ((null? os) #f)
              ((equal? (opt-long (car os)) name) (car os))
              (else (loop (cdr os))))))

    (define (find-opt-short opts name)
      (let loop ((os opts))
        (cond ((null? os) #f)
              ((equal? (opt-short (car os)) name) (car os))
              (else (loop (cdr os))))))

    (define (find-command cmds name)
      (let loop ((cs cmds))
        (cond ((null? cs) #f)
              ((equal? (cmd-name (car cs)) name) (car cs))
              (else (loop (cdr cs))))))

    (define (set-opt opts name value)
      (map (lambda (p) (if (equal? (car p) name) (cons name value) p)) opts))

    (define (match-positional specs vals)
      (let loop ((ss specs) (vs vals) (acc '()))
        (cond ((null? ss) (reverse acc))
              ((null? vs) (reverse (append (map (lambda (s) (cons (arg-name s) #f)) ss) acc)))
              (else (loop (cdr ss) (cdr vs) (cons (cons (arg-name (car ss)) (car vs)) acc))))))

    (define (coerce s default)
      (if (and default (number? default))
          (or (string->number s) s)
          s))

    (define (str-has? s ch)
      (let loop ((i 0))
        (cond ((= i (string-length s)) #f)
              ((char=? (string-ref s i) ch) #t)
              (else (loop (+ i 1))))))

    (define (str-idx s ch)
      (let loop ((i 0))
        (cond ((= i (string-length s)) #f)
              ((char=? (string-ref s i) ch) i)
              (else (loop (+ i 1))))))

    ;; =================================================================
    ;; Help generation
    ;; =================================================================

    (define (generate-help app . args)
      (let* ((sub-name (if (pair? args) (car args) #f))
             (name (cli-name app))
             (specs (if sub-name
                        (let ((c (find-command
                                   (filter (lambda (s) (eq? (spec-type s) 'command))
                                           (cli-specs app))
                                   sub-name)))
                          (if c (cmd-specs c) (cli-specs app)))
                        (cli-specs app)))
             (desc (if sub-name
                       (let ((c (find-command
                                  (filter (lambda (s) (eq? (spec-type s) 'command))
                                          (cli-specs app))
                                  sub-name)))
                         (if c (cmd-desc c) (cli-desc app)))
                       (cli-desc app)))
             (opts (filter (lambda (s) (or (eq? (spec-type s) 'option)
                                           (eq? (spec-type s) 'flag))) specs))
             (positionals (filter (lambda (s) (eq? (spec-type s) 'argument)) specs))
             (cmds (filter (lambda (s) (eq? (spec-type s) 'command)) specs)))

        (display name)
        (when sub-name (display " ") (display sub-name))
        (display " — ") (display desc) (newline) (newline)

        (display "Usage: ") (display name)
        (when sub-name (display " ") (display sub-name))
        (unless (null? opts) (display " [options]"))
        (unless (null? cmds) (display " <command>"))
        (for-each (lambda (a) (display " <") (display (arg-name a)) (display ">"))
                  positionals)
        (newline)

        (unless (null? opts)
          (newline) (display "Options:") (newline)
          (for-each
            (lambda (o)
              (display "  ") (display (opt-short o))
              (display ", ") (display (opt-long o))
              (unless (is-flag? o) (display " <value>"))
              (display (pad (+ (string-length (opt-short o))
                               (string-length (opt-long o))
                               (if (is-flag? o) 4 12))
                            28))
              (display (opt-desc o))
              (when (and (not (is-flag? o)) (opt-default o))
                (display " (default: ") (display (opt-default o)) (display ")"))
              (newline))
            opts)
          (display "  -h, --help")
          (display (pad 12 28))
          (display "Show this help") (newline))

        (unless (null? positionals)
          (newline) (display "Arguments:") (newline)
          (for-each
            (lambda (a)
              (display "  <") (display (arg-name a)) (display ">")
              (display (pad (+ (string-length (arg-name a)) 4) 28))
              (display (arg-desc a)) (newline))
            positionals))

        (unless (null? cmds)
          (newline) (display "Commands:") (newline)
          (for-each
            (lambda (c)
              (display "  ") (display (cmd-name c))
              (display (pad (+ (string-length (cmd-name c)) 2) 28))
              (display (cmd-desc c)) (newline))
            cmds))))

    (define (pad current target)
      (if (>= current target) "  " (make-string (- target current) #\space)))

    ;; =================================================================
    ;; run-cli
    ;; =================================================================

    (define (run-cli-parse app argv)
      (parse-args (cli-specs app) argv))

    (define (run-cli app handlers)
      (let* ((argv (cdr (command-line)))
             (result (parse-args (cli-specs app) argv)))
        (cond
          ((parsed-ref result "help")
           (generate-help app))
          ((parsed-command result)
           (let ((h (assoc (parsed-command result) handlers)))
             (if h ((cdr h) result)
                 (begin (display "Unknown command: ")
                        (display (parsed-command result)) (newline)
                        (generate-help app)))))
          (else
           (let ((h (assoc #f handlers)))
             (if h ((cdr h) result) (generate-help app)))))))))
