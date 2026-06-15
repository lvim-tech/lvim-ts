# lvim-ts

Buffer-side treesitter **runtime** built entirely on Neovim's **built-in
`vim.treesitter`** — **no nvim-treesitter**. On the first open of a filetype it
ensures the parser (and its queries) are installed via **lvim-pkg**, turns on
highlighting with `vim.treesitter.start`, and applies a query-based treesitter
indent (a consumer of the installed `indents.scm`, since Neovim core ships no
treesitter indent engine).

It owns no parser data and no install logic of its own — availability,
compilation and the unified install prompt all live in `lvim-pkg` /
`lvim-installer`. lvim-ts simply contributes a "this filetype needs parser X"
requirement to lvim-pkg and drives buffer activation.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-ts/blob/main/LICENSE)

## Installation

Requires only `lvim-pkg` — the parser backend there compiles parsers and installs
their queries onto the runtimepath, so the built-in `vim.treesitter` finds both.

### LVIM IDE

Ships with LVIM IDE. Override its options in your user module
(`lua/modules/user/init.lua`):

```lua
modules["lvim-tech/lvim-ts"] = {
    dependencies = { "lvim-tech/lvim-pkg" },
    opts = { auto_install = false }, -- offer parsers via lvim-installer's prompt
}
```

### lazy.nvim

```lua
return {
    "lvim-tech/lvim-ts",
    dependencies = { "lvim-tech/lvim-pkg" },
    config = function()
        require("lvim-ts").setup({ auto_install = true })
    end,
}
```

### Native (vim.pack / packadd)

```lua
-- In your init.lua, after the plugin is on the runtimepath:
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-pkg" },
    { src = "https://github.com/lvim-tech/lvim-ts" },
})

require("lvim-ts").setup({ auto_install = true })
```

### packer.nvim

```lua
use({
    "lvim-tech/lvim-ts",
    requires = { "lvim-tech/lvim-pkg" },
    config = function()
        require("lvim-ts").setup({ auto_install = true })
    end,
})
```

> With `lvim-installer` active, set `auto_install = false` so missing parsers are
> offered through the unified prompt instead of installing silently.

## Usage / Configuration

```lua
require("lvim-ts").setup({
    -- Install a missing parser automatically on first open (via lvim-pkg).
    auto_install = true,

    -- Parsers to install silently at setup. A list installs exactly those; the string
    -- "all" installs every available parser except `ignore_install`.
    ensure_installed = {}, -- e.g. { "lua", "go", "rust" }  or  "all"
    ignore_install = {}, -- excluded when ensure_installed = "all"

    fold = false, -- treesitter folding (foldexpr) when a `folds` query exists
    max_filesize = 1024 * 1024, -- skip treesitter above this many bytes (0 = no limit)
    language_map = {}, -- filetype -> parser overrides, e.g. { ["html.handlebars"] = "glimmer" }
    update_outdated = false, -- update installed parsers behind the registry, at setup

    -- Node-based incremental selection (off by default; installs visual/normal keymaps).
    incremental_selection = {
        enable = false,
        keymaps = {
            init_selection = "gnn", -- start a selection at the node under the cursor
            node_incremental = "grn", -- grow to the parent node
            node_decremental = "grm", -- shrink to the previous node
            scope_incremental = "grc", -- grow to the nearest multi-line ancestor
        },
    },

    -- Generic node-type text objects (off by default; installs operator-pending/visual keymaps).
    textobjects = {
        enable = false,
        keymaps = {
            ["af"] = "@function.outer", -- a function (incl. signature + body)
            ["if"] = "@function.inner", -- inner function (the body)
            ["ac"] = "@class.outer", -- a class / struct / type
            ["ic"] = "@class.inner", -- inner class
            ["aa"] = "@parameter.outer", -- a parameter / argument (+ its comma)
            ["ia"] = "@parameter.inner", -- inner parameter
        },
        -- types = { ["function"] = { ... }, class = { ... }, parameter = { ... }, block = { ... } }
        -- maps each logical kind to the node types counting as it; extend per language as needed.
    },
})
```

Beyond highlighting + indentation, lvim-ts can drive Neovim's built-in treesitter
**folding** (`fold = true`), node-based **incremental selection**, and syntax-aware
**text objects** (all opt-in), and guards against lag on huge files via `max_filesize`.

### Text objects

`textobjects.enable = true` installs operator-pending + visual keymaps for the things
vim's built-in bracket text objects (`ib`/`ab`, `iB`/`aB`, `i(`…) cannot express —
function / class / parameter — so e.g. `daf` deletes a whole function, `cif` changes its
body, `daa` removes a parameter (with its trailing comma) leaving a valid argument list.

It is deliberately **query-less**: the precise route — a parser's `textobjects.scm` query —
is parser **data**, which is `lvim-pkg` / the registry's domain, not lvim-ts's. Instead it
climbs to the nearest ancestor whose node **type** is configured for the kind (`function` /
`class`, the `types` map) — and for `parameter` finds the named child of an argument /
parameter **list** (the `lists` map), since many grammars (lua / js) don't wrap each item
in its own node. `inner` comes from the node's `body` field / named children; `outer` of a
parameter swallows the adjacent comma. `class` inner is best-effort across grammars;
`function` and `parameter` are precise. Block kinds are not mapped by default (vim has `ib`/`iB`).

## API

| Function | Description |
| --- | --- |
| `setup(opts)` | Register on-demand activation + the parser requirement provider. |
| `lang_for_buf(buf)` | Resolve a buffer's parser language. |
| `enable(buf, lang)` | Enable built-in highlighting + query-based indent for a buffer. |
| `missing_for_ft(ft)` | Parser a filetype needs but lacks, or `nil`. |

## Requirements

- Neovim with built-in `vim.treesitter` (no nvim-treesitter).
- `lvim-pkg` (parser compilation + query install; also bootstraps the tree-sitter CLI).

## Part of the LVIM ecosystem

- [lvim-pkg](https://github.com/lvim-tech/lvim-pkg) — the engine (parser availability + install)
- [lvim-installer](https://github.com/lvim-tech/lvim-installer) — the install UI / unified prompt
- [lvim-ls](https://github.com/lvim-tech/lvim-ls) — LSP engine
- [lvim-utils](https://github.com/lvim-tech/lvim-utils) — shared UI / notify
