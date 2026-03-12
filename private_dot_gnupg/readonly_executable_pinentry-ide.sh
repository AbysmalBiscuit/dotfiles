#!/bin/sh
if [ -n "$PINENTRY_USER_DATA" ]; then
    case "$PINENTRY_USER_DATA" in
    IJ_PINENTRY=*)
        export WSLENV=INTELLIJ_SSH_ASKPASS_HANDLER/w:INTELLIJ_SSH_ASKPASS_PORT/w:INTELLIJ_GIT_ASKPASS_HANDLER/w:INTELLIJ_GIT_ASKPASS_PORT/w:INTELLIJ_REBASE_HANDER_NO/w:INTELLIJ_REBASE_HANDER_PORT/w:PINENTRY_USER_DATA/w
        "/mnt/c/Program Files (x86)/JetBrains/PyCharm 2025.1.3.1/jbr/bin/java.exe" -cp "C:/Program Files (x86)/JetBrains/PyCharm 2025.1.3.1/plugins/vcs-git/lib/git4idea-rt.jar;C:/Program Files (x86)/JetBrains/PyCharm 2025.1.3.1/lib/externalProcess-rt.jar" git4idea.gpg.PinentryApp
        exit $?
        ;;
    esac
fi
exec /usr/bin/pinentry "$@"
