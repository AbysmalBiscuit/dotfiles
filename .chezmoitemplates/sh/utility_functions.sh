# Utility functions
function has_command() {
    command -v "$1" >/dev/null 2>&1
}

function deduplicate_path() {
    printf %s "$@" | awk -vRS=: '!a[$0]++' | paste -s -d:
}

function remove_windows_paths() {
    printf %s "$@" | /usr/bin/perl -ne 'print join(":", grep { !/\/mnt\/[a-z]/ } split(/:/));' | awk -vRS=: '!a[$0]++' | paste -s -d:
}
