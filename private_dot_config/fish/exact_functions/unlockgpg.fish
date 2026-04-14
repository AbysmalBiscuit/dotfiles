function unlockgpg --description "Unlocks gpg key for use in signing commits without needing to commit"
    if test $OS = wsl
        if type -q secret-tool
            secret-tool store --label="Unlock" unlock true
        else
            echo "secrte-tool is needed to unlock the keyring via the terminal."
            echo "Install it with:"
            echo "sudo apt install libsecret-tools"
            exit 1
        end
    end
    echo test | gpg --clearsign
end
