-- lvim-ts plugin guard.
-- Nothing auto-runs; the user controls everything via require("lvim-ts").setup(opts).
-- This file exists so the plugin manager recognises the plugin without requiring
-- an explicit `main` field.
if vim.g.loaded_lvim_ts then
	return
end
vim.g.loaded_lvim_ts = true
