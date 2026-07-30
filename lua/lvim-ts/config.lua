-- lvim-ts: the live configuration table.
-- Holds the defaults; setup() merges user overrides into it in place, so every
-- require("lvim-ts.config") reader sees the effective values.
--
---@module "lvim-ts.config"

---@class LvimTsIncrementalSelection
---@field enable  boolean                  Enable node-based incremental selection
---@field keymaps { init_selection: string, node_incremental: string, node_decremental: string, scope_incremental: string }

---@class LvimTsTextObjects
---@field enable  boolean                       Enable generic node-type text objects
---@field types   table<string, string[]>       ancestor-by-type kind -> node types counting as it
---@field lists   table<string, string[]>       list-item kind -> list node types (select a child)
---@field keymaps table<string, string>         lhs -> "@<kind>.<inner|outer>" spec

---@class LvimTsFold
---@field expr       boolean               Own 'foldexpr'/'foldmethod' where the language ships a `folds` query
---@field text       boolean               Own 'foldtext': the collapsed line, still syntax-highlighted
---@field show_end   boolean               Append the fold's LAST line after the counter
---@field pad        string                Written after the collapsed line, before the rule
---@field fill       string|false          The rule character ('fillchars' `fold`); false leaves it alone
---@field counter    string                `string.format` pattern for the collapsed line count
---@field left       string                glyphs before the counter
---@field right      string                glyphs after the counter
---@field highlights { icon: string, counter: string, fallback: string }  group NAMES, if you paint them yourself

---@class LvimTsConfig
---@field auto_install     boolean          Install a missing parser automatically on first open
---@field ensure_installed string[]|"all"   Parsers to install at setup; "all" = every available one
---@field ignore_install   string[]         When ensure_installed = "all", parsers to exclude
---@field fold             LvimTsFold       Treesitter folding: the expression, the collapsed line, its parts
---@field colors           LvimTsColors     Palette accents this plugin's own highlight groups derive from
---@field max_filesize     integer          Skip treesitter above this many bytes (0 = no limit)
---@field language_map     table<string, string>  filetype -> parser language overrides
---@field update_outdated  boolean          At setup, update installed parsers behind the registry
---@field incremental_selection LvimTsIncrementalSelection
---@field textobjects      LvimTsTextObjects

---@class LvimTsColor
---@field accent string             a palette KEY ("blue", "yellow", …) or a literal "#rrggbb"
---@field tint   string|number|nil  a role from the shared tint scale, or a raw 0..1 factor
---@field bold   boolean|nil

