;; extends

(
 (variable_declarator
   name: (identifier) @variable_declaration 
 ) 
 (#set! "priority" 128)
)

(
 (variable_declarator
  name: (array_pattern
    (identifier) @declaration_array_member
      ))
 (#set! "priority" 128)
 )
