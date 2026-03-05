function __make_subword_patterns --description 'Creates regex patterns to match partial words by character'
    set -l patterns
    for com in $argv
        if string match --quiet --regex '.+\|.+' $com
            set -l pat
            set -l parts (string split '|' $com)
            for part in $parts
                set -l chars (string split '' $part)
                set -l len (math (count $chars) - 1)
                set pat "$pat""$chars[1]"
                for char in $chars[2..-1]
                    set pat "$pat"'('"$char"
                end
                set pat $pat(string repeat --count $len ')?')
                set pat "$pat|"
            end
            set --append patterns '^('(string join '' (string sub --end -1 "$pat"))')$'
        else
            set -l chars (string split '' $com)
            set -l len (math (count $chars) - 1)
            set -l pat $chars[1]
            for char in $chars[2..-1]
                set pat "$pat"'('"$char"
            end
            set pat "^$pat"(string repeat --count $len ')?')'$'
            set --append patterns $pat
        end
    end
    printf '%s\n' $patterns
end
