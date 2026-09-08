# Forward the cm wrapper and its aliases to the external completer.
def "nu-complete chezmoi" [context: string] {
    let words = ($context | str trim --left | split row --regex '\s+')
    let expansion = (scope aliases | where name == ($words | first) | get --optional 0.expansion)
    let spans = if ($expansion | is-not-empty) {
        ($expansion | split row --regex '\s+') ++ ($words | skip 1)
    } else {
        $words
    }

    let completer = $env.config.completions.external.completer
    if ($completer | describe) != "closure" { return [] }
    do $completer (["chezmoi"] ++ ($spans | skip 1))
}
