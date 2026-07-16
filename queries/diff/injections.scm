;; extends

; Inject each file's OWN language into its hunks, so a multi-file unified diff highlights every file with
; its real parser instead of rendering as flat text. The language is INFERRED from the diff's `+++ b/<path>`
; header (`injection.filename` → `vim.filetype.match`), which is what makes this work for any language
; without a hardcoded extension table.
;
; Note: `changes` carries the leading +/-/space markers, so an ADDED/REMOVED line's first token is scanned
; with the marker glued to it. Context lines are exact; the marker lines are covered by the diff-level
; add/delete highlighting drawn over them.
(block
  (new_file
    (filename) @injection.filename)
  (hunks
    (hunk
      (changes) @injection.content)))
