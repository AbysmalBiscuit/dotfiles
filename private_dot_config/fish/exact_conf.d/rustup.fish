# Add rust source paths
if ! test -f $HOME/.cargo/env.fish
    exit 0
end

source $HOME/.cargo/env.fish

# Source completion files found in cargo registry
if set -q _CARGO_COMPLETION_PATHS; and test (count $_CARGO_COMPLETION_PATHS) -ge 1
    if [ (count $_CARGO_COMPLETION_PATHS) -eq 1 ]; and string match -q "* *" "$_CARGO_COMPLETION_PATHS"
        for comp in (string split " " $_CARGO_COMPLETION_PATHS)
            source $comp
        end
    else
        for comp in $_CARGO_COMPLETION_PATHS
            source $comp
        end
    end
end
