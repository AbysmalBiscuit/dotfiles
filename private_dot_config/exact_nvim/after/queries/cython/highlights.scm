; extends

; match self
(((identifier) @variable.instance_reference
  (#eq? @variable.instance_reference "self"))
  (#set! "priority" 128))

; match cls
(((identifier) @variable.class_reference
  (#eq? @variable.class_reference "cls"))
  (#set! "priority" 128))

; Decorators
((decorator
  "@" @decorator)
  (#set! priority 101))

(decorator
  (identifier) @decorator.identifier
  (#set! priority 128))

(decorator
  (attribute
    attribute: (identifier) @decorator.identifier)
  (#set! priority 128))

(decorator
  (call
    (identifier) @decorator.identifier)
  (#set! priority 128))

(decorator
  (call
    (attribute
      attribute: (identifier) @decorator.identifier))
  (#set! priority 101))

((decorator
  (identifier) @decorator.builtin)
  (#any-of? @decorator.builtin "classmethod" "property" "staticmethod")
  (#set! priority 128))

; when an imported namespace/module is used in a decorator
(decorator
  (call
    (attribute
      object: (identifier) @module))
  (#set! priority 128))

; match magic methods
((function_definition
  name: (identifier) @magic_method.python
  (#match? @magic_method.python "^__[A-Za-z0-9_]+__$"))
  (#set! "priority" 128))

; builtin attributes
(attribute
  attribute: (identifier) @magic_attribute.python
  (#match? @magic_attribute.python "^__[A-Za-z0-9_]+__$"))

; builtin function calls
; Builtin functions
((call
  function: (identifier) @function.builtin)
  (#any-of? @function.builtin
    "abs" "all" "any" "ascii" "bin" "bool" "breakpoint" "bytearray" "bytes" "callable" "chr"
    "classmethod" "compile" "complex" "delattr" "dict" "dir" "divmod" "enumerate" "eval" "exec"
    "filter" "float" "format" "frozenset" "getattr" "globals" "hasattr" "hash" "help" "hex" "id"
    "input" "int" "isinstance" "issubclass" "iter" "len" "list" "locals" "map" "max" "memoryview"
    "min" "next" "object" "oct" "open" "ord" "pow" "print" "property" "range" "repr" "reversed"
    "round" "set" "setattr" "slice" "sorted" "staticmethod" "str" "sum" "super" "tuple" "type"
    "vars" "zip" "__import__")
  (#set! "priority" 101))

; Inject regex grammar into raw strings used with re module
; ((string_start
;   (string_content
;     (pattern
;       (start_assertion)
;       (named_capturing_group)
;    @regex.named_capturing_group)))
;   ; (#eq? @_re "re")
;   ; (#any-of? @_method "compile" "search" "match" "findall" "finditer" "sub" "subn" "split")
;   (#set! injection.language "regex"))
; (call
;   function: (attribute
;     object: (identifier) @_re)
;   arguments: (argument_list
;     .
;     (string
;       (string_content) @string.regexp))
;   (#eq? @_re "re"))
; ((call
;   function: (attribute
;     object: (identifier) @_re
;     attribute: (identifier) @_method)
;   arguments: (argument_list
;     (string) @regex.named_capturing_group))
;   ; (#eq? @_re "re")
;   ; (#any-of? @_method "compile" "search" "match" "findall" "finditer" "sub" "subn" "split")
;   (#set! injection.language "regex"))
; Also match re.Pattern[...] type hints if needed
; ((call
;   function: (identifier) @_re_func
;   arguments: (argument_list
;     (string) @regex.named_capturing_group.python))
;   (#any-of? @_re_func "re.compile" "re.search" "re.match" "re.findall" "re.finditer" "re.sub" "re.subn" "re.split")
;   (#set! injection.language "regex")
;   (#set! priority 126))
(call
  function: (attribute
    object: (identifier) @_re)
  arguments: (argument_list
    (comment)*
    .
    [
      (string
        (string_content) @string.regexp)
      (concatenated_string
        [
          (string
            (string_content) @string.regexp)
          (comment)
        ]+)
    ])
  (#eq? @_re "re"))

; update keywords to match python
[
  "and"
  "in"
  "is"
  "not"
  "or"
] @keyword
