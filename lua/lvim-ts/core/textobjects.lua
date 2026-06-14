-- lvim-ts: generic node-type text objects (opt-in).
-- Syntax-aware text objects (`af`/`if` function, `ac`/`ic` class, `aa`/`ia` parameter)
-- for the operator-pending and visual modes — the things vim's built-in bracket text
-- objects (`ib`/`ab`, `iB`/`aB`, `i(`…) cannot express. Deliberately query-LESS: the
-- precise route (a `textobjects.scm` query) would be parser DATA, which is lvim-pkg /
-- the registry's domain, not ours. Instead this climbs to the nearest ancestor whose
-- node TYPE is configured for the kind (a config-level type map, no parser data), and
-- derives `inner` from the node's `body` field / named children. Pure vim.treesitter.
--
---@module "lvim-ts.core.textobjects"

local config = require("lvim-ts.config")

local M = {}

--- Visually select a charwise range (works in operator-pending AND visual mode: it
--- establishes a fresh `v` selection, which a pending operator then consumes). Treesitter
--- ranges are 0-based with an EXCLUSIVE end column, so a range ending at column 0 actually
--- ends on the line above; the 1-based end column lands on the last included character.
---@param sr integer  start row (0-based)
---@param sc integer  start col (0-based)
---@param er integer  end row (0-based, exclusive col)
---@param ec integer  end col (0-based, exclusive)
---@return nil
local function select_range(sr, sc, er, ec)
    if ec == 0 and er > sr then
        er = er - 1
        ec = #(vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or "")
    end
    -- Leave any active visual selection first so `v` always starts a FRESH one (re-running
    -- `v` while already visual TOGGLES it off, dropping to normal mode).
    if vim.fn.mode():find("[vV\22]") then
        vim.cmd("normal! \27")
    end
    vim.fn.setpos(".", { 0, sr + 1, sc + 1, 0 })
    vim.cmd("normal! v")
    vim.fn.setpos(".", { 0, er + 1, math.max(ec, 1), 0 })
end

--- The `inner` range of a structural node: descend into its `body` field when present
--- (so a function's inner is its block, a struct's its declaration list), then take the
--- span of that target's NAMED children — which strips the surrounding delimiters
--- (`{` … `}`, `function` … `end`). Falls back to the target's own range.
---@param node TSNode
---@return integer sr  start row (0-based)
---@return integer sc  start col (0-based)
---@return integer er  end row (0-based)
---@return integer ec  end col (0-based, exclusive)
local function inner_range(node)
    local body = node:field("body")
    local target = (body and body[1]) or node
    local first, last
    for i = 0, target:named_child_count() - 1 do
        local c = target:named_child(i)
        first = first or c
        last = c
    end
    if first then
        local sr, sc = first:start()
        local _, _, er, ec = last:range()
        return sr, sc, er, ec
    end
    return target:range()
end

--- The `outer` range of a node: its full range, extended to swallow an adjacent comma
--- separator when there is one (trailing preferred, else leading) so e.g. `daa` on a
--- parameter leaves a syntactically clean argument list.
---@param node TSNode
---@return integer sr  start row (0-based)
---@return integer sc  start col (0-based)
---@return integer er  end row (0-based)
---@return integer ec  end col (0-based, exclusive)
local function outer_range(node)
    local sr, sc, er, ec = node:range()
    local nxt = node:next_sibling()
    if nxt and not nxt:named() and nxt:type() == "," then
        -- Trailing comma: swallow it AND the whitespace up to the next item (its start is an
        -- exclusive end), so `daa` leaves no dangling ", " — falling back to the comma's own
        -- end when it is the last thing before the closer.
        local after = nxt:next_sibling()
        if after then
            er, ec = after:start()
        else
            _, _, er, ec = nxt:range()
        end
        return sr, sc, er, ec
    end
    -- No trailing comma (last item): swallow a leading comma instead, so the list stays valid.
    local prev = node:prev_sibling()
    if prev and not prev:named() and prev:type() == "," then
        sr, sc = prev:start()
    end
    return sr, sc, er, ec
end

--- Build a lookup set from a list of strings.
---@param list string[]?
---@return table<string, boolean>
local function to_set(list)
    local set = {}
    for _, t in ipairs(list or {}) do
        set[t] = true
    end
    return set
end

--- Find the target node for a `types` (ancestor-by-type) kind: the nearest ancestor
--- whose node type is configured for the kind (function / class / block).
---@param node TSNode
---@param kind string
---@return TSNode?
local function by_type(node, kind)
    local set = to_set(config.textobjects.types[kind])
    while node and not set[node:type()] do
        node = node:parent()
    end
    return node
end

--- Find the target node for a `lists` (list-item) kind: the innermost NAMED node whose
--- PARENT is one of the configured list nodes (parameter_list / arguments / parameters …).
--- This is how a single parameter / argument is selected uniformly across grammars —
--- many wrap each item in its own node (go `parameter_declaration`), but others leave it
--- a bare child of the list (lua / js: an `identifier` / expression directly in the list).
---@param node TSNode
---@param kind string
---@return TSNode?
local function by_list_item(node, kind)
    local set = to_set(config.textobjects.lists[kind])
    while node do
        local parent = node:parent()
        if parent and set[parent:type()] and node:named() then
            return node
        end
        node = parent
    end
    return nil
end

--- Select the text object identified by an "@<kind>.<inner|outer>" spec. `lists` kinds
--- (parameter) use the list-item search; `types` kinds (function / class) climb to the
--- nearest ancestor of a configured type. A no-op when nothing matches, so the key just
--- does nothing rather than misbehaving.
---@param spec string  e.g. "@function.outer", "@parameter.inner"
---@return nil
function M.select(spec)
    local kind, part = spec:match("^@(%a+)%.(%a+)$")
    if not kind then
        return
    end
    local ok, node = pcall(vim.treesitter.get_node)
    if not ok or not node then
        return
    end
    local target
    if config.textobjects.lists[kind] then
        target = by_list_item(node, kind)
    elseif config.textobjects.types[kind] then
        target = by_type(node, kind)
    end
    if not target then
        return
    end
    if part == "inner" then
        select_range(inner_range(target))
    else
        select_range(outer_range(target))
    end
end

--- Install the buffer-local text-object keymaps (idempotent per buffer). Mapped in
--- operator-pending + visual modes only, so they never affect normal-mode keys.
---@param buf integer
---@return nil
function M.attach(buf)
    if vim.b[buf].lvim_ts_textobjects then
        return
    end
    vim.b[buf].lvim_ts_textobjects = true
    for lhs, spec in pairs(config.textobjects.keymaps or {}) do
        if lhs ~= "" and type(spec) == "string" then
            vim.keymap.set({ "x", "o" }, lhs, function()
                M.select(spec)
            end, { buffer = buf, silent = true, desc = "lvim-ts: textobject " .. spec })
        end
    end
end

return M