---@class LvimTsColors
---@field fold_icon    LvimTsColor  the bracket glyphs around the counter
---@field fold_counter LvimTsColor  the "+N lines" counter
---@field fold_fill    LvimTsColor  the stretches of the folded line no capture covers
---@field fold_line    LvimTsColor|false  the rule drawn to the window edge (the editor's `Folded`)

---@type LvimTsConfig
return {
    auto_install = true,
    ensure_installed = {},
    ignore_install = {},
    -- TREESITTER FOLDING. `expr` changes how the buffer folds, so it stays off unless asked for;
    -- `text` only changes how an ALREADY folded line is drawn, and is worth having whenever the
    -- fold expression comes from treesitter at all — it re-runs the `highlights` query over the
    -- fold's first (and last) line, so a collapsed fold keeps the colours it had open instead of
    -- collapsing to one flat `Folded`.
    fold = {
        expr = false,
        text = true,
        show_end = true,
        -- The gap between the collapsed line and the rule drawn to the window edge, so the text
        -- does not touch it — the mirror of the space the left glyph already carries.
        pad = " ",
        -- THE RULE ITSELF. Neovim draws it from 'fillchars' `fold`, whose default is a middle dot
        -- repeated to the edge; owning the whole collapsed line means owning its character too,
        -- rather than leaving half of the look in the host's options. `false` keeps whatever the
        -- editor already has.
        fill = "─",
        counter = "+%d lines",
        left = " ─┤ ",
        right = " ├─ ",
        -- The groups the collapsed line paints with. They are this plugin's OWN (built from the
        -- live palette in highlights.lua, so they follow the theme) — name someone else's here
        -- only if you want the fold line to borrow another plugin's colours.
        highlights = {
            icon = "LvimTsFoldIcon",
            counter = "LvimTsFoldCounter",
            fallback = "LvimTsFoldFill",
        },
    },
    -- THE PALETTE ACCENTS this plugin's own groups derive from (highlights.lua builds them and
    -- rebinds on ColorScheme, so they follow the theme). Accents are palette KEYS, never hexes;
    -- `tint` names a role in the shared lvim-utils tint scale, which quiets the accent toward the
    -- editor background instead of shouting at full saturation.
    colors = {
        -- The brackets framing the counter: the same blue the set uses for chrome. NO tint — the
        -- shared scale blends toward the editor BACKGROUND, which is right for a wash and wrong for
        -- a glyph (measured: `separator` put the brackets at #273238, a shade off the background).
        fold_icon = { accent = "blue" },
        -- The counter itself — yellow, so the one piece of INFORMATION on the line is what the eye
        -- lands on, and it is never mistaken for code.
        fold_counter = { accent = "yellow", bold = true },
        -- What no capture covers: comment-grey, the same shade the editor uses for text that is
        -- present but not the point.
        fold_fill = { accent = "comment" },
        -- THE RULE Neovim draws from the collapsed line to the window edge ('fillchars' `fold`).
        -- That stretch is painted with the editor's own `Folded`, not with anything this plugin
        -- emits, so matching the brackets means owning that group — set this to `false` to leave
        -- `Folded` exactly as the colorscheme defines it.
        fold_line = { accent = "blue" },
    },
    -- Skip treesitter (highlight / indent / fold) on files larger than this, to avoid lag on
    -- huge buffers. 0 disables the guard. Default 1 MiB.
    max_filesize = 1024 * 1024,
    -- Override the parser language for a filetype, e.g. { ["html.handlebars"] = "glimmer" }.
    language_map = {},
    -- Update installed parsers that are behind the registry on setup (one pass; off by default
    -- as it can hit the network and recompile).
    update_outdated = false,
    -- Node-based incremental selection (off by default — it installs visual/normal keymaps).
    incremental_selection = {
        enable = false,
        keymaps = {
            init_selection = "gnn",
            node_incremental = "grn",
            node_decremental = "grm",
            scope_incremental = "grc",
        },
    },
    -- Generic node-type text objects (off by default — installs operator-pending/visual keymaps).
    -- `types` maps a logical kind to the node types counting as it (extend per language); the
    -- defaults cover the common grammars (go / lua / python / js-ts / rust / c-cpp …). The `inner`
    -- range is derived from the node's `body` field / named children — a best-effort generic stand-in
    -- for a `textobjects.scm` query (which would be parser data, owned by lvim-pkg, not lvim-ts).
    -- Block kinds are intentionally NOT mapped by default: vim already has `ib`/`ab` (parens) and
    -- `iB`/`aB` (`{}`); map `block` yourself if you want a treesitter-scoped variant.
    textobjects = {
        enable = false,
        types = {
            ["function"] = {
                "function_declaration",
                "function_definition",
                "function_literal",
                "method_declaration",
                "method_definition",
                "arrow_function",
                "local_function",
            },
            class = {
                "class_declaration",
                "class_definition",
                "class_specifier",
                "struct_type",
                "struct_specifier",
                "type_declaration",
                "interface_declaration",
                "impl_item",
            },
            block = {
                "block",
                "statement_block",
                "compound_statement",
                "table_constructor",
            },
        },
        -- List-item kinds: a single parameter/argument is the named child of one of these
        -- list nodes. Needed because many grammars do NOT wrap each item in its own node —
        -- lua/js leave it a bare identifier/expression directly in the list, so a type match
        -- finds nothing; matching "child of a list" works uniformly (incl. go's parameter_declaration).
        lists = {
            parameter = {
                "parameters",
                "parameter_list",
                "formal_parameters",
                "arguments",
                "argument_list",
                "parenthesized_expression",
            },
        },
        keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["ac"] = "@class.outer",
            ["ic"] = "@class.inner",
            ["aa"] = "@parameter.outer",
            ["ia"] = "@parameter.inner",
        },
    },
}
