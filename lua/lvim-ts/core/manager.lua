-- lvim-ts: buffer-side treesitter runtime.
-- Resolves a buffer's language and turns on highlighting via Neovim's built-in
-- vim.treesitter (no nvim-treesitter). Parser availability/installation is delegated
-- to lvim-pkg, whose parser backend compiles parsers and installs their queries onto
-- the runtimepath, so vim.treesitter.start finds both natively.
--
---@module "lvim-ts.core.manager"

local config = require("lvim-ts.config")

local M = {}

---@type table<string, boolean>  Parsers with an install in flight (dedupe guard)
local installing = {}

--- The lvim-pkg data hub, or nil when it is unavailable.
---@return table|nil
local function pkg()
    local ok, mod = pcall(require, "lvim-pkg")
    return ok and mod or nil
end

--- Resolve the parser language for a buffer's filetype.
---@param buf integer  Buffer handle
---@return string|nil
function M.lang_for_buf(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return nil
    end
    local ft = vim.bo[buf].filetype
    if ft == "" then
        return nil
    end
    return vim.treesitter.language.get_lang(ft) or ft
end

--- Turn treesitter highlighting on for a buffer via the built-in engine.
--- (Reads the parser and queries/<lang> that lvim-pkg installed onto the rtp.)
---@param buf  integer  Buffer handle
---@param lang string   Resolved parser language
---@return nil
function M.enable(buf, lang)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    pcall(vim.treesitter.start, buf, lang)
    -- Query-based ts indent (only when the language ships indents.scm). The indentexpr
    -- itself returns -1 (keep current indent) whenever it is unsure, so it never
    -- regresses below Neovim's filetype indent.
    if vim.treesitter.query.get(lang, "indents") then
        vim.bo[buf].indentexpr = "v:lua.require'lvim-ts.core.indent'.indentexpr()"
    end
end

--- Is `lang` one of the parsers lvim-pkg can install?
---@param p table    lvim-pkg handle
---@param lang string
---@return boolean
local function is_available(p, lang)
    for _, candidate in ipairs(p.available("parser")) do
        if candidate == lang then
            return true
        end
    end
    return false
end

--- On-demand activation for a buffer: resolve the language, install the parser
--- the first time it is seen (when auto_install is on, via lvim-pkg), then enable
--- treesitter.
---@param buf integer  Buffer handle
---@return nil
function M.activate(buf)
    local lang = M.lang_for_buf(buf)
    if not lang then
        return
    end
    local p = pkg()
    if not p then
        return
    end
    if p.is_installed("parser", lang) then
        -- Migration: a parser compiled by the old nvim-treesitter may have no queries in
        -- our dir. Fetch them once before enabling so highlighting actually works.
        local backend = p.backend("parser")
        if backend and backend.has_queries and not backend.has_queries(lang) and not installing[lang] then
            installing[lang] = true
            backend.install_queries(lang, function()
                installing[lang] = nil
                M.enable(buf, lang)
            end)
        else
            M.enable(buf, lang)
        end
        return
    end
    if not config.auto_install or installing[lang] or not is_available(p, lang) then
        return
    end
    installing[lang] = true
    p.install("parser", { lang }, function(err)
        installing[lang] = nil
        if not err then
            M.enable(buf, lang)
        end
    end)
end

return M
