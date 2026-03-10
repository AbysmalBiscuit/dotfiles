---@type vim.lsp.Config
return {
  settings = {
    texlab = {
      diagnostics = {
        ignoredPatterns = {
          "Unused label",
          "Class acmart Warning: \\vspace should only be used to provide space above/below surrounding objects.*",
        },
      },
      symbols = {
        customEnvironments = {
          { name = "surveyblocks", displayName = "SurveyBlocks", label = true },
          { name = "MultipleChoiceSingleAnswer", displayName = "MultipleChoiceSingleAnswer", label = true },
          { name = "MultipleChoiceMultipleAnswer", displayName = "MultipleChoiceMultipleAnswer", label = true },
          { name = "researchquestions", displayName = "ResearchQuestions", label = true },
          { name = "surveydesign", displayName = "SurveyDesign", label = true },
        },
      },
      latexindent = {
        ["local"] = "localSettings.yaml",
      },
    },
  },
}
