#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

function egress {
    rm -f /tmp/output.txt
    systemctl start smb.service
    iptables -D INPUT -p tcp -s 10.0.0.222 --dport 32400 -j ACCEPT
}
# Call the egress function
trap egress EXIT

# -----------------------------------------------------------------------------
# @brief Determines the script name to use.
# @details This block of code determines the value of `THIS_SCRIPT` based on
#          the following logic:
#          1. If `THIS_SCRIPT` is already set in the environment, it is used.
#          2. If `THIS_SCRIPT` is not set, the script checks if
#             `${BASH_SOURCE[0]}` is available:
#             - If `${BASH_SOURCE[0]}` is set and not equal to `"bash"`, the
#               script extracts the filename (without the path) using
#               `basename` and assigns it to `THIS_SCRIPT`.
#             - If `${BASH_SOURCE[0]}` is unbound or equals `"bash"`, it falls
#               back to using the value of `FALLBACK_SCRIPT_NAME`, which
#               defaults to `debug_print.sh`.
#
# @var FALLBACK_SCRIPT_NAME
# @brief Default name for the script in case `BASH_SOURCE[0]` is unavailable.
# @details This variable is used as a fallback value if `BASH_SOURCE[0]` is
#          not set or equals `"bash"`. The default value is `"debug_print.sh"`.
#
# @var THIS_SCRIPT
# @brief Holds the name of the script to use.
# @details The script attempts to determine the name of the script to use. If
#          `THIS_SCRIPT` is already set in the environment, it is used
#          directly. Otherwise, the script tries to extract the filename from
#          `${BASH_SOURCE[0]}` (using `basename`). If that fails, it defaults
#          to `FALLBACK_SCRIPT_NAME`.
# -----------------------------------------------------------------------------
declare FALLBACK_SCRIPT_NAME="${FALLBACK_SCRIPT_NAME:-debug_print.sh}"
if [[ -z "${THIS_SCRIPT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]:-}" != "bash" ]]; then
        # Use BASH_SOURCE[0] if it is available and not "bash"
        THIS_SCRIPT=$(basename "${BASH_SOURCE[0]}")
    else
        # If BASH_SOURCE[0] is unbound or equals "bash", use FALLBACK_SCRIPT_NAME
        THIS_SCRIPT="${FALLBACK_SCRIPT_NAME}"
    fi
fi

# -----------------------------------------------------------------------------
# @brief Starts the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments, and if so, prints the debug information including the
#          function call and the line number.
#
# @param "$@" Arguments to check for the "debug" flag.
# @return The "debug" flag if present, or an empty string if not.
# -----------------------------------------------------------------------------
debug_start() {
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Starting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi

    # Return debug flag if present
    printf "%s\n" "${debug:-}"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Filters out the "debug" flag from the arguments.
# @details This function removes the "debug" flag from the list of arguments
#          and returns the filtered arguments. The debug flag is not passed
#          to other functions.
#
# @param "$@" Arguments to filter.
# @return Filtered arguments, excluding "debug".
# -----------------------------------------------------------------------------
debug_filter() {
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "debug" ]] || args+=("$arg")
    done
    printf "%q " "${args[@]}"
}

# -----------------------------------------------------------------------------
# @brief Prints a debug message if the debug flag is set.
# @details This function checks if the "debug" flag is present in the arguments
#          and, if so, prints the provided debug message along with the function
#          and line number where it was called.
#
# @param "$@" Arguments to check for the "debug" flag and message.
# @global debug Debug flag, passed from the calling function.
# @return None
# -----------------------------------------------------------------------------
debug_print() {
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done
    # Restore positional parameters
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Assign the remaining argument to the message. Defaults to <unset>
    local message="${1:-<unset>}"

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Message: '%s' sent by %s():%d.\n" \
        "$THIS_SCRIPT" "$message" "$caller_name" "$caller_line" >&2
    fi
}

# -----------------------------------------------------------------------------
# @brief Ends the debug process.
# @details This function checks if the "debug" flag is present in the arguments
#          and, if so, prints the debug information indicating the exit of
#          the function, along with the function name and line number.
#
# @param "$@" Arguments to check for the "debug" flag.
# @global debug Debug flag, passed from the calling function.
# @return None
# -----------------------------------------------------------------------------
debug_end() {
    local debug=""
    local args=()  # Array to hold non-debug arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG:%s] Exiting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi
}

############
### Arguments Functions
############

# Word arguments: Each entry is "<word> <function> <description> <exit_after>"
# exit_after is 0 or 1, 0 is false, 1 is true
arguments_list=(
    "word1 word_arg_one Handles word argument one 0"
    "word2 word_arg_two Handles word argument two 1"
)

