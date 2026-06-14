-- lvim-ts: :checkhealth lvim-ts
--
-- Checks the pieces the buffer-side treesitter runtime needs: built-in
-- vim.treesitter, the lvim-pkg engine (which compiles parsers and installs
-- their queries), the parser compile toolchain (cc + tree-sitter CLI) and the
-- config shape. Parser availability/installation itself is lvim-pkg's concern
-- (see :checkhealth lvim-pkg).
--
---@module "lvim-ts.health"

local config = require("lvim-ts.config")

local M = {}

function M.check()
    local h = vim.health
    h.start("lvim-ts")

    -- ── core ──────────────────────────────────────────────────────────────────
    if vim.fn.has("nvim-0.10") == 1 and type(vim.treesitter) == "table" and vim.treesitter.start then
        h.ok("built-in vim.treesitter available (no nvim-treesitter)")
    else
        h.error("Neovim >= 0.10 with built-in vim.treesitter is required")
    end

    local ok_pkg, pkg = pcall(require, "lvim-pkg")
    if ok_pkg and type(pkg.install) == "function" then
        h.ok("lvim-pkg found (parser availability + compilation)")
    else
        h.error("lvim-pkg not found — required: it compiles parsers and installs their queries")
    end

    -- ── parser compile toolchain (used by lvim-pkg's parser backend) ──────────
    if vim.fn.executable("cc") == 1 then
        h.ok("cc — compiles a grammar's parser.c into a .so")
    else
        h.warn("cc missing — parsers cannot be compiled (install a C compiler)")
    end
    if vim.fn.executable("tree-sitter") == 1 then
        h.ok("tree-sitter CLI — generates parser.c for grammars that ship only grammar.js")
    else
        h.info("tree-sitter CLI not on PATH — lvim-pkg installs it on demand (ensure_cli)")
    end

    -- ── config ────────────────────────────────────────────────────────────────
    local ei = config.ensure_installed
    local ei_ok = ei == "all" or type(ei) == "table"
    if type(config.auto_install) == "boolean" and ei_ok and type(config.ignore_install) == "table" then
        local ei_desc = ei == "all" and '"all"' or (#ei .. " parser(s)")
        h.ok(("config: auto_install=%s  ensure_installed=%s"):format(tostring(config.auto_install), ei_desc))
    else
        h.warn('config: expected auto_install:boolean, ensure_installed:string[]|"all", ignore_install:string[]')
    end

    -- ── installed parsers (built by lvim-pkg, discovered on the runtimepath) ───
    if ok_pkg then
        local installed = pkg.installed("parser") or {}
        if #installed > 0 then
            h.info(("%d parser(s) installed: %s"):format(#installed, table.concat(installed, ", ")))
        else
            h.info("no parsers installed yet (installed on first open / via ensure_installed)")
        end
    end
end

return M
