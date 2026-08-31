# ocargo's completions come from ~/.config/carapace/specs/ocargo.yaml, the same
# spec nushell reads. Sourced per-command rather than through carapace's global
# fish bridge, which would replace every other command's completions too.
#
# Without carapace there is nothing to describe ocargo's own flags, so fall back
# to cargo's completions. The two are exclusive because carapace's snippet opens
# with `complete -e ocargo`, which would drop the wrap anyway.
if type -q carapace
    carapace ocargo fish | source
else
    complete -c ocargo -w cargo
end
