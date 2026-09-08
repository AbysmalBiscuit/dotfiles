return {
  {
    "saghen/blink.cmp",
    init = function()
      require("skill_frontmatter").setup()
    end,
    opts = function(_, opts)
      table.insert(opts.sources.default, "skill_frontmatter")
      opts.sources.providers.skill_frontmatter = {
        name = "Skill frontmatter",
        module = "skill_frontmatter.source",
        score_offset = 10,
      }
    end,
  },
}
