#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

# Should the command line "usage" be printed on stdout or stderr?
# https://stackoverflow.com/questions/2199624/should-the-command-line-usage-be-printed-on-stdout-or-stderr
#
# Argbash
# https://argbash.readthedocs.io/en/latest/example.html
#
# How can I handle command-line options and arguments in my script easily?
# http://mywiki.wooledge.org/BashFAQ/035
#
# ComplexOptionParsing
# http://mywiki.wooledge.org/ComplexOptionParsing


# -----------------------------------------------------------------------------
# @brief Handles shell exit operations, displaying session statistics.
# @details This function is called automatically when the shell exits. It 
#          calculates and displays the number of commands executed during the
#          session and the session's end timestamp. It is intended to provide
#          users with session statistics before the shell terminates.
#
# @global EXIT This signal is trapped to call the `egress` function upon shell
#              termination.
#
# @note The function uses `history | wc -l` to count the commands executed in 
#       the current session and `date` to capture the session end time.
# -----------------------------------------------------------------------------
function egress() {
    true
}

wrap_messages() {
    local line_width=$1        # Maximum width of each line
    local primary=$2           # Primary message string
    local secondary=$3         # Secondary message string
    local delimiter="␞"        # ASCII delimiter (code 30) for separating messages

    # -----------------------------------------------------------------------------
    # @brief Wraps a message into lines with ellipses for overflow or continuation.
    # @details Splits the message into lines, appending an ellipsis for overflowed
    #          lines and prepending it for continuation lines.
    #
    # @param $1 [required] The message string to wrap.
    # @param $2 [required] Maximum width of each line (numeric).
    #
    # @global None.
    #
    # @throws None.
    #
    # @return A single string with wrapped lines, ellipses added as necessary.
    #
    # @example
    # wrapped=$(wrap_message "This is a long message" 50)
    # echo "$wrapped"
    # -----------------------------------------------------------------------------
    local wrap_message
    wrap_message() {
        local message=$1        # Input message to wrap
        local width=$2          # Maximum width of each line
        local result=()         # Array to store wrapped lines
        local adjusted_width=$((width - 2))  # Adjust width for ellipses

        # Process message line-by-line
        while IFS= read -r line; do
            result+=("$line")
        done <<< "$(printf "%s\n" "$message" | fold -s -w "$adjusted_width")"

        # Add ellipses to wrapped lines
        for ((i = 0; i < ${#result[@]}; i++)); do
            if ((i == 0)); then
                # Append ellipsis to the first line
                result[i]="${result[i]% }…"
            elif ((i == ${#result[@]} - 1)); then
                # Prepend ellipsis to the last line
                result[i]="…${result[i]}"
            else
                # Add ellipses to both ends of middle lines
                result[i]="…${result[i]% }…"
            fi
        done

        # Return the wrapped lines as a single string
        printf "%s\n" "${result[@]}"
    }

    # Process the primary message
    local overflow=""          # Stores overflow lines from the primary message
    if [[ ${#primary} -gt $line_width ]]; then
        local wrapped_primary  # Temporarily stores the wrapped primary message
        wrapped_primary=$(wrap_message "$primary" "$line_width")
        overflow=$(printf "%s\n" "$wrapped_primary" | tail -n +2)
        primary=$(printf "%s\n" "$wrapped_primary" | head -n 1)
    fi

    # Process the secondary message
    if [[ ${#secondary} -gt $line_width ]]; then
        secondary=$(wrap_message "$secondary" "$line_width")
    fi

    # Return the combined messages
    printf "%s%b%s%b%s" "$primary" "$delimiter" "$overflow" "$delimiter" "$secondary"
}

add_period() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_period cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Add a trailing period if it's missing
    if [[ "$input" != *. ]]; then
        input="$input."
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

warn() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -----------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -----------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgylw=$(safe_tput setaf 3)  # Yellow text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text
    local fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # -----------------------------------------------------------------------------
    # @brief Creates a formatted prefix for logging messages.
    # @details Combines color, labels, and positional information into a prefix.
    #
    # @param $1 Color for the prefix.
    # @param $2 Label for the message (e.g., "[WARN ]").
    #
    # @return Formatted prefix as a string.
    #
    # @example
    # local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    # -----------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " \
            "${bold}${color}" "$label" "${reset}" \
            "${bold}" "$script" "$func_name" "$caller_line" "${reset}"
    }

    # Generate prefixes
    local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    local extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    local dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_warn_prefix=$(echo -e "$warn_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    local prefix_length=${#plain_warn_prefix}
    local adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    fi

    # Process primary message
    message=$(add_period "${1:-A warning was raised on this line}")
    if [[ -n "$error_code" ]]; then
        message=$(printf "%s Code: (%d)" "$message" "$error_code")
    fi
    shift

    # Process additional details
    details="${1:-}"
    shift
    for arg in "$@"; do
        details+=" $arg"
    done
    if [[ -n $details ]]; then
        details=$(add_period "$details")
    fi

    # Call wrap_and_combine_messages
    local result
    result=$(wrap_messages "$adjusted_width" "$message" "$details")

    # Parse wrapped parts
    local primary="${result%%${delimiter}*}"
    result="${result#*${delimiter}}"
    local overflow="${result%%${delimiter}*}"
    local secondary="${result#*${delimiter}}"

    # Print the primary message
    printf "%s%s\n" "$warn_prefix" "$primary" >&2

    # Print overflow lines
    if [[ -n "$overflow" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$extd_prefix" "$line" >&2
        done <<< "$overflow"
    fi

    # Print secondary details
    if [[ -n "$secondary" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$dets_prefix" "$line" >&2
        done <<< "$secondary"
    fi

    # Include stack trace for warnings if enabled
    if [[ "${WARN_STACK_TRACE:-false}" == "true" ]]; then
        stack_trace "WARNING" "$message"
    fi
}


remove_dot() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
            debug_end "$debug" # Next line must be a return/print/exit out of function
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == *. ]]; then
        input="${input#.}"
    fi

    debug_end "$debug" # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

pad_with_spaces() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # Declare locals
    local number="${1:-0}"  # Input number (mandatory)
    local width="${2:-4}"   # Optional width (default is 4)

    # If the second parameter is "debug", adjust the arguments
    if [[ "$width" == "debug" ]]; then
        debug="$width"
        width=4  # Default width to 4 if "debug" was passed in place of width
    fi

    # Validate input for the number
    if [[ -z "${number:-}" || ! "$number" =~ ^[0-9]+$ ]]; then
        die 1 "Input must be a valid non-negative integer."
    fi

    # Ensure the width is a positive integer
    if [[ ! "$width" =~ ^[0-9]+$ || "$width" -lt 1 ]]; then
        die 1 "Error: Width must be a positive integer."
    fi

    # Strip leading zeroes to prevent octal interpretation
    number=$((10#$number))  # Forces the number to be interpreted as base-10

    # Format the number with leading spaces and return it as a string
    printf "%${width}d\n" "$number"

    debug_end "$debug" # Next line must be a return/print/exit out of function
    return 0
}

exit_script() {
    local debug=$(debug_start "$@")     # Debug declarations, must be first line

    # Local variables
    local exit_status="${1:-}"          # First parameter as exit status
    local message="${2:-Exiting script.}"  # Main error message, defaults to "Exiting script."
    local details                       # Additional details
    local lineno="${BASH_LINENO[0]}"    # Line number where the exit was called
    lineno=$(pad_with_spaces "$lineno") # Pad line number with spaces for consistency
    local caller_func="${FUNCNAME[1]}"  # Calling function name

    # Determine exit status if not numeric
    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
        message="${message}"  # No need to overwrite message here
    else
        shift  # Remove the exit_status from the arguments
    fi

    # Remove trailing dot if needed
    message=$(remove_dot "$message")
    printf "[EXIT ] '%s' from %s:%d status (%d).\n" "$message" "$caller_func" "$lineno" "$exit_status" # Log the provided or default message

    debug_end "$debug" # Next line must be a return/print/exit out of function
    exit "$exit_status"  # Exit with the provided status
}

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
    local caller_line=${BASH_LINENO[1]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] Starting function %s() called by %s():%d.\n" \
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
        printf "[DEBUG in %s] '%s' from %s():%d.\n" \
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
        printf "[DEBUG in %s] Exiting function %s() called by %s():%d.\n" \
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

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

    retval="$?"

    debug_end "$debug"
    return "$retval"
}

word_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_one() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

    retval="$?"

    debug_end "$debug"
    return "$retval"
}

 flag_arg_tre() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

    retval="$?"

    debug_end "$debug"
    return "$retval"
}

flag_arg_fwr() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0

    local function_name
    local caller_name
    local caller_line
    local argument
    argument="${1:-}"
    function_name="${FUNCNAME:-main}"
    caller_name="${FUNCNAME[1]:-main}"
    caller_line="${BASH_LINENO[0]:-0}"

    # Handle debug mode
    debug_print "Argument: ${argument}" "$debug"

    local message="Function: ${function_name}() called by ${caller_name}():${caller_line}"
    # Conditionally append the argument if it's not empty
    if [[ -n "$argument" ]]; then
        message="${message} with argument: ${argument}"
    fi
    # End the message with a period
    message="${message}."
    # Print the final message
    printf "%s\n" "$message"

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
    for entry in "${options_list[@]}"; do
        local flag=$(echo "$entry" | cut -d' ' -f1)

        # Track the max length of the flag
        local flag_len=${#flag}
        if (( flag_len > max_flag_len )); then
            max_flag_len=$flag_len
        fi
    done
    # Second pass to print with padded formatting
    for entry in "${options_list[@]}"; do
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
    local retval=0
    local args=("$@")

    # Loop through all provided arguments
    while (( ${#args[@]} > 0 )); do
        local current_arg="${args[0]}"
        local found_match=false

        # Check against word arguments (arguments_list)
        if [[ "${current_arg:0:1}" != "-" ]]; then
            for entry in "${arguments_list[@]}"; do
                local word
                local function_name
                local description
                local exit_flag
                word=$(echo "$entry" | cut -d' ' -f1)
                function_name=$(echo "$entry" | cut -d' ' -f2)
                description=$(echo "$entry" | cut -d' ' -f3- | rev | cut -d' ' -f2- | rev)
                exit_flag=$(echo "$entry" | awk '{print $NF}')

                # Check if the current argument matches the word argument
                if [[ "$current_arg" == "$word" ]]; then
                    found_match=true
                    # Call the associated function
                    $function_name "$debug"
                    retval="$?"

                    # Exit if exit_flag is set
                    if (( exit_flag == 1 )); then
                        debug_end "$debug"
                        exit_script "$retval" "" "$debug"
                        # DEBUG: TODO:  Can also - return "$retval"
                    fi

                    # Remove the processed argument from args
                    args=("${args[@]:1}")
                    break
                fi
            done
        else
            # Process options_list
            for entry in "${options_list[@]}"; do
                local flag
                local complex_flag
                local function_name
                local description
                local exit_flag
                flag=$(echo "$entry" | cut -d' ' -f1)
                complex_flag=$(echo "$entry" | cut -d' ' -f2)
                function_name=$(echo "$entry" | cut -d' ' -f3)
                description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
                exit_flag=$(echo "$entry" | awk '{print $NF}')

                # Split the flag by "|" and check if $current_arg matches any of the flags
                IFS='|' read -ra flag_parts <<< "$flag"  # Split the flag by "|"

                for part in "${flag_parts[@]}"; do
                    # Remove any leading/trailing spaces from each flag part
                    part=$(echo "$part" | xargs)

                    # Check if the current argument matches this part
                    if [[ "$current_arg" == "$part" ]]; then
                        found_match=true
                        # If it's a complex flag, we expect a following argument
                        if (( complex_flag == 1 )); then
                            local next_arg
                            if [[ ${#args[@]} -ge 2 ]]; then
                                next_arg="${args[1]}"
                            else
                                echo "Error: Missing argument for flag '$part'" >&2
                                return 1
                            fi

                            # Call the function with the next argument as a parameter
                            $function_name "$next_arg" "$debug"
                            retval="$?"

                            # Remove the processed flag and its argument
                            args=("${args[@]:2}")
                        else
                            # Call the function with no arguments
                            $function
                            retval="$?"
                            # Remove the processed flag
                            args=("${args[@]:1}")
                        fi

                        # Exit if exit_flag is set
                        if (( exit_flag == 1 )); then
                            debug_end "$debug"
                            exit_script "$retval" "" "$debug"
                            # DEBUG: TODO:  Can also - return "$retval"
                        fi
                    fi
                done
            done
        fi

        # If no match was found, show an error and break the loop
        if ! $found_match; then
            echo "Error: Invalid argument '$current_arg'" >&2
            retval=1
            break  # Exit the loop when no valid argument is found
        fi

        # Check if args is empty after processing the argument
        if (( ${#args[@]} == 0 )); then
            break
        fi
    done

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

# -----------------------------------------------------------------------------
# @brief Traps the `EXIT` signal to invoke the `egress` function.
# @details Ensures the `egress` function is called automatically when the shell
#          exits. This enables proper session cleanup and displays session 
#          statistics to the user.
# -----------------------------------------------------------------------------
trap egress EXIT

# Call the main function
debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
retval=0 ; main "$@" "$debug" ; retval="$?"
debug_end "$debug"
exit "$retval"
