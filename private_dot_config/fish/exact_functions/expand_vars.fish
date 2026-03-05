function expand_vars -d "Expands variables in passed string without evaluating the string"
    for var in (echo -n $argv | grep -oP '[^\\\\]\$[A-z_][A-z0-9_]*?([^A-z0-9_]|\n)' | perl -pe 's:.*[^\\\\]\$([A-z_][A-z0-9_]*?)[^A-z0-9_].*:\1:g' | sort -u)
        if set -q $var
            set argv (echo -n $argv | string replace -a -r "([^\\\\])\\\$$var" "$1$$var")
        end
    end
    echo $argv
end

# set folders (fd -t d -d 1)
# set v folders
# expand_vars 'for f in $folders; echo \$folders; echo \$myvar; echo $f; echo $folders; end'
