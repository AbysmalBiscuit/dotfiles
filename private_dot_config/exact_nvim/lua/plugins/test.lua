-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  -- {
  --   "MisanthropicBit/neotest-busted",
  -- },
  -- {
  --   "nvim-neotest/neotest",
  --   dependencies = { "nvim-neotest/nvim-nio", "MisanthropicBit/neotest-busted" },
  --   opts = {
  --     -- Can be a list of adapters like what neotest expects,
  --     -- or a list of adapter names,
  --     -- or a table of adapter names, mapped to adapter configs.
  --     -- The adapter will then be automatically loaded with the config.
  --     require("neotest-busted")({
  --       -- Leave as nil to let neotest-busted automatically find busted
  --       busted_command = nil,
  --       -- Do not use nvim to run busted, but run busted directly
  --       no_nvim = false,
  --       -- Extra arguments to busted
  --       busted_args = nil,
  --       -- List of paths to add to lua path lookups before running
  --       -- busted, or a function returning a list of such paths
  --       -- busted_paths = { "my/custom/path/?.lua" },
  --       busted_paths = nil,
  --       -- List of paths to add to lua cpath lookups before running
  --       -- busted, or a function returning a list of such paths
  --       busted_cpaths = nil,
  --       -- Custom config to load via -u to set up testing.
  --       -- If nil, will look for a 'minimal_init.lua' file
  --       minimal_init = nil,
  --       -- Only use a luarocks installation in the project's directory. If
  --       -- true, installations in $HOME and global installations will be
  --       -- ignored. Useful for isolating the test environment
  --       local_luarocks_only = true,
  --       -- Find parametric tests
  --       parametric_test_discovery = false,
  --     }),
  --     -- require("neotest-plenary"),
  --     -- Example for loading neotest-golang with a custom config
  --     -- adapters = {
  --     --   ["neotest-golang"] = {
  --     --     go_test_args = { "-v", "-race", "-count=1", "-timeout=60s" },
  --     --     dap_go_enabled = true,
  --     --   },
  --     -- },
  --   },
  -- },
  {
    "nvim-neotest/neotest",
    dependencies = {
      "thenbe/neotest-playwright",
      dependencies = "nvim-telescope/telescope.nvim",
    },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(
        opts.adapters,
        require("neotest-playwright").adapter({
          options = {
            persist_project_selection = true,
            enable_dynamic_test_discovery = true,
          },
        })
      )
    end,
  },
}
