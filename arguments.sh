#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

# -----------------------------------------------------------------------------
# @brief Handles shell exit operations, displaying session statistics.
# @details This function is called automatically when the shell exits. It
#          calculates and displays the number of commands executed during
#          the session and the session's end timestamp. It is intended to
#          provide users with session statistics before the shell terminates.
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
    local line_width=$1 # Maximum width of each line
    local primary=$2    # Primary message string
    local secondary=$3  # Secondary message string
    local delimiter="␞" # ASCII delimiter (code 30) for separating messages

    # -------------------------------------------------------------------------
    # @brief Wraps a message into lines with ellipses for overflow or
    #        continuation.
    # @details Splits the message into lines, appending an ellipsis for
    #          overflowed lines and prepending it for continuation lines.
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
    # -------------------------------------------------------------------------
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
    printf "%s%b%s%b%s" /
        "$primary" /
        "$delimiter" /
        "$overflow" /
        "$delimiter" /
        "$secondary"
}

# -----------------------------------------------------------------------------
# @brief Adds a period to the end of the input string if it doesn't already
#        have one.
# @details This function checks if the input string has a trailing period.
#          If not, it appends one. If the input is empty, an error is logged.
#
# @param $1 [required] The input string to process.
#
# @return The input string with a period added at the end (if missing).
# @return 1 If the input string is empty.
#
# @example
# result=$(add_period "Hello")
# echo "$result"  # Output: "Hello."
# -----------------------------------------------------------------------------
add_period() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_period cannot be empty."
        debug_end "$debug" # Next line must be a return/print/exit
        return 1
    fi

    # Add a trailing period if it's missing
    if [[ "$input" != *. ]]; then
        input="$input."
    fi

    debug_end "$debug"  # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Prints a stack trace with optional formatting and a message.
