; extends

; Commands
(command
  argument: [
    (word) @variable.parameter.flag
    (concatenation
      (word) @variable.parameter.flag)
    (#lua-match? @variable.parameter.flag "^[-]")
  ])

redirect: (file_redirect
  descriptor: (file_descriptor) @operator.redirect
  destination: (number) @operator.redirect)

; Operators
[
  ">"
  ">>"
  "<"
  "<<"
  "&>"
  "&>>"
  "<&"
  ">&"
  "<&-"
  ">&-"
  "<<-"
  "<<<"
] @operator.redirect

redirect: (file_redirect
  destination: (word) @string.special.path)
