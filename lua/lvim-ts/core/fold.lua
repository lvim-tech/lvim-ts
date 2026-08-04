-- lvim-ts.core.fold: the collapsed fold line, still syntax-highlighted.
--
-- Neovim's own 'foldtext' draws the fold's first line as ONE flat `Folded` run: a collapsed
-- function loses every colour it had while open, which is exactly when the colour is worth most —
-- the line is all you are given to recognise what is inside. This re-runs the language's
-- `highlights` query over that line and hands 'foldtext' the per-capture chunks instead.
--
-- WHY IT LIVES HERE. Nine tenths of the work is treesitter: resolve the parser, get the query,
-- iterate the captures of one row, merge the ranges that nest, order them by priority. That is this
-- plugin's subject, and it already owns the parser lifecycle and the language resolution the lookup
-- needs. It was a `_G.fold_text` global in a host config before, wired by name through
-- `foldtext = "v:lua.fold_text()"`.
--
-- Everything drawn between the two lines — the glyphs, the counter, the highlight groups — comes
-- from `config.fold`, so a distribution restyles the collapsed line without touching this file.
--
---@module "lvim-ts.core.fold"

local config = require("lvim-ts.config")

local api = vim.api

local M = {}

--- The syntax-highlighted chunks of ONE buffer line, as 'foldtext' wants them: `{ text, group }`.
---
--- Overlapping captures are the reason this is not a plain loop. A `@function` capture can contain
--- a `@function.call`, and the inner one must win the pixels it covers while the outer still paints
--- what is left. So an enclosing range hands its groups DOWN to the ranges nested inside it and
--- then drops out, and each surviving chunk lists its groups by priority.
---@param linenr integer  1-based line
--- The `#` matters: without it the comma after the return NAME reads as a second return value,
--- and every `return` in this function is then short one value.
---@return table[]|nil chunks # nil when the line cannot be highlighted (no parser, no query)
local function parse_line(linenr)
    local buf = api.nvim_get_current_buf()
    local line = api.nvim_buf_get_lines(buf, linenr - 1, linenr, false)[1]
    if not line then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then
        return nil
    end

    local query = vim.treesitter.query.get(parser:lang(), "highlights")
    if not query then
        return nil
    end

    local tree = parser:parse({ linenr - 1, linenr })[1]
    if not tree then
        return nil
    end

    local fallback = config.fold.highlights.fallback
    local default_priority = vim.hl.priorities.treesitter

    local result = {}
    local pos = 0

    for id, node, metadata in query:iter_captures(tree:root(), 0, linenr - 1, linenr) do
        local name = query.captures[id]
        local start_row, start_col, end_row, end_col = node:range()
        local priority = tonumber(metadata.priority or default_priority)
        -- Multi-line captures are skipped: only what this row actually shows is drawn.
        if start_row == linenr - 1 and end_row == linenr - 1 then
            if start_col > pos then
                result[#result + 1] = {
                    line:sub(pos + 1, start_col),
                    { { fallback, priority } },
                    range = { pos, start_col },
                }
            end
            pos = end_col
            result[#result + 1] = {
                line:sub(start_col + 1, end_col),
                { { "@" .. name, priority } },
                range = { start_col, end_col },
            }
        end
    end

    local i = 1
    while i <= #result do
        local j = i + 1
        while j <= #result and result[j].range[1] >= result[i].range[1] and result[j].range[2] <= result[i].range[2] do
            for k, v in ipairs(result[i][2]) do
                if not vim.tbl_contains(result[j][2], v) then
                    table.insert(result[j][2], k, v)
                end
            end
            j = j + 1
        end
        if j > i + 1 then
            -- Fully covered by the ranges nested inside it: its groups have been handed down.
            table.remove(result, i)
        else
            if #result[i][2] > 1 then
                table.sort(result[i][2], function(a, b)
                    return a[2] < b[2]
                end)
            end
            result[i][2] = vim.tbl_map(function(pair)
                return pair[1]
            end, result[i][2])
            result[i] = { result[i][1], result[i][2] }
            i = i + 1
        end
    end

    return result
end

