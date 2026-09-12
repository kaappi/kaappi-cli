;;; (kaappi cli) — CLI framework
;;;
;;; Declarative argument parsing, subcommands, and help generation.

(define-library (kaappi cli)
  (import (scheme base) (scheme write) (scheme char)
          (scheme process-context) (scheme cxr))
  (export cli flag option argument command
          parsed-ref parsed-flag? parsed-args parsed-command parsed-sub
          parsed-errors
          run-cli run-cli-parse generate-help)
  (begin

    ;; =================================================================
    ;; Spec builders
    ;; =================================================================

    ;; (flag "-v" "--verbose" "Enable verbose")
    (define (flag short long description)
      (check-not-help 'flag short long)
      (list 'flag short long description))

    ;; (option "-n" "--count" "Number" 10) — default 10, type inferred
    ;; (option "-o" "--output" "File")     — default #f
    (define (option short long description . args)
      (check-not-help 'option short long)
      (let ((default (if (pair? args) (car args) #f)))
        (list 'option short long description default)))

    ;; -h and --help are handled by the parser and listed on every help
    ;; page, so a spec cannot claim either name.
    (define (check-not-help who short long)
      (when (or (equal? short "-h") (equal? long "--help"))
        (error (string-append (symbol->string who)
                              ": -h and --help are reserved for the built-in help")
               short long)))

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

    (define (make-parsed opts args cmd sub errors)
      (list 'parsed opts args cmd sub errors))

    (define (parsed-ref result name)
      (let ((pair (assoc name (cadr result))))
        (if pair (cdr pair) #f)))

    (define (parsed-flag? result name)
      (eq? #t (parsed-ref result name)))

    (define (parsed-args result) (caddr result))

    (define (parsed-command result) (cadddr result))

    (define (parsed-sub result) (list-ref result 4))

    ;; Usage errors as a list of strings; '() when the parse was clean.
    ;; Errors found while scanning come first, in argv order, then
    ;; surplus positionals, then the subcommand's errors (also kept in
    ;; the subcommand's own result), then any error run-cli adds. The
    ;; order is informational, not a contract.
    (define (parsed-errors result) (list-ref result 5))

    ;; =================================================================
    ;; Parser
    ;; =================================================================

    (define (parse-args specs argv)
      (let ((options (filter option-spec? specs))
            (arguments (filter (lambda (s) (eq? (spec-type s) 'argument)) specs))
            (commands (filter (lambda (s) (eq? (spec-type s) 'command)) specs)))

        ;; pos-args, cmd-argv and errors accumulate in reverse. found-cmd
        ;; is the matched command's spec; bad-cmd is set once a bare word
        ;; has been reported as an unknown command.
        (let loop ((argv argv)
                   (opts (map (lambda (o)
                                (cons (opt-long-name o)
                                      (if (is-flag? o) #f (opt-default o))))
                              options))
                   (pos-args '())
                   (found-cmd #f)
                   (cmd-argv '())
                   (errors '())
                   (bad-cmd #f))

          (if (null? argv)
              (finish-parse arguments opts (reverse pos-args)
                            found-cmd (reverse cmd-argv) (reverse errors))

              (let ((arg (car argv)) (rest (cdr argv)))
                (cond
                  ;; "--" ends option parsing: every later token is data.
                  ;; After a command the whole tail, "--" included, is the
                  ;; subcommand's to parse; after an unknown command it
                  ;; would have been that command's data.
                  ((equal? arg "--")
                   (cond
                     (found-cmd
                      (loop '() opts pos-args found-cmd
                            (append (reverse argv) cmd-argv) errors bad-cmd))
                     (bad-cmd
                      (loop '() opts pos-args found-cmd cmd-argv errors bad-cmd))
                     (else
                      (loop '() opts (append (reverse rest) pos-args)
                            found-cmd cmd-argv errors bad-cmd))))

                  ;; "-vn5" is several short options in one token; spell
                  ;; it out and parse the pieces. After a command the
                  ;; subcommand's options are consulted first, as below.
                  ((cluster-token? arg)
                   (let ((r (expand-cluster
                              arg
                              (if found-cmd
                                  (append (filter option-spec? (cmd-specs found-cmd))
                                          options)
                                  options)
                              errors)))
                     (loop (append (car r) rest) opts pos-args found-cmd
                           cmd-argv (cadr r) bad-cmd)))

                  ;; After the command token, tokens belong to the
                  ;; subcommand, except top-level options the subcommand
                  ;; does not define itself (its own option wins). A
                  ;; subcommand option's value travels with it so it is
                  ;; never mistaken for a top-level option.
                  (found-cmd
                   (let* ((sub-options (filter option-spec? (cmd-specs found-cmd)))
                          (so (and (not (help-token? arg))
                                   (find-option sub-options arg)))
                          (to (and (not so) (not (help-token? arg))
                                   (find-option options arg))))
                     (cond
                       (to
                        (let ((r (apply-option to arg rest opts errors)))
                          (loop (cadr r) (car r) pos-args found-cmd
                                cmd-argv (caddr r) bad-cmd)))
                       ((and so (takes-value? so arg)
                             (pair? rest) (valid-value? (car rest)))
                        (loop (cdr rest) opts pos-args found-cmd
                              (cons (car rest) (cons arg cmd-argv)) errors bad-cmd))
                       (else
                        (loop rest opts pos-args found-cmd
                              (cons arg cmd-argv) errors bad-cmd)))))

                  ;; --help wins over everything else, errors included
                  ((help-token? arg)
                   (make-parsed (cons (cons "help" #t) opts) '() #f #f '()))

                  ((find-option options arg)
                   => (lambda (o)
                        (let ((r (apply-option o arg rest opts errors)))
                          (loop (cadr r) (car r) pos-args found-cmd
                                cmd-argv (caddr r) bad-cmd))))

                  ;; Option-shaped but matches nothing: a negative number
                  ;; is data, anything else is a mistake.
                  ((option-shaped? arg)
                   (if (real-number-token? arg)
                       (loop rest opts (cons arg pos-args) found-cmd
                             cmd-argv errors bad-cmd)
                       (loop rest opts pos-args found-cmd cmd-argv
                             (cons (string-append "unknown option '"
                                                  (option-token-name arg) "'")
                                   errors)
                             bad-cmd)))

                  ((and (not bad-cmd) (find-command commands arg))
                   => (lambda (cs)
                        (loop rest opts pos-args cs cmd-argv errors bad-cmd)))

                  ;; With commands but no positionals a bare word can only
                  ;; be a mistyped command. Report the first one; later
                  ;; bare words would have been its arguments, so they are
                  ;; skipped, while option-shaped tokens keep being checked.
                  ((and (pair? commands) (null? arguments))
                   (loop rest opts pos-args found-cmd cmd-argv
                         (if bad-cmd
                             errors
                             (cons (string-append "unknown command '" arg "'")
                                   errors))
                         (or bad-cmd arg)))

                  (else
                   (loop rest opts (cons arg pos-args)
                         found-cmd cmd-argv errors bad-cmd))))))))

    ;; Build the result: parse the subcommand's argv, bind positionals,
    ;; and report positionals beyond the declared ones.
    (define (finish-parse arguments opts pos found-cmd cmd-argv errors)
      (let* ((sub (and found-cmd (parse-args (cmd-specs found-cmd) cmd-argv)))
             (extra (if (> (length pos) (length arguments))
                        (list-tail pos (length arguments))
                        '())))
        (make-parsed opts
                     (match-positional arguments pos)
                     (and found-cmd (cmd-name found-cmd))
                     sub
                     (append errors
                             (map (lambda (x)
                                    (string-append "unexpected argument '" x "'"))
                                  extra)
                             (if sub (parsed-errors sub) '())))))

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

    (define (option-spec? s)
      (or (eq? (spec-type s) 'option) (eq? (spec-type s) 'flag)))

    ;; Token shapes: "--name", "--name=value", "-x". The lone "-" is data.
    (define (option-shaped? tok)
      (and (> (string-length tok) 1) (char=? (string-ref tok 0) #\-)))

    (define (long-token? tok)
      (and (> (string-length tok) 2) (string=? (substring tok 0 2) "--")))

    ;; "--name=value" -> "--name"; any other token unchanged
    (define (option-token-name tok)
      (let ((ep (and (long-token? tok) (str-idx tok #\=))))
        (if ep (substring tok 0 ep) tok)))

    ;; "--name=value" -> "value"; #f when there is no "="
    (define (option-token-value tok)
      (let ((ep (and (long-token? tok) (str-idx tok #\=))))
        (and ep (substring tok (+ ep 1) (string-length tok)))))

    (define (help-token? tok)
      (or (equal? tok "-h") (equal? (option-token-name tok) "--help")))

    ;; The option spec a token names, or #f
    (define (find-option options tok)
      (cond ((long-token? tok) (find-opt-long options (option-token-name tok)))
            ((and (= (string-length tok) 2) (option-shaped? tok))
             (find-opt-short options tok))
            (else #f)))

    ;; A dash-leading token that is a real number ("-5", "-1.5e2") is
    ;; data. real? rejects number-shaped flags such as "-i", which
    ;; string->number reads as the complex -i.
    (define (real-number-token? tok)
      (let ((n (string->number tok)))
        (and n (real? n))))

    ;; A token an option may take as its value: anything that is not
    ;; option-shaped (the lone "-", the stdin convention, included) or a
    ;; negative real number. "-v", "--help" and "--" are never values.
    (define (valid-value? tok)
      (or (not (option-shaped? tok)) (real-number-token? tok)))

    ;; "-abc": a single dash, more than one character, not a number
    (define (cluster-token? tok)
      (and (> (string-length tok) 2)
           (char=? (string-ref tok 0) #\-)
           (not (char=? (string-ref tok 1) #\-))
           (not (real-number-token? tok))))

    ;; Spell out a cluster of short options as one token per option:
    ;; flags may run together ("-vv"), and the first option that takes a
    ;; value swallows the rest of the token, with or without "=" ("-n5",
    ;; "-n=5", "-vn5"); with nothing left it takes the next argv token as
    ;; usual. A value is emitted as "--long=value" so it is used verbatim.
    ;; Returns (list tokens errors). A cluster whose first letter is not
    ;; an option is reported whole, as the user most likely meant a
    ;; single option ("-foo"); a later unknown letter is reported alone.
    (define (expand-cluster tok options errors)
      (let loop ((i 1) (acc '()) (errors errors))
        (if (= i (string-length tok))
            (list (reverse acc) errors)
            (let* ((short (string #\- (string-ref tok i)))
                   (o (find-opt-short options short))
                   (more (substring tok (+ i 1) (string-length tok))))
              (cond
                ((and o (not (is-flag? o)))
                 (list (reverse
                         (cons (if (string=? more "")
                                   short
                                   (string-append
                                     (opt-long o) "="
                                     (if (char=? (string-ref more 0) #\=)
                                         (substring more 1 (string-length more))
                                         more)))
                               acc))
                       errors))
                ((or o (string=? short "-h"))
                 (loop (+ i 1) (cons short acc) errors))
                ((= i 1)
                 (list '() (cons (string-append "unknown option '" tok "'")
                                 errors)))
                (else
                 (loop (+ i 1) acc
                       (cons (string-append "unknown option '" short "'")
                             errors))))))))

    ;; Does option o, written as tok, still need a value from the next token?
    (define (takes-value? o tok)
      (and (not (is-flag? o)) (not (option-token-value tok))))

    ;; Apply option o for token tok, taking the value from "=value" or the
    ;; next token. Returns (list opts rest errors). A flag ignores any
    ;; =value; an option with no usable value keeps its default and
    ;; records an error.
    (define (apply-option o tok rest opts errors)
      (let ((name (opt-long-name o)) (inline (option-token-value tok)))
        (cond
          ((is-flag? o)
           (list (set-opt opts name #t) rest errors))
          (inline
           (list (set-opt opts name (coerce inline (opt-default o))) rest errors))
          ((and (pair? rest) (valid-value? (car rest)))
           (list (set-opt opts name (coerce (car rest) (opt-default o)))
                 (cdr rest) errors))
          (else
           (list opts rest
                 (cons (string-append "option '" (option-token-name tok)
                                      "' requires a value")
                       errors))))))

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
        (display " [options]")
        (unless (null? cmds) (display " <command>"))
        (for-each (lambda (a) (display " <") (display (arg-name a)) (display ">"))
                  positionals)
        (newline)

        ;; -h/--help is accepted on every page, so the section always shows
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
        (display "Show this help") (newline)

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

    ;; (run-cli app handlers)      — parse (command-line), dispatch
    ;; (run-cli app handlers argv) — parse explicit argv (for testing)
    ;;
    ;; handlers is an alist keyed by command name, with (#f . proc) for
    ;; "no command" and an optional (error . proc) that takes over usage
    ;; error reporting. Every proc receives the parsed result.
    (define (run-cli app handlers . rest)
      (let* ((argv (if (pair? rest) (car rest) (cdr (command-line))))
             (result (parse-args (cli-specs app) argv)))
        (cond
          ((parsed-ref result "help")
           (generate-help app))
          ((and (parsed-command result)
                (parsed-sub result)
                (parsed-ref (parsed-sub result) "help"))
           (generate-help app (parsed-command result)))
          ((pair? (parsed-errors result))
           (usage-error app handlers result))
          ((parsed-command result)
           (let ((h (assoc (parsed-command result) handlers)))
             (if h
                 ((cdr h) result)
                 ;; A declared command with no dispatch entry is a bug in
                 ;; the app, not in the invocation.
                 (error "run-cli: no handler for command"
                        (parsed-command result)))))
          (else
           (let ((h (assoc #f handlers)))
             (cond
               (h ((cdr h) result))
               ((pair? (filter (lambda (s) (eq? (spec-type s) 'command))
                               (cli-specs app)))
                (usage-error app handlers
                             (add-error result "missing command")))
               (else
                (error "run-cli: no default (#f) handler"))))))))

    (define (add-error result msg)
      (make-parsed (cadr result) (parsed-args result) (parsed-command result)
                   (parsed-sub result)
                   (append (parsed-errors result) (list msg))))

    ;; Report usage errors on stderr and exit 2, unless handlers has an
    ;; (error . proc) entry, in which case proc decides.
    (define (usage-error app handlers result)
      (let ((h (assoc 'error handlers)))
        (if h
            ((cdr h) result)
            (let ((err (current-error-port)) (name (cli-name app)))
              (for-each (lambda (msg)
                          (display name err) (display ": " err)
                          (display msg err) (newline err))
                        (parsed-errors result))
              (display "Try '" err) (display name err)
              (display " --help' for more information." err) (newline err)
              (exit 2)))))))
