; extends

; docstrings markdown
; (line_comment
;   outer: (outer_doc_comment_marker)
;   doc: (doc_comment) @injection.content
;   (#set! injection.language "markdown"))
;
; (block_comment
;   outer: (outer_doc_comment_marker)
;   doc: (doc_comment) @injection.content
;   (#set! injection.language "markdown"))
((comment
  content: (comment_content) @injection.content)
  (#lua-match? @injection.content "^-.+")
  (#set! injection.language "markdown"))

; ((comment
;   _ @_injection_start
;   [
;     "-"
;     (_) @injection.content
;   ])
;   (#lua-match? @_injection_start "^---")
;   (#set! injection.language "markdown"))