--- The 'foldtext' body: the fold's first line highlighted, the configured counter, and — when
--- `fold.show_end` is on — its last line, so a collapsed block still shows how it closes.
--- Falls back to Neovim's own fold text whenever the line cannot be highlighted, so a buffer with
--- no parser is never left with an empty fold line.
---@return table[]|string
function M.text()
    local fold = config.fold
    local result = parse_line(vim.v.foldstart)
    if not result then
        return vim.fn.foldtext()
    end

    local hl = fold.highlights
    result[#result + 1] = { fold.left, hl.icon }
    result[#result + 1] = { fold.counter:format(vim.v.foldend - vim.v.foldstart), hl.counter }
    result[#result + 1] = { fold.right, hl.icon }

    if fold.show_end then
        local tail = parse_line(vim.v.foldend)
        if tail and tail[1] then
            -- The closing line keeps its own highlights but loses its indent: it is being pulled up
            -- next to the counter, where leading whitespace would read as a gap, not as structure.
            tail[1] = { vim.trim(tail[1][1]), tail[1][2] }
            for _, chunk in ipairs(tail) do
                result[#result + 1] = chunk
            end
        end
    end

    -- The gap before Neovim's own rule. It is drawn in the fill group rather than left bare so the
    -- space carries the same background as the rest of the line.
    if fold.pad and fold.pad ~= "" then
        result[#result + 1] = { fold.pad, hl.fallback }
    end

    return result
end

--- Own 'foldtext' — or hand it back. The previous value is remembered on the first enable, so
--- turning the collapsed line off restores whatever the editor had (Neovim's default, or a host's
--- own renderer) instead of guessing at it.
---@type string|nil
local previous = nil

--- Turn the highlighted fold line on or off at runtime. `setup()` calls this with `config.fold.text`;
--- everything else is the user's own switch.
---@param on boolean
---@return nil
function M.enable(on)
    if on then
        if previous == nil then
            previous = vim.o.foldtext
        end
        vim.o.foldtext = "v:lua.require'lvim-ts.core.fold'.text()"
        -- The rule's CHARACTER, alongside its colour: the collapsed line is one thing, and half of
        -- it living in a host's 'fillchars' is how it ends up mismatched. Only this key is touched
        -- — every other fill character the host set stays exactly as it is.
        if config.fold.fill then
            vim.opt.fillchars:append({ fold = config.fold.fill })
        end
    elseif previous ~= nil then
        vim.o.foldtext = previous
        previous = nil
    end
    config.fold.text = on and true or false
end

--- Flip it, and answer what it became.
---@return boolean  the new state
function M.toggle()
    local on = not (config.fold.text == true)
    M.enable(on)
    return on
end

--- Whether the highlighted fold line is currently ours.
---@return boolean
function M.enabled()
    return config.fold.text == true
end

-- ── The fold EXPRESSION ───────────────────────────────────────────────────────────────────────────

---@type table<integer, true>  buffers whose language folds through treesitter
local expr_buffers = {}

---@type integer|nil  the augroup that re-applies the options to windows opened later
local expr_group = nil

--- Put the treesitter fold options on one window, for one buffer.
---@param win integer
---@return nil
local function apply_expr(win)
    vim.wo[win][0].foldmethod = "expr"
    vim.wo[win][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
end

--- Fold this buffer through treesitter, in every window that shows it — now and later.
---
--- 'foldmethod' and 'foldexpr' are WINDOW options: setting them when the buffer attaches covers the
--- window it loaded in and nothing else, so a `:split` afterwards showed the same buffer with no
--- folds at all. The autocmd below closes that: the buffer is remembered, and every window it later
--- appears in gets the same pair. Registered once, and only when something actually folds.
---@param buf integer
---@return nil
function M.attach_expr(buf)
    expr_buffers[buf] = true
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        apply_expr(win)
    end
    if expr_group ~= nil then
        return
    end
    expr_group = api.nvim_create_augroup("LvimTsFoldExpr", { clear = true })
    api.nvim_create_autocmd("BufWinEnter", {
        group = expr_group,
        callback = function(args)
            if not expr_buffers[args.buf] then
                return
            end
            apply_expr(api.nvim_get_current_win())
        end,
    })
    api.nvim_create_autocmd("BufDelete", {
        group = expr_group,
        callback = function(args)
            expr_buffers[args.buf] = nil
        end,
    })
end

return M
