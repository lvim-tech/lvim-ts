-- Which grammar a buffer gets, and in what order that is decided:
--   a buffer-local `b:lvim_ts_lang`  →  config.language_map[ft]  →  treesitter's own ft→lang map
--   →  the filetype itself.
-- The installer prompt (`missing_for_ft`) must mirror that same order, or it offers a parser that
-- `activate` will never ask for.

local ts = require("lvim-ts")
local config = require("lvim-ts.config")

--- A scratch buffer with filetype `ft` (and optional override), current for `fn`.
---@param ft string
---@param override string|nil
---@param fn fun(buf: integer)
local function on_buffer(ft, override, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = ft
    if override then
        vim.b[buf].lvim_ts_lang = override
    end
    local ok, err = pcall(fn, buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if not ok then
        error(err, 0)
    end
end

describe("lvim-ts.lang_for_buf")

it("takes the filetype when nothing maps it", function()
    on_buffer("lua", nil, function(buf)
        eq("lua", ts.lang_for_buf(buf))
    end)
end)

it("lets the config's language_map rename a filetype's grammar", function()
    local saved = config.language_map["lvim-test-ft"]
    config.language_map["lvim-test-ft"] = "glimmer"
    on_buffer("lvim-test-ft", nil, function(buf)
        eq("glimmer", ts.lang_for_buf(buf))
    end)
    config.language_map["lvim-test-ft"] = saved
end)

it("lets a buffer-local override win over everything", function()
    local saved = config.language_map["lua"]
    config.language_map["lua"] = "mapped"
    on_buffer("lua", "chosen_by_buffer", function(buf)
        eq("chosen_by_buffer", ts.lang_for_buf(buf), "b:lvim_ts_lang is the last word")
    end)
    config.language_map["lua"] = saved
end)

it("ignores an empty or non-string override", function()
    on_buffer("lua", "", function(buf)
        eq("lua", ts.lang_for_buf(buf), "an empty override is no override")
    end)
end)

it("says nothing for a buffer with no filetype", function()
    on_buffer("", nil, function(buf)
        eq(nil, ts.lang_for_buf(buf))
    end)
end)

it("says nothing for a buffer that is gone", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    eq(nil, ts.lang_for_buf(buf))
end)

describe("lvim-ts.missing_for_ft")

it("asks about the MAPPED language, not the filetype", function()
    -- The prompt and `activate` must want the same parser. With a map pointing at a language
    -- nobody ships, the answer is either that language or nil (unavailable) — never the filetype.
    local saved = config.language_map["lvim-test-ft"]
    config.language_map["lvim-test-ft"] = "lvim_no_such_grammar"
    local got = ts.missing_for_ft("lvim-test-ft")
    truthy(got == nil or got == "lvim_no_such_grammar", "got " .. tostring(got))
    config.language_map["lvim-test-ft"] = saved
end)

it("says nothing for an empty filetype", function()
    eq(nil, ts.missing_for_ft(""))
end)
