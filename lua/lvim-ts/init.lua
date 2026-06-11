-- lvim-ts: public API entry point.
-- Call require("lvim-ts").setup(opts) once from your config.  lvim-ts owns the
-- buffer-side treesitter runtime: it installs a buffer's parser on demand (via
-- lvim-pkg) the first time its filetype is opened, then enables highlighting +
-- indentation.  Parser data/installation and the unified prompt live elsewhere
-- (lvim-pkg / lvim-installer).
--
---@module "lvim-ts"

local config = require("lvim-ts.config")
local manager = require("lvim-ts.core.manager")
local data = require("lvim-ts.data")

local M = {}

--- Resolve the configured ensure_installed set to a concrete list of not-yet-installed
--- parsers, then install them silently. `ensure_installed = "all"` installs every
--- available parser except `ignore_install`; a list installs exactly those.
---@param pkg table  lvim-pkg handle
---@return nil
local function ensure_installed(pkg)
	local ei = config.ensure_installed
	if ei ~= "all" and not (type(ei) == "table" and #ei > 0) then
		return
	end
	-- "all" needs the registry; resolve once it is loaded (TTL-gated, no force).
	pkg.update_registry("ts", function()
		local want
		if ei == "all" then
			local ignore = {}
			for _, x in ipairs(config.ignore_install or {}) do
				ignore[x] = true
			end
			want = {}
			for _, lang in ipairs(pkg.available("parser")) do
				if not ignore[lang] then
					want[#want + 1] = lang
				end
			end
		else
			want = ei
		end
		local todo = {}
		for _, lang in ipairs(want) do
			if not pkg.is_installed("parser", lang) then
				todo[#todo + 1] = lang
			end
		end
		if #todo > 0 then
			pkg.install("parser", todo, function() end)
		end
	end, false)
end

--- Configure lvim-ts: register on-demand parser activation and contribute the
--- treesitter parser requirement to the unified install prompt (via lvim-pkg).
---@param opts? LvimTsConfig
---@return nil
function M.setup(opts)
	-- Merge user overrides into the live config (in place, so require()ers see them).
	for k, v in pairs(opts or {}) do
		if type(v) == "table" and type(config[k]) == "table" then
			config[k] = vim.tbl_deep_extend("force", config[k], v)
		else
			config[k] = v
		end
	end

	-- Tell lvim-pkg which parser a filetype needs, for the unified prompt.
	local ok, pkg = pcall(require, "lvim-pkg")
	if ok then
		pkg.register_provider("ts", function(ft)
			local lang = M.missing_for_ft(ft)
			if lang then
				return { { kind = "parser", name = lang, label = "parser: " .. lang } }
			end
			return {}
		end)
		-- Silently install the configured parsers (ensure_installed).
		ensure_installed(pkg)
	end

	-- Activate treesitter on every FileType, then sweep already-open buffers.
	vim.api.nvim_create_autocmd("FileType", {
		desc = "Enable treesitter (install parser on demand)",
		group = vim.api.nvim_create_augroup("lvim_ts", { clear = true }),
		callback = function(args)
			manager.activate(args.buf)
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			manager.activate(buf)
		end
	end
end

-- ── Re-exported API ───────────────────────────────────────────────────────────

--- Resolve the parser language for a buffer.
---@param buf integer
---@return string|nil
function M.lang_for_buf(buf)
	return manager.lang_for_buf(buf)
end

--- Enable treesitter highlighting + indentation for a buffer.
---@param buf  integer
---@param lang string
---@return nil
function M.enable(buf, lang)
	manager.enable(buf, lang)
end

--- Parser language `ft` is missing (for the unified installer prompt), or nil.
---@param ft string
---@return string|nil
function M.missing_for_ft(ft)
	return data.missing_for_ft(ft)
end

return M
