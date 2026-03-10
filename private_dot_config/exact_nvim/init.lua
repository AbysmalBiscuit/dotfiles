vim.g.is_manpage = vim.v.progname == "man" or vim.tbl_contains(vim.v.argv, "+Man!")

-- vim.opt.shell = "/bin/sh"
-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
