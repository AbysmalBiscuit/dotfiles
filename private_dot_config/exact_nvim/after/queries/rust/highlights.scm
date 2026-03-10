; extends

; match self
((self) @variable.instance_reference
  (#set! "priority" 128))

; Set macro invocation priorirty
((macro_invocation
  macro: (identifier) @function.macro.rust)
  (#set! "priority" 128))

; set parameter priorirty
; (
;   (parameter
;     pattern: (identifier)  @variable.parameter.rust)
;   (#set! "priority" 128)
; )
; function parameters
(function_item
  parameters: (parameters
    (parameter
      pattern: (identifier) @variable.parameter.declaration
      (#set! "priority" 128))))

; docstrings
(line_comment
  "//" @comment.documentation.prefix
  outer: (outer_doc_comment_marker) @comment.documentation.prefix)

(block_comment
  "/*" @comment.documentation.prefix
  outer: (outer_doc_comment_marker) @comment.documentation.prefix
  _
  "*/" @comment.documentation.prefix)

; (_
;   [
;     "//"
;     "/*"
;   ] @comment.documentation.prefix
;   outer: (outer_doc_comment_marker))
;
; (_
;   [
;     outer: (outer_doc_comment_marker)
;     "/"
;   ] @comment.documentation.prefix)
