function unlockgpg --description "Warm the gpg-agent passphrase cache for commit signing"
    # WSL: gpg-agent often reads the passphrase from gnome-keyring via
    # libsecret, so unlock that keyring first.
    if set -q WSL_DISTRO_NAME
        if type -q secret-tool
            secret-tool store --label="Unlock" unlock true
        else
            echo "secret-tool is needed to unlock the keyring via the terminal." >&2
            echo "Install it with: sudo apt install libsecret-tools" >&2
            return 1
        end
    end

    # Use the exact gpg binary and signing key git is configured with, so we
    # warm the same agent/key that signs commits — not whatever bare `gpg` is.
    set -l gpg (git config --get gpg.program)
    test -n "$gpg"; or set gpg gpg
    set -l key (git config --get user.signingkey)

    if test -n "$key"
        echo warm | $gpg --local-user $key --clearsign >/dev/null 2>&1
    else
        echo warm | $gpg --clearsign >/dev/null 2>&1
    end

    if test $status -eq 0
        echo "GPG passphrase cached."
    else
        echo "gpg sign test failed (status $status)." >&2
        return 1
    end
end
