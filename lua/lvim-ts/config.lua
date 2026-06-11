-- lvim-ts: the live configuration table.
-- Holds the defaults; setup() merges user overrides into it in place, so every
-- require("lvim-ts.config") reader sees the effective values.
--
---@module "lvim-ts.config"

---@class LvimTsConfig
---@field auto_install     boolean          Install a missing parser automatically on first open
---@field ensure_installed string[]|"all"   Parsers to install at setup; "all" = every available one
---@field ignore_install   string[]         When ensure_installed = "all", parsers to exclude

---@type LvimTsConfig
return {
	auto_install = true,
	ensure_installed = {},
	ignore_install = {},
}
