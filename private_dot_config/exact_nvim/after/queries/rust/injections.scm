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
([
  (line_comment
    doc: (doc_comment) @injection.content)
  (block_comment
    doc: (doc_comment) @injection.content)
]
  (#set! injection.language "markdown"))
