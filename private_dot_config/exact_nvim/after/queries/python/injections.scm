; extends

; regex
((string
  (string_start) @_string_start
  (string_content) @injection.content)
  (#lua-match? @_string_start "[ft]?r[ft]?")
  (#set! injection.language "regex"))

;
; SQL injections
; ((string
;   (string_content) @injection.content @sql.wrapper)?
;   ; (#lua-match? @injection.content
;   ;   "ALTER TABLE" "ANALYZE" "ATTACH DATABASE" "BEGIN TRANSACTION" "COMMIT TRANSACTION"
;   ;   "CREATE INDEX" "CREATE TABLE" "CREATE TRIGGER" "CREATE VIEW" "CREATE VIRTUAL TABLE"
;   ;   "DELETE" "DETACH DATABASE" "DROP INDEX" "DROP TABLE" "DROP TRIGGER" "DROP VIEW"
;   ;   "END TRANSACTION" "EXPLAIN" "INDEXED BY" "INSERT" "ON CONFLICT" "PRAGMA" "REINDEX"
;   ;   "RELEASE SAVEPOINT" "REPLACE" "RETURNING" "ROLLBACK TRANSACTION" "SAVEPOINT"
;   ;   "SELECT" "UPDATE" "UPSERT" "VACUUM" "WITH"
;   ;  )
;    (#lua-match? @injection.content "[%u]+" _command_name)
;   ; (#any-of? @injection.content "ANALYZE")
;   (#set! injection.language "sql"))
((string
  (string_content) @injection.content)
  (#match? @injection.content
    "[\\s|\\n|\\r]*(ALTER TABLE|ANALYZE|ATTACH DATABASE|BEGIN TRANSACTION|COMMIT TRANSACTION|CREATE INDEX|CREATE TABLE|CREATE TRIGGER|CREATE VIEW|CREATE VIRTUAL TABLE|DELETE|DETACH DATABASE|DROP INDEX|DROP TABLE|DROP TRIGGER|DROP VIEW|END TRANSACTION|EXPLAIN|INDEXED BY|INSERT|ON CONFLICT|PRAGMA|REINDEX|RELEASE SAVEPOINT|REPLACE|RETURNING|ROLLBACK TRANSACTION|SAVEPOINT|SELECT|UPDATE|UPSERT|VACUUM|WITH).*")
  (#set! injection.language "sql"))

; (string
;   (string_start) @_string_start
;   (string_content) @injection.content
;   (#lua-match? @injection.content "%s*ALTER TABLE.*")
;   (#set! injection.language "sql"))
; (string
;   (string_start) @_string_start
;   (string_content) @injection.content
;   [
;     (#lua-match? @injection.content "%s*ALTER TABLE.*")
;     (#lua-match? @injection.content "%s*ANALYZE.*")
;     (#lua-match? @injection.content "%s*ATTACH DATABASE.*")
;     (#lua-match? @injection.content "%s*BEGIN TRANSACTION.*")
;     (#lua-match? @injection.content "%s*COMMIT TRANSACTION.*")
;     (#lua-match? @injection.content "%s*CREATE INDEX.*")
;     (#lua-match? @injection.content "%s*CREATE TABLE.*")
;     (#lua-match? @injection.content "%s*CREATE TRIGGER.*")
;     (#lua-match? @injection.content "%s*CREATE VIEW.*")
;     (#lua-match? @injection.content "%s*CREATE VIRTUAL TABLE.*")
;     (#lua-match? @injection.content "%s*DELETE.*")
;     (#lua-match? @injection.content "%s*DETACH DATABASE.*")
;     (#lua-match? @injection.content "%s*DROP INDEX.*")
;     (#lua-match? @injection.content "%s*DROP TABLE.*")
;     (#lua-match? @injection.content "%s*DROP TRIGGER.*")
;     (#lua-match? @injection.content "%s*DROP VIEW.*")
;     (#lua-match? @injection.content "%s*END TRANSACTION.*")
;     (#lua-match? @injection.content "%s*EXPLAIN.*")
;     (#lua-match? @injection.content "%s*INDEXED BY.*")
;     (#lua-match? @injection.content "%s*INSERT.*")
;     (#lua-match? @injection.content "%s*ON CONFLICT.*")
;     (#lua-match? @injection.content "%s*PRAGMA.*")
;     (#lua-match? @injection.content "%s*REINDEX.*")
;     (#lua-match? @injection.content "%s*RELEASE SAVEPOINT.*")
;     (#lua-match? @injection.content "%s*REPLACE.*")
;     (#lua-match? @injection.content "%s*RETURNING.*")
;     (#lua-match? @injection.content "%s*ROLLBACK TRANSACTION.*")
;     (#lua-match? @injection.content "%s*SAVEPOINT.*")
;     (#lua-match? @injection.content "%s*SELECT.*")
;     (#lua-match? @injection.content "%s*UPDATE.*")
;     (#lua-match? @injection.content "%s*UPSERT.*")
;     (#lua-match? @injection.content "%s*VACUUM.*")
;     (#lua-match? @injection.content "%s*WITH.*")
;   ]
;   (#set! injection.language "sql"))
;
; sql
(call
  function: (attribute
    (identifier) @_function)
  arguments: (argument_list
    (string
      (string_content) @injection.content @sql.wrapper)
    (#any-of? @_function "execute" "executemany" "executescript")
    (#match? @injection.content
      "\\c(alter table|analyze|attach database|begin transaction|commit transaction|create index|create table|create trigger|create view|create virtual table|delete|detach database|drop index|drop table|drop trigger|drop view|end transaction|explain|indexed by|insert|on conflict|pragma|reindex|release savepoint|replace|returning|rollback transaction|savepoint|select|update|upsert|vacuum|with)")
    (#set! injection.language "sql")))
