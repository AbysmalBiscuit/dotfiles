function cmsecrets --description 'Runs the command to edit chezmoi secrets'
    set -l source_path (chezmoi source-path)
    "$source_path/edit_secrets.sh"
end
