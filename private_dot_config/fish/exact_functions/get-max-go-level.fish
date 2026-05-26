function get-max-go-level --description 'Tests different go optimization levels until one that works is found'
    set -l temp_file (mktemp 'XXXXX.go')
    printf "package main\nfunc main() { println(\"$level\") }" >$temp_file
    set best_level 1
    for level in 4 3 2 1
        env GO111MODULE=off GOAMD64=v$level go run $temp_file 2>/dev/null

        if test $status -eq 0
            set best_level $level
            break
        end
    end
    if test -f $temp_file
        rm $temp_file
    end
    echo $best_level
    return 0
end
