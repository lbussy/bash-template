#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'
set +o noclobber

declare FALLBACK_SCRIPT_NAME="${FALLBACK_SCRIPT_NAME:-template.sh}"
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-bash-template}"
declare GIT_BRCH="${GIT_BRCH:-main}"
declare GIT_TAG="${GIT_TAG:-0.0.1}"
declare SEM_VER="${GIT_TAG:-0.0.1}"
declare LOCAL_SOURCE_DIR="${LOCAL_SOURCE_DIR:-}"
declare LOCAL_WWW_DIR="${LOCAL_WWW_DIR:-}"
declare LOCAL_SCRIPTS_DIR="${LOCAL_SCRIPTS_DIR:-}"
declare GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"
declare GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"
declare GIT_CLONE="${GIT_CLONE:-"https://github.com/$REPO_ORG/$REPO_NAME.git"}"

declare USER_HOME
if [[ -n "${SUDO_USER-}" ]]; then
    readonly USER_HOME=$(eval echo "~$SUDO_USER")
else
    readonly USER_HOME="$HOME"
fi

readonly DIRECTORIES=("man" "scripts" "conf")           # Relevant directories for installation.

download_file() {
    local file_path="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"
    curl -s -o "$dest_dir/$(basename "$file_path")" "$GIT_RAW/$REPO_BRANCH/$file_path"
}

download_files_from_directories() {
    local dest_root="$USER_HOME/apppop" # Destination root directory
    logI "Fetching repository tree."
    local tree=$(fetch_tree)

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree. Check repository details or ensure it is public."
    fi

    for dir in "${DIRECTORIES[@]}"; do
        logI "Processing directory: $dir"

        local files
        files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
            '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

        if [[ -z "$files" ]]; then
            logI "No files found in directory: $dir"
            continue
        fi

        local dest_dir="$dest_root/$dir"
        mkdir -p "$dest_dir"

        printf "%s\n" "$files" | while read -r file; do
            logI "Downloading: $file"
            download_file "$file" "$dest_dir"
        done

        logI "Files from $dir downloaded to: $dest_dir"
    done

    logI "Files saved in: $dest_root"
    update_directory_and_files "$dest_root"
}

fetch_tree() {
    local branch_sha
    branch_sha=$(curl -s "$GIT_API/git/ref/heads/$REPO_BRANCH" | jq -r '.object.sha')
    curl -s "$GIT_API/git/trees/$branch_sha?recursive=1"
}

update_file() {
    local file="$1"
    local home_root="$2"

    if [[ -z "$file" || -z "$home_root" ]]; then
        logE "Usage: update_file <file> <home_root>"
        return 1
    fi

    if [[ ! -d "$home_root" ]]; then
        logE "Home root '$home_root' is not a valid directory."
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        logE "File '$file' does not exist."
        return 1
    fi

    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    logI "Changing ownership of '$file' to '$owner'."
    chown "$owner":"$owner" "$file" || { logE "Failed to change ownership."; return 1; }

    if [[ "$file" == *.sh ]]; then
        logI "Setting permissions of '$file' to 700 (executable)."
        chmod 700 "$file" || { logE "Failed to set permissions to 700."; return 1; }
    else
        logI "Setting permissions of '$file' to 600."
        chmod 600 "$file" || { logE "Failed to set permissions to 600."; return 1; }
    fi

    logI "Ownership and permissions updated successfully for '$file'."
    return 0
}

update_directory_and_files() {
    local directory="$1"
    local home_root="$USER_HOME"

    if [[ -z "$directory" ]]; then
        logE "Usage: update_directory_and_files <directory>"
        return 1
    fi

    if [[ ! -d "$directory" ]]; then
        logE "Directory '$directory' does not exist."
        return 1
    fi

    if [[ -z "$home_root" || ! -d "$home_root" ]]; then
        logE "USER_HOME environment variable is not set or points to an invalid directory."
        return 1
    fi

    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    logI "Changing ownership and permissions of '$directory' tree."
    find "$directory" -type d -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update ownership or permissions of directories."
        return 1
    }

    logI "Setting permissions of non-.sh files to 600 in '$directory'."
    find "$directory" -type f ! -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 600 {} \; || {
        logE "Failed to update permissions of non-.sh files."
        return 1
    }

    logI "Setting permissions of .sh files to 700 in '$directory'."
    find "$directory" -type f -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update permissions of .sh files."
        return 1
    }

    logI "Ownership and permissions applied to all files and directories in '$directory'."
    return 0
}

# TODO: Git clone

_main() {
    download_files_from_directories
}

main() { _main "$@"; };
main "$@"
exit $?
