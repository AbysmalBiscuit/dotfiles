function cm --wraps=chezmoi --description 'alias cm=chezmoi'
    if type -q gh
        CHEZMOI_GITHUB_TOKEN=(gh auth token 2>/dev/null) chezmoi $argv
    else
        chezmoi $argv
    end
end
