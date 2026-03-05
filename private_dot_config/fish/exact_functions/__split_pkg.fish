function __split_pkg --description 'splits a single pkg row into variables'
    set -l pkg (string split ',' $argv)
    set -l lang $pkg[1]
    set -l name $pkg[2]
    # Due to description containing quotes and commas,
    # it's hard to get it without doing fancy string manipulation.
    # offset is for this: `,,"` + 1 for 1-index
    set -l description_start_offset 4
    set -l description_start (math (string length $lang) + (string length $name) + $description_start_offset)
    # offset is for this: `,,,,,` + 1 for -1 index
    set -l description_end_offset 6
    # echo (string length "$pkg[-5]""$pkg[-4]""$pkg[-3]""$pkg[-2]""$pkg[-1]")
    # echo "$pkg[-5]""$pkg[-4]""$pkg[-3]""$pkg[-2]""$pkg[-1]"
    set -l description_end (math (string length $argv) - (string length "$pkg[-5]""$pkg[-4]""$pkg[-3]""$pkg[-2]""$pkg[-1]") - $description_end_offset)
    set -l description (string sub --start $description_start --end $description_end $argv)

    set -l website (string sub --start 2 --end -1 "$pkg[-5]")
    set -l git (string sub --start 2 --end -1 "$pkg[-4]")
    set -l install_command (string sub --start 2 --end -1 "$pkg[-3]")
    set -l completions_command (string sub --start 2 --end -1 $pkg[-2])
    set -l init_command (string sub --start 2 --end -1 $pkg[-1])
    printf '%s\n' $lang $name $description $website $git $install_command $completions_command $init_command
end
