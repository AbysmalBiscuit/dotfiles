# chezmoi
def --wrapped cm [...args] {
    let token = (do --ignore-errors { ^gh auth token | str trim } | default "")
    with-env { CHEZMOI_GITHUB_TOKEN: $token } { ^chezmoi ...$args }
}
alias cmexe = cm execute-template
