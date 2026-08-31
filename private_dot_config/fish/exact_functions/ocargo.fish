# cargo with release-grade codegen flags. The flag parsing, RUSTFLAGS assembly
# and nightly check all live in ocargo.py so every shell shares one implementation.
# Completions are registered in completions/ocargo.fish, not with --wraps here,
# so the carapace spec and the plain cargo wrap stay mutually exclusive.
function ocargo --description 'cargo with release-grade codegen flags'
    python3 ~/.local/bin/ocargo.py $argv
end
