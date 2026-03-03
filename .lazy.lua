return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function()
      local orig_start = vim.treesitter.start
      local orig_get_parser = vim.treesitter.get_parser

      vim.treesitter.get_parser = function(buf, lang, ...)
        buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
        if vim.b[buf].chezmoi_ts_lang then
          lang = vim.b[buf].chezmoi_ts_lang
        end
        return orig_get_parser(buf, lang, ...)
      end

      vim.treesitter.start = function(buf, lang, ...)
        buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
        if vim.b[buf].chezmoi_ts_lang then
          lang = vim.b[buf].chezmoi_ts_lang
        end
        return orig_start(buf, lang, ...)
      end
    end,
  },
}
