-- lvim-ts: query-based treesitter indentation.
-- Neovim core ships highlight / fold / select for treesitter but NO indent engine.
-- This is a focused consumer of the installed indents.scm queries (the @indent.*
-- captures), exposed as an 'indentexpr'. It is deliberately conservative: it returns
-- -1 ("keep the current indent") whenever it is unsure, so it never indents worse than
-- Neovim's filetype indent. Covers @indent.begin / branch / dedent / ignore / zero;
-- @indent.align is left to the -1 fallback.
--
---@module "lvim-ts.core.indent"

local M = {}

local CAPTURE = {
    ["indent.begin"] = "begins",
    ["indent.dedent"] = "dedent",
    ["indent.branch"] = "branch",
    ["indent.end"] = "ends",
    ["indent.ignore"] = "ignore",
    ["indent.zero"] = "zero",
}

--- Map every relevant capture to the set of node ids it tags, over the whole tree.
---@param query vim.treesitter.Query
---@param root TSNode
---@param bufnr integer
---@return table<string, table<integer, boolean>>
local function collect(query, root, bufnr)
    local maps = { begins = {}, dedent = {}, branch = {}, ends = {}, ignore = {}, zero = {} }
    for id, node in query:iter_captures(root, bufnr) do
        local key = CAPTURE[query.captures[id]]
        if key then
            maps[key][node:id()] = true
        end
    end
    return maps
end

---@type table<integer, { tick: integer, lang: string, maps: table }>  per-buffer collect() cache
local cache = {}

--- collect() scans the whole tree (O(tree)) and runs on every indentexpr call (i.e. per line
--- during a `=` re-indent). The tree only changes when the buffer does, so cache the maps per
--- buffer keyed by 'changedtick': an indentexpr over an unchanged buffer (a re-indent of
--- already-clean lines, or several calls within one tick) reuses them instead of re-querying.
--- The maps hold node ids (integers), never node objects, so they keep no tree alive.
---@param bufnr integer
---@param lang string
---@param query vim.treesitter.Query
---@param root TSNode
---@return table<string, table<integer, boolean>>
local function maps_for(bufnr, lang, query, root)
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local c = cache[bufnr]
    if c and c.tick == tick and c.lang == lang then
        return c.maps
    end
    local maps = collect(query, root, bufnr)
    cache[bufnr] = { tick = tick, lang = lang, maps = maps }
    return maps
end

--- Compute the indent (in spaces) for 1-based `lnum`, or -1 to keep the current indent.
---@param lnum? integer
---@return integer
function M.indentexpr(lnum)
    lnum = lnum or vim.v.lnum
    local bufnr = vim.api.nvim_get_current_buf()
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return -1
    end
    local trees = parser:parse(true)
    local tree = trees and trees[1]
    if not tree then
        return -1
    end
    local lang = parser:lang()
    local query = vim.treesitter.query.get(lang, "indents")
    if not query then
        return -1
    end
    local root = tree:root()
    local maps = maps_for(bufnr, lang, query, root)

    -- Pick the starting node. For a blank line (the common "pressed Enter after a block
    -- opener" case) use the last node of the previous non-blank line, so the opener still
    -- contributes its indent; otherwise the node under the first non-blank column.
    local function get_line(n)
        return vim.api.nvim_buf_get_lines(bufnr, n - 1, n, false)[1] or ""
    end
    local node
    local line = get_line(lnum)
    if line:match("^%s*$") then
        local p = lnum - 1
        while p >= 1 and get_line(p):match("^%s*$") do
            p = p - 1
        end
        if p < 1 then
            return 0
        end
        local plen = #get_line(p)
        node = root:descendant_for_range(p - 1, math.max(0, plen - 1), p - 1, math.max(0, plen - 1))
    else
        -- descendant_for_range (not named_) so anonymous closers like `end` / `}` / `)`
        -- — which carry @indent.branch/@indent.end — are part of the walk.
        local col = #(line:match("^%s*") or "")
        node = root:descendant_for_range(lnum - 1, col, lnum - 1, col)
    end
    if not node then
        return -1
    end

    local sw = vim.fn.shiftwidth()
    local levels = 0 -- @indent.begin levels above the line
    local dedents = 0 -- @indent.branch/@indent.dedent on the line itself
    local counted = {} -- start rows already credited (avoid double-counting per row)

    -- The walk is bottom-up, so begins and dedents are tallied separately and combined
    -- at the end (a branch like `else` must cancel its opener's level, regardless of the
    -- order they are visited).
    while node do
        local srow = node:start()
        local id = node:id()
        if maps.zero[id] then
            return 0
        end
        if maps.ignore[id] then
            break -- stop accumulating opener levels above an ignored node
        end
        if maps.begins[id] and srow < (lnum - 1) and not counted[srow] then
            levels = levels + 1
            counted[srow] = true
        end
        -- A branch (else / elseif), an explicit dedent, or a closing token (@indent.end:
        -- end / } / ]) that sits on this line pulls one level back. Counted once per node.
        if (maps.branch[id] or maps.dedent[id] or maps.ends[id]) and srow == (lnum - 1) then
            dedents = dedents + 1
        end
        node = node:parent()
    end
    return math.max(0, (levels - dedents) * sw)
end

return M
