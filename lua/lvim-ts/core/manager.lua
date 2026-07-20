-- lvim-ts: buffer-side treesitter runtime.
-- Resolves a buffer's language and turns on highlighting via Neovim's built-in
-- vim.treesitter (no nvim-treesitter). Parser availability/installation is delegated
-- to lvim-pkg, whose parser backend compiles parsers and installs their queries onto
-- the runtimepath, so vim.treesitter.start finds both natively.
--
---@module "lvim-ts.core.manager"

local config = require("lvim-ts.config")
local selection = require("lvim-ts.core.selection")
local textobjects = require("lvim-ts.core.textobjects")

local M = {}

---@type table<string, integer[]>  Parsers with an install in flight (pending buffers to enable)
local installing = {}

--- The lvim-pkg data hub, or nil when it is unavailable.
---@return table|nil
local function pkg()
    local ok, mod = pcall(require, "lvim-pkg")
    return ok and mod or nil
end

--- Resolve the parser language for a buffer's filetype. A buffer-local `b:lvim_ts_lang`
--- set by the OWNING plugin wins over every filetype mapping — the self-registration seam
--- for buffers whose GRAMMAR is not their filetype (e.g. lvim-db's query editor: the ft
--- stays real `sql` so LSP/completion attach, but a MongoDB connection's statements are
--- extended-JSON, so it sets `lvim_ts_lang = "json"` and calls `require("lvim-ts").activate`).
---@param buf integer  Buffer handle
---@return string|nil
function M.lang_for_buf(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return nil
    end
    local override = vim.b[buf].lvim_ts_lang
    if type(override) == "string" and override ~= "" then
        return override
    end
    local ft = vim.bo[buf].filetype
    if ft == "" then
        return nil
    end
    return config.language_map[ft] or vim.treesitter.language.get_lang(ft) or ft
end

--- True when treesitter should be skipped for `buf` because the file exceeds
--- config.max_filesize (a guard against lag on very large buffers; 0 disables it).
--- Unsaved / nameless buffers (no file to stat) are never skipped.
---@param buf integer
---@return boolean
local function too_big(buf)
    local limit = config.max_filesize or 0
    if limit <= 0 then
        return false
    end
    local ok, stat = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
    return ok and stat ~= nil and stat.size > limit
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
    -- A LANGUAGE SWITCH (b:lvim_ts_lang changed, then a re-activate): stop the old
    -- highlighter first — vim.treesitter.start would otherwise leave the previous
    -- grammar's highlighter attached alongside the new one.
    local running = vim.treesitter.highlighter.active[buf]
    if running and running.tree and running.tree:lang() ~= lang then
        vim.treesitter.stop(buf)
    end
    if not pcall(vim.treesitter.start, buf, lang) then
        return
    end
    -- Query-based ts indent (only when the language ships indents.scm). The indentexpr
    -- itself returns -1 (keep current indent) whenever it is unsure, so it never
    -- regresses below Neovim's filetype indent.
    if vim.treesitter.query.get(lang, "indents") then
        vim.bo[buf].indentexpr = "v:lua.require'lvim-ts.core.indent'.indentexpr()"
    end
    -- Treesitter folding (opt-in) — set the window-local fold options on every window currently
    -- showing this buffer, when the language ships a `folds` query. New windows that open the
    -- buffer later inherit nothing here; this covers the common load-in-a-window case.
    if config.fold and vim.treesitter.query.get(lang, "folds") then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
            vim.wo[win][0].foldmethod = "expr"
            vim.wo[win][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        end
    end
    -- Node-based incremental selection keymaps (opt-in), scoped to this buffer.
    if config.incremental_selection and config.incremental_selection.enable then
        selection.attach(buf)
    end
    -- Generic node-type text-object keymaps (opt-in), scoped to this buffer.
    if config.textobjects and config.textobjects.enable then
        textobjects.attach(buf)
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
    if too_big(buf) then
        return -- skip treesitter entirely on oversized files
    end
    local p = pkg()
    if not p then
        return
    end
    if p.is_installed("parser", lang) then
        -- Migration: a parser compiled by the old nvim-treesitter may have no queries in
        -- our dir. Fetch them once before enabling so highlighting actually works.
        local backend = p.backend("parser")
        if backend and backend.has_queries and not backend.has_queries(lang) then
            if installing[lang] then
                installing[lang][#installing[lang] + 1] = buf
                return
            end
            installing[lang] = { buf }
            backend.install_queries(lang, function()
                local pending = installing[lang] or {}
                installing[lang] = nil
                for _, b in ipairs(pending) do
                    M.enable(b, lang)
                end
            end)
        else
            M.enable(buf, lang)
        end
        return
    end
    if not config.auto_install or not is_available(p, lang) then
        return
    end
    if installing[lang] then
        installing[lang][#installing[lang] + 1] = buf
        return
    end
    installing[lang] = { buf }
    p.install("parser", { lang }, function(err)
        local pending = installing[lang] or {}
        installing[lang] = nil
        if not err then
            for _, b in ipairs(pending) do
                M.enable(b, lang)
            end
        end
    end)
end

return M
