; extends

((named_capturing_group) @regex.named_capturing_group
  (#set! priority 100))

((named_capturing_group
  (group_name) @regex.group_name)
  (#set! priority 100))

(named_capturing_group
  [
    "(?P<"
    ">"
  ] @regex.group_syntax.python
  (group_name) @regex.group_name
  (#set! priority 100))