# @details This function generates and displays a formatted stack trace for
#          debugging purposes. It includes a log level and optional details,
#          with color-coded formatting and proper alignment.
#
# @param $1 [optional] Log level (DEBUG, INFO, WARN, ERROR, CRITICAL).
#           Defaults to INFO.
# @param $2 [optional] Primary message for the stack trace.
# @param $@ [optional] Additional context or details for the stack trace.
#
# @global FUNCNAME Array of function names in the call stack.
# @global BASH_LINENO Array of line numbers corresponding to the call stack.
# @global THIS_SCRIPT The name of the current script, used for logging.
# @global COLUMNS Console width, used for formatting output.
#
# @throws None.
#
# @return None. Outputs the stack trace and message to standard output.
#
# @example
# stack_trace WARN "Unexpected condition detected."
# -----------------------------------------------------------------------------
stack_trace() {
    # Determine log level and message
    local level="${1:-INFO}"  # Default to INFO if $1 is not provided
    local message=""

    # Check if $1 is a valid level, otherwise treat it as the message
    case "$level" in
        DEBUG|INFO|WARN|WARNING|ERROR|CRIT|CRITICAL)
            shift
            ;;
        *)
            # If $1 is not valid, treat it as the beginning of the message
            message="$level"
            level="INFO"
            shift
            ;;
    esac

    # Concatenate all remaining arguments into $message
    for arg in "$@"; do
        message+="$arg "
    done
    # Trim trailing space
    message="${message% }"

    # Block width and character for header/footer
    local width=60
    local char="-"

    # Define functions to skip
    local skip_functions=("die" "warn" "stack_trace")
    local encountered_main=0 # Track the first occurrence of main()

    # Get the current function name in title case
    local raw_function_name="${FUNCNAME[0]}"
    local function_name
    function_name="$(echo "$raw_function_name" | /
        sed -E 's/_/ /g; s/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')"

    # -------------------------------------------------------------------------
    # @brief Determines if a function should be skipped in the stack trace.
    # @details Skips functions specified in the `skip_functions` list and
    #          ignores duplicate `main()` entries.
    #
    # @param $1 Function name to evaluate.
    #
    # @return 0 if the function should be skipped, 1 otherwise.
    #
    # @example
    # should_skip "main" && continue
    # -------------------------------------------------------------------------
    should_skip() {
        local func="$1"
        for skip in "${skip_functions[@]}"; do
            if [[ "$func" == "$skip" ]]; then
                return 0 # Skip this function
            fi
        done
        # Skip duplicate main()
        if [[ "$func" == "main" ]]; then
            if (( encountered_main > 0 )); then
                return 0 # Skip subsequent occurrences of main
            fi
            ((encountered_main++))
        fi
        return 1 # Do not skip
    }

    # Iterate through the stack to build the displayed stack
    local displayed_stack=()
    local longest_length=0  # Track the longest function name length

    # Handle a piped script calling stack_trace from main
    if [[ -p /dev/stdin && ${#FUNCNAME[@]} == 1 ]]; then
        displayed_stack+=("$(printf "%s|%s" "main()" "${BASH_LINENO[0]}")")
    fi

    # Handle the rest of the stack
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[i]}"
        local line="${BASH_LINENO[i - 1]}"
        local current_length=${#func}

        # Skip ignored functions
        if should_skip "$func"; then
            continue
        elif (( current_length > longest_length )); then
            longest_length=$current_length
        fi

        # Prepend the formatted stack entry to reverse the order
        displayed_stack=("$(printf "%s|%s" /
            "$func()" /
            "$line")" /
            "${displayed_stack[@]}")
    done

    # -------------------------------------------------------------------------
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
    # -------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgred=$(safe_tput setaf 1)  # Red text
    local fggrn=$(safe_tput setaf 2)  # Green text
    local fgylw=$(safe_tput setaf 3)  # Yellow text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgmag=$(safe_tput setaf 5)  # Magenta text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text
    local fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # Determine color and label based on the log level
    local color label
    case "$level" in
        DEBUG) color=${fgcyn}; label="[DEBUG]";;
        INFO) color=${fggrn}; label="[INFO ]";;
        WARN|WARNING) color=${fggld}; label="[WARN ]";;
        ERROR) color=${fgmag}; label="[ERROR]";;
        CRIT|CRITICAL) color=${fgred}; label="[CRIT ]";;
    esac

    # Create header
    local dash_count=$(( (width - ${#function_name} - 2) / 2 ))
    local header_l header_r
    header_l="$(printf '%*s' "$dash_count" | tr ' ' "$char")"
    header_r="$header_l"
    [[ $(( (width - ${#function_name}) % 2 )) -eq 1 ]] && /
        header_r="${header_r}${char}"
    local header=$(printf "%b%s%b %b%b%s%b %b%s%b" /
        "${color}" /
        "${header_l}" /
        "${reset}" /
        "${color}" /
        "${bold}" /
        "${function_name}" /
        "${reset}" /
        "${color}" /
        "${header_r}" /
        "${reset}")

    # Create footer
    local footer="$(printf '%*s' "$width" "" | tr ' ' "$char")"
    [[ -n "$color" ]] && footer="${color}${footer}${reset}"

    # Print header
    printf "%s\n" "$header"

    # Print the message, if provided
    if [[ -n "$message" ]]; then
        # Extract the first word and preserve the rest
        local first="${message%% *}"    # Extract up to the first space
        local remainder="${message#* }" # Remove the first word and the space

        # Format the message
        message="$(printf "%b%b%s%b %b%b%s%b" \
            "${bold}" "${color}" "$first" \
            "${reset}" "${color}" "$remainder" \
            "${reset}")"

        # Print the formatted message
        printf "%b\n" "$message"
    fi

    # Calculate indent for proper alignment
    local indent=$(( ($width / 2) - ((longest_length + 28) / 2) ))

    # Print the displayed stack in reverse order
    for ((i = ${#displayed_stack[@]} - 1, idx = 0; i >= 0; i--, idx++)); do
        IFS='|' read -r func line <<< "${displayed_stack[i]}"
        printf "%b%*s [%d] Function: %-*s Line: %4s%b\n" /
            "${color}" /
            "$indent" /
            ">" /
            "$idx" /
            "$((longest_length + 2))" /
            "$func" /
            "$line" /
            "${reset}"
    done

    # Print footer
    printf "%b%s%b\n\n" "${color}" "$footer" "${reset}"
}

# -----------------------------------------------------------------------------
# @brief Terminates the script with a critical error message and details.
# @details This function prints a critical error message along with optional
#          details, formats them with color and indentation, and includes a
#          stack trace for debugging. It then exits with the specified error
#          code.
#
# @param $1 [optional] Numeric error code. Defaults to 1 if not provided.
# @param $2 [optional] Primary error message. Defaults to "Critical error"
#                      if not provided.
# @param $@ [optional] Additional details or context for the error.
#
# @global THIS_SCRIPT The script's name, used for logging.
# @global COLUMNS Console width, used to calculate message formatting.
#
# @throws Exits the script with the provided error code or the default
#         value (1).
#
# @return None. Outputs formatted error messages and terminates the script.
#
# @example
# die 127 "File not found" "The specified file is missing or inaccessible."
# -----------------------------------------------------------------------------
die() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -------------------------------------------------------------------------
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
    # -------------------------------------------------------------------------
    safe_tput() {
        tput "$@" 2>/dev/null || printf ""
    }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)

    # Foreground colors
    local fgred=$(safe_tput setaf 1)  # Red text
    local fgblu=$(safe_tput setaf 4)  # Blue text
    local fgcyn=$(safe_tput setaf 6)  # Cyan text

    # -------------------------------------------------------------------------
    # @brief Formats a log message prefix with a specified label and color.
    # @details Constructs a formatted prefix string that includes the label,
    #          the script name, the calling function name, and the line number.
    #
    # @param $1 [required] Color for the label (e.g., `$fgred` for red text).
    # @param $2 [required] Label for the prefix (e.g., "[CRIT ]").
    #
    # @return A formatted prefix string with color and details.
    #
    # @example
    # local crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    # -------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " /
            "${bold}${color}" /
            "$label" /
            "${reset}" /
            "${bold}" /
            "$script" /
            "$func_name" /
            "$caller_line" /
            "${reset}"
    }

    # Generate prefixes
    local crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    local extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    local dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_crit_prefix=$(echo -e "$crit_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    local prefix_length=${#plain_crit_prefix}
    local adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric, default to 1
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    else
        error_code=1  # Default to 1 if no numeric value is provided
    fi

    # Process primary message
    message=$(add_period "${1:-Critical error}")
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
    printf "%s%s\n" "$crit_prefix" "$primary" >&2

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
    stack_trace "CRITICAL" "$message"
    exit "$error_code"
}

# -----------------------------------------------------------------------------
# @brief Logs a warning message with optional additional details and
#        formatting.
# @details This function outputs a formatted warning message with color and
#          positional information (script name, function, and line number).
#          If additional details are provided, they are included in the
#          message. The function also supports including an error code and
#          handling stack traces if enabled.
#
# @param $1 [optional] The primary message to log. Defaults to "A warning was
#                      raised on this line" if not provided.
# @param $@ [optional] Additional details to include in the warning message.
#
# @return None.
#
# @example
# warn "File not found" "Please check the file path."
# -----------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    #     local bold=$(safe_tput bold)
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # @brief Creates a formatted prefix for logging messages.
    # @details Combines color, labels, and positional information into a
    #          prefix.
    #
    # @param $1 [required] Color for the prefix.
    # @param $2 [required] Label for the message (e.g., "[WARN ]").
    #
    # @return [string] Formatted prefix as a string.
    #
    # @example
    # local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    # -------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# @brief Removes a leading dot from the input string, if present.
# @details This function checks if the input string starts with a dot (`.`)
#          and removes it. If the input is empty, an error message is logged.
#          The function handles empty strings by returning an error and logging
#          an appropriate warning message.
#
# @param $1 [required] The input string to process.
#
# @return 0 on success, 1 on failure (when the input is empty).
#
# @example
# remove_dot ".hidden"  # Output: "hidden"
# remove_dot "visible"  # Output: "visible"
# -----------------------------------------------------------------------------
remove_dot() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
        debug_end "$debug"  # Next line must be a return/print/exit from func
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == *. ]]; then
        input="${input#.}"
    fi

    debug_end "$debug"  # Next line must be a return/print/exit out of function
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Pads a number with leading spaces to achieve the desired width.
# @details This function takes a number and a specified width, and returns the
#          number formatted with leading spaces if necessary. The number is
#          guaranteed to be a valid non-negative integer, and the width is
#          checked to ensure it is a positive integer. If "debug" is passed as
#          the second argument, it defaults the width to 4 and provides debug
#          information.
#
# @param $1 [required] The number to be padded (non-negative integer).
# @param $2 [optional] The width of the output (defaults to 4 if not provided).
#
# @return 0 on success.
#
# @example
# pad_with_spaces 42 6  # Output: "   42"
# pad_with_spaces 123 5  # Output: "  123"
# -----------------------------------------------------------------------------
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

    debug_end "$debug"  # Next line must be a return/print/exit out of function
    return 0
}

# -----------------------------------------------------------------------------
# @brief Handles script exit operations and logs the exit message.
# @details This function is designed to handle script exit operations by logging
#          the exit message along with the status code, function name, and line
#          number where the exit occurred. The function also supports an optional
#          message and exit status, with default values provided if not supplied.
#          After logging the exit message, the script will terminate with the
#          specified exit status.
#
# @param $1 [optional] Exit status code (default is 1 if not provided).
# @param $2 [optional] Message to display upon exit (default is "Exiting
#           script.").
#
# @return None.
#
# @example
# exit_script 0 "Completed successfully"
# exit_script 1 "An error occurred"
# -----------------------------------------------------------------------------
exit_script() {
    local debug=$(debug_start "$@")     # Debug declarations, must be first line

    # Local variables
    local exit_status="${1:-}"              # First parameter as exit status
    local message="${2:-Exiting script.}"   # Main error message wit default
    local details                           # Additional details
    local lineno="${BASH_LINENO[0]}"        # Line number of calling line
    lineno=$(pad_with_spaces "$lineno")     # Pad line number with spaces
    local caller_func="${FUNCNAME[1]}"      # Calling function name

    # Determine exit status if not numeric
    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
        message="${message}"  # No need to overwrite message here
    else
        shift  # Remove the exit_status from the arguments
    fi

    # Remove trailing dot if needed
    message=$(remove_dot "$message")
    # Log the provided or default message
    printf "[EXIT ] '%s' from %s:%d status (%d).\n" "$message" "$caller_func" "$lineno" "$exit_status"

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
        # If BASH_SOURCE[0] is unbound or "bash", use FALLBACK_SCRIPT_NAME
        THIS_SCRIPT="${FALLBACK_SCRIPT_NAME}"
    fi
fi

# -----------------------------------------------------------------------------
# @brief Starts the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments, and if so, prints the debug information including the
#          function name, the caller function name, and the line number where
#          the function was called.
#
# @param "$@" Arguments to check for the "debug" flag.
#
# @return Returns the "debug" flag if present, or an empty string if not.
#
# @example
# debug_start "debug"  # Prints debug information
# debug_start          # Does not print anything, returns an empty string
# -----------------------------------------------------------------------------
debug_start() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Look for the "debug" flag in the provided arguments
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

    # Return the debug flag if present, or an empty string if not
    printf "%s\n" "${debug:-}"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Filters out the "debug" flag from the arguments.
# @details This function removes the "debug" flag from the list of arguments
#          and returns the filtered arguments. The debug flag is not passed
#          to other functions to avoid unwanted debug outputs.
#
# @param "$@" Arguments to filter.
#
# @return Returns a string of filtered arguments, excluding "debug".
#
# @example
# debug_filter "arg1" "debug" "arg2"  # Returns "arg1 arg2"
# -----------------------------------------------------------------------------
debug_filter() {
    local args=()  # Array to hold non-debug arguments

    # Iterate over each argument and exclude "debug"
    for arg in "$@"; do
        if [[ "$arg" != "debug" ]]; then
            args+=("$arg")
        fi
    done

    # Print the filtered arguments, safely quoting them for use in a command
    printf "%q " "${args[@]}"
}

# -----------------------------------------------------------------------------
# @brief Prints a debug message if the debug flag is set.
# @details This function checks if the "debug" flag is present in the
#          arguments. If the flag is present, it prints the provided debug
#          message along with the function name and line number from which the
#          function was called.
#
# @param "$@" Arguments to check for the "debug" flag and the debug message.
# @global debug A flag to indicate whether debug messages should be printed.
#
# @return None.
#
# @example
# debug_print "debug" "This is a debug message"
# -----------------------------------------------------------------------------
debug_print() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Loop through all arguments and identify the "debug" flag
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done

    # Restore the positional parameters with the filtered arguments
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Assign the remaining argument to the message, defaulting to <unset>
    local message="${1:-<unset>}"

    # Print debug information if the debug flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] '%s' from %s():%d.\n" \
        "$THIS_SCRIPT" "$message" "$caller_name" "$caller_line" >&2
    fi
}

# -----------------------------------------------------------------------------
# @brief Ends the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments. If the flag is present, it prints debug information
#          indicating the exit of the function, along with the function name
#          and line number from where the function was called.
#
# @param "$@" Arguments to check for the "debug" flag.
# @global debug Debug flag, passed from the calling function.
#
# @return None
#
# @example
# debug_end "debug"
# -----------------------------------------------------------------------------
debug_end() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Loop through all arguments and identify the "debug" flag
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Print debug information if the debug flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] Exiting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi
}

############
### Arguments Functions
############

# -----------------------------------------------------------------------------
# @brief List of word arguments.
# @details Each entry in the list corresponds to a word argument and contains
#          the argument name, the associated function, a brief description,
#          and a flag indicating whether the function should exit after
#          processing the argument.
#
# @var arguments_list
# @brief List of word arguments.
# @details The list holds the word arguments, their corresponding functions,
#          descriptions, and exit flags. Each word argument triggers a
#          specific function when encountered on the command line.
# -----------------------------------------------------------------------------
arguments_list=(
    "word1 word_arg_one Handles word argument one 0"
    "word2 word_arg_two Handles word argument two 1"
)

# -----------------------------------------------------------------------------
# @brief List of flagged arguments.
# @details Each entry in the list corresponds to a flagged argument, containing
#          the flag(s), a complex flag indicating if a secondary argument is
#          required, the associated function, a description, and an exit flag
#          indicating whether the function should terminate after processing.
#
# @var options_list
# @brief List of flagged arguments.
# @details This list holds the flags (which may include multiple pipe-delimited
#          options), the associated function to call, whether a secondary
#          argument is required, and whether the function should exit after
#          processing.
# -----------------------------------------------------------------------------
options_list=(
    "-1|--flag_1 0 flag_arg_one Handles flag_arg_one 0"
    "-2|--flag_2 0 flag_arg_two Handles flag_arg_two 1"
    "-3|--flag_3 1 flag_arg_tre Handles flag_arg_tre 0"
    "-4|--flag_4 1 flag_arg_fwr Handles flag_arg_fwr 1"
    "-h|--help 0 usage Show these instructions 1"
)

# -----------------------------------------------------------------------------
# @brief Handles the first word argument.
# @details This function processes a plain word argument, constructs a message
#          based on its value, and prints the message. If the argument is not
#          provided, a default message is used. This function is designed as a
#          demo for handling word arguments, showing how to pass and process
#          arguments.
#
# @param $1 [optional] Turns on debug printing
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
word_arg_one() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument value
    #          is constructed. If no argument is provided, a default message
    #          is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Handles the first word argument.
# @details This function processes a plain word argument, constructs a message
#          based on its value, and prints the message. If the argument is not
#          provided, a default message is used. This function is designed as a
#          demo for handling word arguments, showing how to pass and process
#          arguments.
#
# @param $1 [optional] Turns on debug printing if == "debug"
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
word_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument value
    #          is constructed. If no argument is provided, a default message
    #          is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Handles the first flag argument.
# @details This function processes the a flagged argument, constructs a
#          message based on whether the argument is provided. If an argument
#          is supplied, it constructs a message with the argument value.
#          Otherwise, a default message is used. The message is then printed
#          with the debug_print function, and the status is returned.
#
# @param $1 [optional] The first flag argument passed to the function. If not
#           provided, the function defaults to an empty string.
# @param $2 [optional] Turns on debug printing if == "debug"
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
flag_arg_one() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument
    #          value is constructed. If no argument is provided, a default
    #          message is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Handles the first flag argument.
# @details This function processes the a flagged argument, constructs a
#          message based on whether the argument is provided. If an argument
#          is supplied, it constructs a message with the argument value.
#          Otherwise, a default message is used. The message is then printed
#          with the debug_print function, and the status is returned.
#
# @param $1 [optional] The first flag argument passed to the function. If not
#           provided, the function defaults to an empty string.
# @param $2 [optional] Turns on debug printing if == "debug"
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
flag_arg_two() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument value
    #          is constructed. If no argument is provided, a default message
    #          is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Handles the first flag argument.
# @details This function processes the a flagged argument, constructs a
#          message based on whether the argument is provided. If an argument
#          is supplied, it constructs a message with the argument value.
#          Otherwise, a default message is used. The message is then printed
#          with the debug_print function, and the status is returned.
#
# @param $1 [optional] The first flag argument passed to the function. If not
#           provided, the function defaults to an empty string.
# @param $2 [optional] Turns on debug printing if == "debug"
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
flag_arg_tre() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument value
    #          is constructed. If no argument is provided, a default message
    #          is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Handles the first flag argument.
# @details This function processes the a flagged argument, constructs a
#          message based on whether the argument is provided. If an argument
#          is supplied, it constructs a message with the argument value.
#          Otherwise, a default message is used. The message is then printed
#          with the debug_print function, and the status is returned.
#
# @param $1 [optional] The first flag argument passed to the function. If not
#           provided, the function defaults to an empty string.
# @param $2 [optional] Turns on debug printing if == "debug"
#
# @return 0 on success, or the status of the last executed command.
# -----------------------------------------------------------------------------
flag_arg_fwr() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local argument
    argument="${1:-}"  # Use the first argument or default to an empty string

    # -------------------------------------------------------------------------
    # @brief Constructs a message based on the presence of the argument.
    # @details If the argument is provided, a message with the argument value
    #          is constructed. If no argument is provided, a default message
    #          is used.
    # -------------------------------------------------------------------------
    local message
    if [[ -n "$argument" ]]; then
        message="Argument: ${argument}."
    else
        message="No arguments."
    fi

    # -------------------------------------------------------------------------
    # @brief Print the constructed message.
    # @details The message is printed using the debug_print function. If the
    #          debug flag is set, the function outputs the message with debug
    #          information.
    # -------------------------------------------------------------------------
    debug_print "$message" "$debug"
    retval="$?"

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Processes command-line arguments.
# @details This function processes both word arguments (defined in
#          `arguments_list`) and flagged options (defined in `options_list`).
#          It handles complex flags that require a following argument, and
#          calls the associated functions for each valid argument. If an
#          invalid argument is encountered, it will trigger the `usage()`
#          function to display help instructions.
#
# @param $@ [optional] Command-line arguments passed to the function.
# @global arguments_list List of valid word arguments and their associated
#                        functions.
# @global options_list List of valid flagged options and their associated
#                      functions.
# @global debug_flag Optional debug flag to enable debugging information.
#
# @return 0 on success, or the status code of the last executed command.
# -----------------------------------------------------------------------------
process_args() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local args=("$@")
    local invalid_argument=false

    # -----------------------------------------------------------------------------
    # @brief Loop through all the arguments passed to the function.
    # @details This loop iterates through each argument, processing either word
    #          arguments or flagged options.
    # -----------------------------------------------------------------------------
    while (( ${#args[@]} > 0 )); do
        local current_arg="${args[0]}"
        local processed_argument=false

        # -----------------------------------------------------------------------------
        # @brief Skip empty arguments.
        # -----------------------------------------------------------------------------
        if [[ -z "${current_arg}" ]]; then
            args=("${args[@]:1}")  # Remove the blank argument and continue
            continue
        fi

        # -----------------------------------------------------------------------------
        # @brief Process flagged options (starting with "-").
        # -----------------------------------------------------------------------------
        if [[ "${current_arg:0:1}" == "-" ]]; then
            # Loop through all flagged options (options_list)
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

                # -----------------------------------------------------------------------------
                # @brief Split flags and check if current_arg matches.
                # -----------------------------------------------------------------------------
                IFS='|' read -ra flag_parts <<< "$flag"  # Split the flag by "|"
                for part in "${flag_parts[@]}"; do
                    part=$(echo "$part" | xargs)  # Trim spaces

                    # Check if the current argument matches any of the flags
                    if [[ "$current_arg" == "$part" ]]; then
                        # If it's a complex flag, we expect a following argument
                        if (( complex_flag == 1 )); then
                            local next_arg
                            if [[ ${#args[@]} -ge 2 ]]; then
                                next_arg="${args[1]}"
                            else
                                die 1 "Error: Missing argument for flag '$part'."
                            fi

                            # Call the function with the next argument as a parameter
                            $function_name "$next_arg" "$debug"
                            retval="$?"

                            # Remove the processed flag and its argument
                            args=("${args[@]:2}")
                            processed_argument=true
                        else
                            # Call the function with no arguments
                            $function_name
                            retval="$?"
                            # Remove the processed flag
                            args=("${args[@]:1}")
                            processed_argument=true
                        fi

                        # Exit if exit_flag is set
                        if (( exit_flag == 1 )); then
                            debug_end "$debug"
                            exit_script "$retval"
                        fi
                        continue
                    fi
                done
            done
        elif [[ -n "${current_arg}" ]]; then
            # -----------------------------------------------------------------------------
            # @brief Process single-word arguments from arguments_list.
            # -----------------------------------------------------------------------------
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
                    # Call the associated function
                    $function_name "$debug"
                    retval="$?"

                    # Exit if exit_flag is set
                    if (( exit_flag == 1 )); then
                        debug_end "$debug"
                        exit_script "$retval"
                    fi

                    # Remove the processed argument from args
                    args=("${args[@]:1}")
                    processed_argument=true
                    break
                fi
            done
        fi

        # -----------------------------------------------------------------------------
        # @brief Handle invalid arguments by setting the flag.
        # -----------------------------------------------------------------------------
        if [[ "$processed_argument" != true ]]; then
            args=("${args[@]:1}")
            invalid_argument=true
            continue
        fi
    done

    # -----------------------------------------------------------------------------
    # @brief If any invalid argument is found, show usage instructions.
    # -----------------------------------------------------------------------------
    if [[ "$invalid_argument" == true ]]; then
        usage
    fi

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Prints usage information for the script.
# @details This function prints out the usage instructions for the script,
#          including the script name, command-line options, and their
#          descriptions. The usage of word arguments and flag arguments is
#          displayed separately. It also handles the optional inclusion of
#          the `sudo` command based on the `REQUIRE_SUDO` environment variable.
#          Additionally, it can direct output to either stdout or stderr based
#          on the second argument.
#
# @param $@ [optional] Command-line arguments passed to the function,
#                      typically used for the debug flag.
# @global REQUIRE_SUDO If set to "true", the script name will include "sudo"
#                      in the usage message.
# @global THIS_SCRIPT The script's name, used for logging.
#
# @return 0 on success.
# -----------------------------------------------------------------------------
usage() {
    local debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local output_redirect="1"  # Default to stdout (1)
    local args=()              # Array to hold non-debug arguments

    # -----------------------------------------------------------------------------
    # @brief Check for the "stderr" argument to redirect output to stderr.
    # -----------------------------------------------------------------------------
    for arg in "$@"; do
        if [[ "$arg" == "stderr" ]]; then
            output_redirect="2"  # Set to stderr (2)
            shift
            break  # Exit the loop as soon as we find "stderr"
        fi
    done

    # -----------------------------------------------------------------------------
    # @brief Check if "sudo" should be appended to the script name based on
    #        the REQUIRE_SUDO variable.
    # -----------------------------------------------------------------------------
    local script_name
    [[ "${REQUIRE_SUDO:-}" == "true" ]] && script_name+="sudo "
    script_name+=" ./$THIS_SCRIPT"

    # -----------------------------------------------------------------------------
    # @brief Print the usage with the correct script name, without including
    #        redirection.
    # -----------------------------------------------------------------------------
    printf "\nUsage: %s [debug] <option1> [<option2> ...]\n\n" "$script_name" >&$output_redirect

    # -----------------------------------------------------------------------------
    # @brief Word Arguments section
    # -----------------------------------------------------------------------------
    printf "Available Options\n\n" >&$output_redirect
    printf "Word Arguments:\n" >&$output_redirect

    local max_word_len=0
    # First pass to calculate the maximum lengths of the word arguments
    for entry in "${arguments_list[@]}"; do
        local word=$(echo "$entry" | cut -d' ' -f1)
        local word_len=${#word}
        if (( word_len > max_word_len )); then
            max_word_len=$word_len
        fi
    done

    # Second pass to print with padded formatting
    for entry in "${arguments_list[@]}"; do
        local word=$(echo "$entry" | cut -d' ' -f1)
        local function=$(echo "$entry" | cut -d' ' -f2)
        local description=$(echo "$entry" | cut -d' ' -f3- | rev | cut -d' ' -f2- | rev)
        local exit_flag=$((1 - $(echo "$entry" | awk '{print $NF}')))  # Invert the value

        printf "  %$(($max_word_len))s: %s\n" "$word" "$description" >&$output_redirect
    done
    printf "\n" >&$output_redirect

    # -----------------------------------------------------------------------------
    # @brief Flag Arguments section
    # -----------------------------------------------------------------------------
    printf "Flag Arguments:\n" >&$output_redirect
    local max_flag_len=0
    for entry in "${options_list[@]}"; do
        local flag=$(echo "$entry" | cut -d' ' -f1)
        local flag_len=${#flag}
        if (( flag_len > max_flag_len )); then
            max_flag_len=$flag_len
        fi
    done

    # Second pass to print with padded formatting for flag arguments
    for entry in "${options_list[@]}"; do
        local flag=$(echo "$entry" | cut -d' ' -f1)
        local complex_flag=$(echo "$entry" | cut -d' ' -f2)
        local function=$(echo "$entry" | cut -d' ' -f3)
        local description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
        local exit_flag=$((1 - $(echo "$entry" | awk '{print $NF}')))  # Invert the value

        printf "  %$(($max_flag_len))s: %s\n" "$(echo "$flag" | tr '|' ' ')" "$description" >&$output_redirect
    done

    debug_end "$debug"
    return 0
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