# Flagged arguments: Each entry is "<flag> <complex_flag> <function> <description> <exit_flag>"
# flag is a pipe-delimited list of flags to trigger this condition
# complex_flag (hasa a secondary word argument) is 0 or 1; 0 is false, 1 is true
# exit_after is 0 or 1, 0 is false, 1 is true
options_list=(
    "-1|--flag_1 0 flag_arg_one Handles opt_arg_1 1"
    "-2|--flag_2 0 flag_arg_two Handles opt_arg_3 0"
    "-3|--flag_3 1 flag_arg_tre Handles opt_arg_4 1"
    "-4|--flag_4 1 flag_arg_fwr Handles opt_arg_4 1"
)

word_arg_one() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

word_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_one() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"


    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

 flag_arg_tre() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_fwr() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local retval=0
    printf "Function: %s debug mode is (%s) args: %s\n" "${FUNCNAME}" "${debug:-disabled}" "$*"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

usage() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Append "sudo" if required
    local script_name
    [[ "${REQUIRE_SUDO:-}" == "true" ]] && script_name+="sudo "
    script_name+=" ./$THIS_SCRIPT"
    # Print the usage with the correct script name
    printf "\nUsage: %s [debug] <option1> [<option2> ...]\n\n" "$script_name"

    printf "Available Options\n\n"

    # Display word arguments
    printf "Word Arguments:\n"
    local max_word_len=0
    # First pass to calculate the maximum lengths
    for entry in "${word_arguments_list[@]}"; do
        # The first word in the string is the word argument name
        local word=$(echo "$entry" | cut -d' ' -f1)

        # Calculate max_length by comparing length of the word
        local word_len=${#word}
        if (( word_len > max_word_len )); then
            max_word_len=$word_len
        fi
    done
    # Second pass to print with padded formatting
    for entry in "${word_arguments_list[@]}"; do
        # Parse each entry again
        # Word arguments:   word_len    | function          | description       | exit_flag
        #                   pos_arg_1   | positional_arg_1  | Handles pos_arg_1 | 0
        local word=$(echo "$entry" | cut -d' ' -f1)
        local function=$(echo "$entry" | cut -d' ' -f2)
        local description=$(echo "$entry" | cut -d' ' -f3- | rev | cut -d' ' -f2- | rev)
        local exit_flag=$((1 - $(echo "$entry" | awk '{print $NF}'))) # Invert the value, 1 is true to humans


        # Print with left-justified padding
        printf "  %$(($max_word_len))s: %s\n" "$word" "$description"
    done
    printf "\n"

    # Optional arguments: each entry is "<flag> <complex_flag> <function> <description> <exit_flag>"

    # Display optional arguments
    printf "Flag Arguments:\n"
    # Initialize variable to track the max length of $flag
    local max_flag_len=0
    for entry in "${flag_arguments_list[@]}"; do
        local flag=$(echo "$entry" | cut -d' ' -f1)

        # Track the max length of the flag
        local flag_len=${#flag}
        if (( flag_len > max_flag_len )); then
            max_flag_len=$flag_len
        fi
    done
    # Second pass to print with padded formatting
    for entry in "${flag_arguments_list[@]}"; do
        # Parse each entry using positional splitting
        # Optional arguments:   flag           | complex_flag   | function   | description                        | exit_flag
        #                       -1|--opt_arg_1 | 0              | opt_arg_1  | Handles opt_arg_1 (flag) and exits | 1
        local flag=$(echo "$entry" | cut -d' ' -f1)
        local complex_flag=$(echo "$entry" | cut -d' ' -f2)
        local function=$(echo "$entry" | cut -d' ' -f3)
        local description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
        local exit_flag=$((1 - $(echo "$entry" | awk '{print $NF}'))) # Invert the value, 1 is true to humans

        # Split $flag by "|" and replace with spaces, then print with right padding
        printf "  %$(($max_flag_len))s: %s\n" "$(echo "$flag" | tr '|' ' ')" "$description"
    done

    debug_end "$debug"
    return 0
}

process_args() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    usage "$debug"

    debug_end "$debug"
    return "$retval"
}

############
### Main Functions
############

# -----------------------------------------------------------------------------
# @brief Main function to run the script.
# @details This function may be renamed to anything you like, except for
#          `main()`. If you update the name, be sure to update the name of
#          `_main` in the line/function `main() { _main "$@"; return "$?"; }`.
#
# @param "$@" Arguments to be passed to `_main`.
# @return Returns the status code from `_main`.
# -----------------------------------------------------------------------------
_main() {
    # This first line captures the debug variable for the function and logs a
    # debug line if it is present.
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    process_args "$@" "$debug"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Main function entry point.
# @details This function calls `_main` to initiate the script execution. By
#          calling `main`, we enable the correct reporting of the calling
#          function in Bash, ensuring that the stack trace and function call
#          are handled appropriately during the script execution.
#
# @param "$@" Arguments to be passed to `_main`.
# @return Returns the status code from `_main`.
# -----------------------------------------------------------------------------
main() { _main "$@"; return "$?"; }

# Call the main function
debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
retval=0 ; main "$@" "$debug" ; retval="$?"
debug_end "$debug"
exit "$retval"
