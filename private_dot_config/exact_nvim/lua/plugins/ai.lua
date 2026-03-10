-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  -- {
  --   "yetone/avante.nvim",
  --   ---@type avante.Config
  --   opts = {
  --     provider = "gemini",
  --     auto_suggestions_provider = "ollama",
  --     providers = {
  --       claude = {
  --         endpoint = "https://api.anthropic.com",
  --         model = "claude-sonnet-4-20250514",
  --         timeout = 30000, -- Timeout in milliseconds
  --         extra_request_body = {
  --           temperature = 0.75,
  --           max_tokens = 20480,
  --         },
  --       },
  --       gemini = {
  --         endpoint = "https://generativelanguage.googleapis.com/v1beta/models/",
  --         model = "gemini-2.5-flash",
  --         timeout = 30000,
  --       },
  --       ollama = {
  --         -- endpoint = "http://localhost:11434/v1/chat/completions",
  --         model = "qwen2.5-coder:3b",
  --         is_env_set = require("avante.providers.ollama").check_endpoint_alive,
  --       },
  --       -- ollama_chat = {
  --       --   endpoint = "http://localhost:11434/v1/chat",
  --       --   model = "qwen3:8b",
  --       --   is_env_set = require("avante.providers.ollama").check_endpoint_alive,
  --       -- },
  --     },
  --     behaviour = {
  --       -- auto_suggestions = true,
  --       auto_approve_tool_permissions = false, },
  --   },
  -- },
  {
    "folke/sidekick.nvim",
    keys = {
      { "<C-.>", false },
    },
    ---@type sidekick.Config
    opts = {
      nes = {
        enabled = false,
      },
      cli = {
        tools = {
          aider = { cmd = { "aider", "--model=gemini/gemini-2.5-flash-lite-preview-09-2025" } },
          aider_gemini_flash = { cmd = { "aider", "--model=gemini/gemini-2.5-flash" } },
          aider_gemini_flash_preview = { cmd = { "aider", "--model=gemini/gemini-2.5-flash-lite-preview-09-2025" } },
          aider_ollama_qwen3_8b = { cmd = { "aider", "--model=ollama_chat/qwen3:8b" } },
          aider_ollama_qwen2_5_coder_3b = { cmd = { "aider", "--model=ollama_chat/qwen2.5-coder:3b" } },
          ccr_code = { cmd = { "ccr", "code" } },
        },
      },
      copilot = {
        status = {
          enabled = false,
        },
      },
    },
  },
  -- {
  --   "milanglacier/minuet-ai.nvim",
  --   opts = function(_, opts)
  --     opts = opts or {}
  --     local hostname = vim.fn.hostname()
  --     local config = {}
  --     if hostname == "Yin" then
  --       config = {
  --         provider = "openai_fim_compatible",
  --         n_completions = 1, -- recommend for local model for resource saving
  --         -- I recommend beginning with a small context window size and incrementally
  --         -- expanding it, depending on your local computing power. A context window
  --         -- of 512, serves as an good starting point to estimate your computing
  --         -- power. Once you have a reliable estimate of your local computing power,
  --         -- you should adjust the context window to a larger value.
  --         context_window = 512,
  --         provider_options = {
  --           openai_fim_compatible = {
  --             -- For Windows users, TERM may not be present in environment variables.
  --             -- Consider using APPDATA instead.
  --             api_key = "",
  --             name = "Ollama",
  --             end_point = "http://localhost:11434/v1/completions",
  --             model = "qwen2.5-coder:7b",
  --             optional = {
  --               max_tokens = 56,
  --               top_p = 0.9,
  --             },
  --           },
  --         },
  --       }
  --     end
  --     opts = vim.tbl_deep_extend("force", opts, config)
  --
  --     return opts
  --   end,
  -- },
}
