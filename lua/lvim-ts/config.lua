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

---@class LvimTsConfig
---@field auto_install     boolean          Install a missing parser automatically on first open
---@field ensure_installed string[]|"all"   Parsers to install at setup; "all" = every available one
---@field ignore_install   string[]         When ensure_installed = "all", parsers to exclude
---@field fold             boolean          Enable treesitter folding (foldexpr) when a `folds` query exists
---@field max_filesize     integer          Skip treesitter above this many bytes (0 = no limit)
---@field language_map     table<string, string>  filetype -> parser language overrides
---@field update_outdated  boolean          At setup, update installed parsers behind the registry
---@field incremental_selection LvimTsIncrementalSelection
---@field textobjects      LvimTsTextObjects

---@type LvimTsConfig
return {
    auto_install = true,
    ensure_installed = {},
    ignore_install = {},
    -- Treesitter folding (foldexpr) — off by default since it changes fold behaviour.
    fold = false,
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
