; extends

; Operators
[
  operator: (direction)
  redirect: (stream_redirect)
] @operator.redirect.fish

redirect: (file_redirect
  destination: (word) @string.special.path)

; Commands
(command
  [
    name: (concatenation
      (word) @constant)
    argument: (concatenation
      (word) @constant)
    argument: (word) @constant
  ]+
  .
  argument: (word) @function.call
  (#match? @function.call "^[^=]+$")
  (#match? @constant "="))

(command
  argument: [
    (word) @variable.parameter.flag
    (#lua-match? @variable.parameter.flag "^[-]")
  ])

(command
  argument: [
    (word) @variable.parameter.argument
    (#lua-match? @variable.parameter.argument "^[^-]+")
  ])

(function_definition
  option: [
    (word)
    (concatenation
      (word))
  ] @variable.parameter.flag
  (#lua-match? @variable.parameter.flag "^[-]"))

; Variables
((variable_name) @constant
  (#lua-match? @constant "^[A-Z][A-Z_0-9]*$"))

; ((command
;   [
;     name: (concatenation
;       (word) @constant)
;     argument: (concatenation
;       (word) @constant)
;   ])
;   (#offset! @constant 0 0 0 -1))
; Punctuation
";" @punctuation.delimiter
