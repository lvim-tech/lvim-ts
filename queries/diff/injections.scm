;; extends

; Inject each file's OWN language into its hunks, so a multi-file unified diff highlights every file with
; its real parser instead of rendering as flat text. The language is INFERRED from the diff's `+++ b/<path>`
; header (`injection.filename` → `vim.filetype.match`), which is what makes this work for any language
; without a hardcoded extension table.
;
; `injection.include-children` is REQUIRED, not decoration: `changes` has one named child per line
; (`context`/`addition`/`deletion`), and nvim MASKS OUT a content node's named children unless it is set
; (`get_node_ranges` in runtime/lua/vim/treesitter/languagetree.lua). Without it the injected region is
; whatever is left BETWEEN the children — nothing — so the language is injected with an EMPTY range and
; not one byte is highlighted, while `:InspectTree`/`for_each_tree` still cheerfully report "diff, lua".
;
; Note: `changes` carries the leading +/-/space markers, so an ADDED/REMOVED line's first token is scanned
; with the marker glued to it. Context lines are exact; the marker lines are covered by the diff-level
; add/delete highlighting drawn over them. This is the measured best of the options: per-LINE content
; captures (offset past the marker) would name that first token correctly, but injected ranges exclude the
; line endings, so multi-range regions glue every line into one (a `--` comment then eats the rest of the
; hunk) and one-tree-per-line loses all cross-line context. Against a ground truth (each hunk stripped of
; markers and parsed as pure lua) this form agrees on 96.5% of coloured cells vs 95.2% for per-line, with
; 28 injected trees instead of 458.
(block
  (new_file
    (filename) @injection.filename)
  (hunks
    (hunk
      (changes) @injection.content
      (#set! injection.include-children))))
