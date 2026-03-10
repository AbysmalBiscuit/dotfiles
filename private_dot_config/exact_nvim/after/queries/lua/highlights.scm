; extends

; docstrings
((comment
  "--" @comment.documentation.prefix
  content: (comment_content) @_comment_prefix)
  (#lua-match? @_comment_prefix "^-")
  (#eq? @comment.documentation.prefix "--"))

((comment) @comment.documentation.prefix
  (#any-of? @comment.documentation.prefix "---" "--- "))

; (block_comment
;   "/*" @comment.documentation.rust.prefix
;   outer: (outer_doc_comment_marker) @comment.documentation.rust.prefix
;   _
;   "*/" @comment.documentation.rust.prefix)
