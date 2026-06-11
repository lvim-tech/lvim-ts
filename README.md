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

## Installation

Requires only `lvim-pkg` — the parser backend there compiles parsers and installs
their queries onto the runtimepath, so the built-in `vim.treesitter` finds both.

### LVIM IDE

```lua
modules["lvim-tech/lvim-ts"] = {
  dependencies = { "lvim-tech/lvim-pkg" },
  opts = { auto_install = false },   -- offer parsers via lvim-installer's prompt
}
```

### Standalone (lazy.nvim)

```lua
{
  "lvim-tech/lvim-ts",
  dependencies = { "lvim-tech/lvim-pkg" },
  opts = { auto_install = true },
}
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
  ensure_installed = {},          -- e.g. { "lua", "go", "rust" }  or  "all"
  ignore_install   = {},          -- excluded when ensure_installed = "all"
})
```

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
