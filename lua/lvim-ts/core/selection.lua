-- lvim-ts: node-based incremental selection (opt-in).
-- `init_selection` starts a charwise visual selection at the node under the cursor;
-- `node_incremental` / `node_decremental` grow / shrink it by treesitter node;
-- `scope_incremental` grows to the nearest multi-line ancestor. A per-window node
-- stack records the history so shrinking pops back. Pure built-in vim.treesitter.
--
---@module "lvim-ts.core.selection"

local config = require("lvim-ts.config")

local M = {}

---@type table<integer, TSNode[]>  window id -> node stack (innermost first .. outermost last)
local stacks = {}

--- Visually select a node's range (charwise). Treesitter ranges are 0-based with an
--- EXCLUSIVE end column; a range that ends at column 0 actually ends on the line above.
---@param node TSNode
local function select_node(node)
    local sr, sc, er, ec = node:range()
    if ec == 0 and er > 0 then
        er = er - 1
        ec = #(vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or "")
    end
    -- Leave any active visual selection first, so the `v` below always starts a FRESH one.
    -- Re-running `v` while already in visual mode TOGGLES it off, dropping to normal mode — then
    -- the next grow/shrink key hits a NORMAL-mode mapping instead (e.g. Neovim's built-in `grn`
    -- LSP-rename), which looks like "it replaced a symbol".
    if vim.fn.mode():find("[vV\22]") then
        vim.cmd("normal! \27")
    end
    vim.fn.setpos(".", { 0, sr + 1, sc + 1, 0 })
    vim.cmd("normal! v")
    vim.fn.setpos(".", { 0, er + 1, math.max(ec, 1), 0 })
end

--- Start a selection at the named node under the cursor.
---@return nil
function M.init()
    local ok, node = pcall(vim.treesitter.get_node)
    if not ok or not node then
        return
    end
    stacks[vim.api.nvim_get_current_win()] = { node }
    select_node(node)
end

--- Grow the selection to the parent node, or (scope) to the nearest multi-line ancestor.
---@param scope? boolean
---@return nil
function M.grow(scope)
    local win = vim.api.nvim_get_current_win()
    local stack = stacks[win]
    if not stack or #stack == 0 then
        return M.init()
    end
    local parent = stack[#stack]:parent()
    if scope then
        while parent do
            local sr, _, er = parent:range()
            if er > sr then
                break
            end
            parent = parent:parent()
        end
    end
    if not parent then
        return select_node(stack[#stack])
    end
    stack[#stack + 1] = parent
    select_node(parent)
end

--- Shrink the selection back to the previous node.
---@return nil
function M.shrink()
    local stack = stacks[vim.api.nvim_get_current_win()]
    if not stack or #stack <= 1 then
        return
    end
    stack[#stack] = nil
    select_node(stack[#stack])
end

--- Install the buffer-local incremental-selection keymaps (idempotent per buffer).
---@param buf integer
---@return nil
function M.attach(buf)
    if vim.b[buf].lvim_ts_selection then
        return
    end
    vim.b[buf].lvim_ts_selection = true
    local km = config.incremental_selection.keymaps or {}
    local function map(mode, lhs, fn, desc)
        if lhs and lhs ~= "" then
            vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, desc = desc })
        end
    end
    map("n", km.init_selection, M.init, "lvim-ts: init selection")
    map("x", km.node_incremental, function()
        M.grow(false)
    end, "lvim-ts: grow node")
    map("x", km.node_decremental, M.shrink, "lvim-ts: shrink node")
    map("x", km.scope_incremental, function()
        M.grow(true)
    end, "lvim-ts: grow scope")
end

return M
