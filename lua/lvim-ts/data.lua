-- lvim-ts: parser requirement data for the unified installer prompt.
-- Reports the parser a filetype needs but lacks, without installing or any UI.
-- Availability/installation facts come from lvim-pkg.
--
---@module "lvim-ts.data"

local M = {}

--- Parser language that filetype `ft` needs but does not yet have installed.
--- Returns nil when the parser is already installed, is unavailable, or the
--- filetype has no treesitter mapping.
---@param ft string
---@return string|nil
function M.missing_for_ft(ft)
    if ft == "" then
        return nil
    end
    local ok, pkg = pcall(require, "lvim-pkg")
    if not ok then
        return nil
    end
    local lang = vim.treesitter.language.get_lang(ft) or ft
    if pkg.is_installed("parser", lang) then
        return nil
    end
    for _, candidate in ipairs(pkg.available("parser")) do
        if candidate == lang then
            return lang
        end
    end
    return nil
end

return M
