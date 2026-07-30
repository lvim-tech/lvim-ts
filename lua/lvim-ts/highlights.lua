-- lvim-ts.highlights: every group this plugin paints with, built from ONE factory reading the LIVE
-- palette — there is no colour anywhere else in the plugin. init.lua registers it through
-- `lvim-utils.highlight.bind`, so the groups re-derive on ColorScheme / palette sync and track the
-- theme instead of freezing whatever was loaded first.
--
-- Accents are palette KEYS, never a hex in code, and the tint strengths are ROLE names resolved
-- against the shared `lvim-utils.config.ui` scale — the plugin defines no scale of its own.
--
-- What it colours today is the collapsed fold line (core/fold.lua): the bracket glyphs around the
-- counter, the counter itself, and the fallback used for the stretches of the line no capture
-- covers. Those used to be `FoldedIcon` / `FoldedText` — names belonging to nobody, grey wherever a
-- theme had not heard of them.
--
---@module "lvim-ts.highlights"

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")
local config = require("lvim-ts.config")

local M = {}

--- The shared tint scale (`lvim-utils.config.ui` `tint`), read LIVE so a retuned scale reaches us.
---@return table<string, number>
local function shared_tints()
    local ok, ui = pcall(require, "lvim-utils.config.ui")
    return (ok and type(ui) == "table" and ui.tint) or {}
end

--- Resolve a config accent: a palette key (tracks the live theme) or a literal "#rrggbb".
---@param key string
---@return string
local function accent(key)
    local v = c[key]
    return type(v) == "string" and v or key
end

--- Resolve a tint: a ROLE name from the shared scale, or a raw factor, or nothing.
---@param t string|number|nil
---@param tints table<string, number>
---@return number|nil
local function tint_of(t, tints)
    if type(t) == "number" then
        return t
    end
    if type(t) == "string" then
        return tints[t]
    end
    return nil
end

--- A foreground for a colour role: the accent blended toward the editor background when the role
--- carries a tint (a quieter shade of the same hue), or the accent itself when it does not.
---@param role { accent: string, tint: string|number|nil }
---@param tints table<string, number>
---@return string
local function shade(role, tints)
    local t = tint_of(role.tint, tints)
    return t and hl.blend(accent(role.accent), c.bg, t) or accent(role.accent)
end

--- All lvim-ts groups from the live palette + the live `config.colors`.
---@return table<string, table>
function M.build()
    local col = config.colors
    local tints = shared_tints()

    local groups = {
        -- The bracket glyphs that frame the collapsed line's counter.
        LvimTsFoldIcon = { fg = shade(col.fold_icon, tints), bold = col.fold_icon.bold },
        -- The "+N lines" counter between them.
        LvimTsFoldCounter = { fg = shade(col.fold_counter, tints), bold = col.fold_counter.bold },
        -- Whatever the language's `highlights` query does not cover on the folded line.
        LvimTsFoldFill = { fg = shade(col.fold_fill, tints) },
    }
    -- THE EDITOR'S OWN `Folded`, when the config asks for it. Neovim draws the rule from the end of
    -- the collapsed line to the window edge itself, in this group — no chunk we emit can reach it,
    -- so a fold line whose brackets are blue and whose rule is grey can only be fixed here. The
    -- background stays the editor's, so nothing but the rule's colour changes.
    if col.fold_line then
        groups.Folded = { fg = shade(col.fold_line, tints), bg = c.bg }
    end
    return groups
end

return M
