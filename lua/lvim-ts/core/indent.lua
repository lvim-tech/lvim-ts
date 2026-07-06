-- lvim-ts: query-based treesitter indentation.
-- Neovim core ships highlight / fold / select for treesitter but NO indent engine.
-- This is a focused consumer of the installed indents.scm queries (the @indent.*
-- captures), exposed as an 'indentexpr'. It is deliberately conservative: it returns
-- -1 ("keep the current indent") whenever it is unsure, so it never indents worse than
-- Neovim's filetype indent. Covers @indent.begin / branch / dedent / ignore / zero, and
-- @indent.align (aligns to the column after the open delimiter; the close delimiter row
-- de-aligns to the opener's indent), gated on the open/close delimiter metadata.
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
---@return table  capture name -> set of node ids; plus `align` -> id -> alignment info
local function collect(query, root, bufnr)
    local maps = { begins = {}, dedent = {}, branch = {}, ends = {}, ignore = {}, zero = {}, align = {} }
    -- iter_matches (not iter_captures): the `#set! indent.open_delimiter` directives that drive
    -- @indent.align are MATCH-level metadata, which iter_captures does not expose.
    for _, match, meta in query:iter_matches(root, bufnr, 0, -1) do
        for id, nodes in pairs(match) do
            local cap = query.captures[id]
            local key = CAPTURE[cap]
            for _, node in ipairs(nodes) do
                if key then
                    maps[key][node:id()] = true
                elseif cap == "indent.align" then
                    -- Align inner lines to just after the open delimiter on the node's first row.
                    -- All resolved to plain values now (no node kept): the alignment column, the
                    -- opener line's own indent (where a lone closer goes) and the close delimiter.
                    -- Gated on `indent.open_delimiter` so it only fires when the query opted in.
                    local sr, sc, er = node:range()
                    local open = meta["indent.open_delimiter"]
                    if type(open) == "string" and open ~= "" and er > sr then
                        local line = vim.api.nvim_buf_get_lines(bufnr, sr, sr + 1, false)[1] or ""
                        local at = line:find(open, sc + 1, true) -- 1-based position of the delimiter
                        if at then
                            local close = meta["indent.close_delimiter"]
                            maps.align[node:id()] = {
                                srow = sr,
                                erow = er,
                                col = at - 1 + #open,
                                open_indent = #(line:match("^%s*") or ""),
                                close = (type(close) == "string" and close ~= "") and close or nil,
                            }
                        end
                    end
                end
            end
        end
    end
    return maps
end

---@type table<integer, { tick: integer, lang: string, maps: table }>  per-buffer collect() cache
local cache = {}

vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("LvimTsIndent", { clear = true }),
    callback = function(args)
        cache[args.buf] = nil
    end,
})

--- collect() scans the whole tree (O(tree)) and runs on every indentexpr call (i.e. per line
--- during a `=` re-indent). The tree only changes when the buffer does, so cache the maps per
--- buffer keyed by 'changedtick': an indentexpr over an unchanged buffer (a re-indent of
--- already-clean lines, or several calls within one tick) reuses them instead of re-querying.
--- The maps hold node ids (integers), never node objects, so they keep no tree alive.
---@param bufnr integer
---@param lang string
---@param query vim.treesitter.Query
---@param root TSNode
---@return table  capture name -> set of node ids; plus `align` -> id -> alignment info
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
    local trees = parser:parse({ lnum - 1, lnum })
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

    local function get_line(n)
        return vim.api.nvim_buf_get_lines(bufnr, n - 1, n, false)[1] or ""
    end
    -- Pick the node at the line's OWN position: the first non-blank column for a real line, or
    -- column 0 for a blank/new line. The blank-line position lands in the block the new line will
    -- belong to — so a new line inside a body indents in (`function () … end`), while a new line
    -- after a closed block lands in the OUTER scope and is not indented (the "extra indent after
    -- }"). descendant_for_range (not named_) keeps anonymous closers (`end` / `}` / `)`, which
    -- carry @indent.branch/@indent.end) in the walk.
    local line = get_line(lnum)
    local col = line:match("^%s*$") and 0 or #(line:match("^%s*") or "")
    local node = root:descendant_for_range(lnum - 1, col, lnum - 1, col)
    if not node then
        return -1
    end

    local sw = vim.fn.shiftwidth()
    local levels = 0 -- @indent.begin levels above the line
    local dedents = 0 -- @indent.branch/@indent.dedent on the line itself
    local counted = {} -- start rows already credited (avoid double-counting per row)
    local align_col = nil -- @indent.align: absolute column for lines inside an aligned node
    local saw_capture = false

    local row = lnum - 1 -- 0-based target row

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
            saw_capture = true
            break -- stop accumulating opener levels above an ignored node
        end
        -- @indent.align: the innermost aligned ancestor wins. Inner rows align to just after the
        -- open delimiter; the closer row is handled specially (below). Outside an aligned node
        -- this never fires, so non-aligned languages keep the level-based indent unchanged.
        if not align_col and maps.align[id] then
            local a = maps.align[id] ---@type { srow: integer, erow: integer, col: integer, open_indent: integer, close: string? }
            if a.srow < row and row < a.erow then
                align_col = a.col
            elseif row == a.erow then
                -- The closer row: a line that BEGINS with the close delimiter aligns to the
                -- opener's own indent; a line with content before the closer aligns like the rest.
                local lc = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
                local trimmed = lc:match("^%s*(.*)") or ""
                if a.close and trimmed:sub(1, #a.close) == a.close then
                    align_col = a.open_indent
                else
                    align_col = a.col
                end
            end
        end
        if maps.begins[id] and srow < row and not counted[srow] then
            saw_capture = true
            levels = levels + 1
            counted[srow] = true
        end
        -- A branch (else / elseif), an explicit dedent, or a closing token (@indent.end:
        -- end / } / ]) that sits on this line pulls one level back. Counted once per node.
        if (maps.branch[id] or maps.dedent[id] or maps.ends[id]) and srow == row then
            saw_capture = true
            dedents = dedents + 1
        end
        node = node:parent()
    end
    if align_col then
        return align_col
    end
    if not saw_capture then
        return -1
    end
    return math.max(0, (levels - dedents) * sw)
end

return M
