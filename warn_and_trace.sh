#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'
set +o noclobber

readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-true}"   # Default to false if not set.
declare THIS_SCRIPT="${THIS_SCRIPT:-$(basename "$0")}"  # Default to the script's name if not set.
[[ -p /dev/stdin ]] && THIS_SCRIPT="stack_trace.sh"     # Update if being piped

# Do not carry this over.
pad_with_spaces() {
    # Declare locals
    local number="$1"       # Input number (mandatory)
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
    return 0
}

# Do not carry this
add_period() {
    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        printf "Input to add_period cannot be empty.\n" >&2
        return 1
    fi

    # Add a trailing period if it's missing
    if [[ "$input" != *. ]]; then
        input="$input."
    fi

    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Wraps primary and secondary messages with ellipses for overflow lines.
# @details Ensures that the primary and secondary messages fit within the 
#          specified line width. If a line overflows, ellipses are appended 
#          (or prepended for continuation lines). The processed messages are 
#          returned as a single string, separated by an ASCII delimiter (␞).
#
# @param $1 [required] Maximum width of each line (numeric).
# @param $2 [required] Primary message string.
# @param $3 [required] Secondary message string.
#
# @global None.
#
# @throws None.
#
# @return A single string containing the formatted primary, overflow, and 
#         secondary messages, separated by the ASCII delimiter ␞.
#
# @example
# result=$(wrap_messages 50 "Primary message" "Secondary message")
# echo "$result"
# -----------------------------------------------------------------------------
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

stack_trace() {
    # Determine level and message
    local level="${1:-INFO}"  # Default to INFO if $1 is not provided
    local message=""

    # Check if $1 is a valid level, otherwise treat it as a message
    case "$level" in
        DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL)
            shift
            ;;
        *)
            # If $1 is not a valid level, treat it as the beginning of the message
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
    function_name="$(echo "$raw_function_name" | sed -E 's/_/ /g; s/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')"

    # Define a helper function to determine if a function should be skipped
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

    # Iterate through the stack to identify the "top of heap" and build the stack
    local displayed_stack=()
    local longest_length=0 # Track the longest function name length

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
        displayed_stack=("$(printf "%s|%s" "$func()" "$line")" "${displayed_stack[@]}")
    done

    # Fallback to an empty string on error with colors
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)
    
    # Foreground colors
    local fgred=$(safe_tput setaf 1)
    local fggrn=$(safe_tput setaf 2)
    local fgylw=$(safe_tput setaf 3)
    local fgblu=$(safe_tput setaf 4)
    local fgmag=$(safe_tput setaf 5)
    local fgcyn=$(safe_tput setaf 6)
    local fggld=$(safe_tput setaf 220)
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow
    local fgrst==$(safe_tput setaf 39)

    # Determine color and label based on the log level
    local color label
    case "$level" in
        DEBUG) color=${fgcyn}; label="[DEBUG]";;
        INFO) color=${fggrn}; label="[INFO ]";;
        WARN|WARNING) color=${fggld}; label="[WARN ]";;
        ERROR) color=${fgmag}; label="[ERROR]";;
        CRITICAL) color=${fgred}; label="[CRIT ]";;
    esac

    # Create header
    local dash_count=$(( (width - ${#function_name} - 2) / 2 ))
    local header header_l header_r
    # Create left and right padding separately
    header_l="$(printf '%*s' "$dash_count" | tr ' ' "$char")"
    header_r="$header_l"

    # Add an extra character to the right padding if the width is odd
    [[ $(( (width - ${#function_name}) % 2 )) -eq 1 ]] && header_r="${header_r}${char}"

    # Combine the parts into the full header
    header=$(
        printf "%b%s%b %b%b%s%b %b%s%b" \
        "${color}" \
        "${header_l}" \
        "${reset}" \
        "${color}" \
        "${bold}" \
        "${function_name}" \
        "${reset}" \
        "${color}" \
        "${header_r}" \
        "${reset}"
    ) 
 
    # Add "Details:" to the message
    message=$(add_period "$message")
    message=$(
        printf "%b%bDetails: %b%b%s%b" \
        "${color}" \
        "${bold}" \
        "${reset}" \
        "${color}" \
        "${message}" \
        "${reset}" \
    )

    # Strip out terminal codes for length calculation
    stripped_message=$(echo "$message" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')

    # If the stripped message exceeds 60 characters, split it at word boundaries
    if [[ ${#stripped_message} -gt 60 ]]; then
        message=$(echo "$stripped_message" | fold -s -w 60)
    fi

    # Create a plain footer without color codes
    local footer
    footer="$(printf '%*s' "$width" "" | tr ' ' "$char")"
    # Wrap the footer in color codes, if provided
    if [[ -n "$color" ]]; then
        footer="${color}${footer}${reset}"
    fi

    # Print header
    printf "%s\n" "$header"

    # Print the message, if provided
    if [[ -n "$message" ]]; then
        printf "%b%s%b\n" "${color}" "$message" "${reset}"
    fi

    # Calculate indent for proper alignment
    local indent=$(( ($width / 2) - ((longest_length + 28) / 2) ))

    # Print the displayed stack in reverse order with correct indices
    for ((i = ${#displayed_stack[@]} - 1, idx = 0; i >= 0; i--, idx++)); do
        IFS='|' read -r func line <<< "${displayed_stack[i]}"

        # Calculate the width for the function name (longest_length + 2)
        local func_width=$((longest_length + 2))

        # Use the calculated width in the printf statement
        printf "%b%*s [%d] Function: %-*s Line: %4s%b\n" \
            "${color}" "$indent" ">" "$idx" "$func_width" "$func" "$line" "${reset}"
    done

    # Print footer
    printf "%b%s%b\n\n" "${color}${bold}" "$footer" "${reset}"
    return
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

    # Fallback to an empty string on error with colors
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset=$(safe_tput sgr0)
    local bold=$(safe_tput bold)
    
    # Foreground colors
    local fgred=$(safe_tput setaf 1)
    local fggrn=$(safe_tput setaf 2)
    local fgylw=$(safe_tput setaf 3)
    local fgblu=$(safe_tput setaf 4)
    local fgmag=$(safe_tput setaf 5)
    local fgcyn=$(safe_tput setaf 6)
    local fggld=$(safe_tput setaf 220)
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow
    local fgrst==$(safe_tput setaf 39)

    # Helper to create a prefixed string
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " "${bold}${color}" "$label" "${reset}" "${bold}" "$script" "$func_name" "$caller_line" "${reset}"
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
        details=$(add_period $details)
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

declare lorem="Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

warn 999 "With code"

warn

warn 7

warn 1 "This is a warning message that will end with a code."

warn "This is a warning message that has no code but is super long and has extended details." "$lorem"
