-- vim.cmd("ToggleBlinkRipgrep")

local snacks_sources = {
	"files",
	"explorer",
	"grep",
	"grep_word",
	"grep_buffers",
	"lsp_references",
	"lsp_definitions",
	"lsp_declarations",
	"lsp_implementations",
	"lsp_symbols",
	"lsp_workspace_symbols",
}

for _, source_name in ipairs(snacks_sources) do
	local source = Snacks.config.picker.sources[source_name]
	if source ~= nil then
		---@diagnostic disable-next-line: inject-field
		source.follow = true
		---@diagnostic disable-next-line: inject-field
		source.hidden = true
	end
end

vim.api.nvim_set_hl(0, "LspReferenceRead", {})

--------------------------------------------------------------------------------
-- Treesitter
--------------------------------------------------------------------------------

local chezmoi_filetypes = { "bash", "sh", "fish", "toml", "conf", "ini" }
for i = 1, #chezmoi_filetypes do
	vim.treesitter.language.register("gotmpl", chezmoi_filetypes[i] .. ".chezmoitmpl")
end

local ft_to_parser = {
	sh = "bash",
	bash = "bash",
	zsh = "bash",
	toml = "toml",
	yaml = "yaml",
	json = "json",
	fish = "fish",
	lua = "lua",
	ini = "ini",
	conf = "bash",
}

local function set_gotmpl_injections(lang)
	vim.treesitter.query.set(
		"gotmpl",
		"injections",
		string.format('((text) @injection.content (#set! injection.combined) (#set! injection.language "%s"))', lang)
	)
end

local orig_ts_start = vim.treesitter.start
vim.treesitter.start = function(buf, lang, ...)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	if vim.b[buf].chezmoi_ts_lang then
		lang = vim.b[buf].chezmoi_ts_lang
	end
	return orig_ts_start(buf, lang, ...)
end

vim.api.nvim_create_autocmd("BufReadPost", {
	pattern = { "*.tmpl" },
	callback = function(ev)
		-- Mark this buffer early, before filetype is even set
		vim.b[ev.buf].chezmoi_ts_lang = "gotmpl"
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "*.chezmoitmpl",
	callback = function(ev)
		local ft = vim.bo[ev.buf].filetype
		local base = ft:match("^(.+)%.chezmoitmpl$")
		local lang = ft_to_parser[base] or "bash"
		vim.b[ev.buf].chezmoi_base_parser = lang
		set_gotmpl_injections(lang)
	end,
})

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
	pattern = "*.tmpl",
	callback = function(ev)
		vim.b[ev.buf].chezmoi_ts_lang = "gotmpl"
	end,
})

--------------------------------------------------------------------------------
-- LSP
--------------------------------------------------------------------------------

local all_filetypes = { "bash", "sh", "fish", "toml", "conf", "ini" }
local filetypes = { "go", "gomod", "gowork", "gotmpl" }
for i = 1, #all_filetypes do
	table.insert(filetypes, all_filetypes[i] .. ".chezmoitmpl")
end

vim.lsp.config("gopls", {
	filetypes = filetypes,
	settings = {
		gopls = {
			templateExtensions = { "tmpl" },
		},
	},
})

-- local ignored_vtsls_codes = { [80001] = true }
-- local method = vim.lsp.protocol.Methods.textDocument_publishDiagnostics
--
-- vim.api.nvim_create_autocmd("LspAttach", {
-- 	callback = function(args)
-- 		local client = vim.lsp.get_client_by_id(args.data.client_id)
--
-- 		-- Only apply to vtsls
-- 		if client and client.name == "vtsls" then
-- 			client.handlers[method] = function(err, result, ctx, config)
-- 				if result.diagnostics then
-- 					local filtered = {}
-- 					for _, diagnostic in ipairs(result.diagnostics) do
-- 						if not ignored_vtsls_codes[diagnostic.code] then
-- 							table.insert(filtered, diagnostic)
-- 						end
-- 					end
-- 					result.diagnostics = filtered
-- 				end
-- 				-- Call the default handler with the filtered results
-- 				vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx)
-- 			end
-- 		end
-- 	end,
-- })
