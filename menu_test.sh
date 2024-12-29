#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'
set +o noclobber

# -----------------------------------------------------------------------------
# Declare Menu Variables
# -----------------------------------------------------------------------------
declare -A MENU_ITEMS       # Associative array of menu items
declare -a MAIN_MENU        # Array defining the main menu screen
declare -a SUB_MENU         # Array defining the sub-menu screen
MENU_HEADER="Welcome to the Menu-Driven Script"  # Global menu header

# -----------------------------------------------------------------------------
# @var MENU_ITEMS
# @brief Stores menu item details.
# @details Keys are unique identifiers for menu items, and values are formatted
#          strings containing display name and function to call.
# -----------------------------------------------------------------------------
MENU_ITEMS["option_one"]="Option One"
MENU_ITEMS["option_two"]="Option Two"
MENU_ITEMS["option_three"]="Option Three"
MENU_ITEMS["display_sub_menu"]="Display Sub Menu"
MENU_ITEMS["display_main_menu"]="Display Main Menu"

# -----------------------------------------------------------------------------
# @var MAIN_MENU
# @brief Array defining the main menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the main menu.
#
# @example
# MAIN_MENU=(
#     "option_one"
#     "option_two"
#     "display_sub_menu"
# )
# -----------------------------------------------------------------------------
MAIN_MENU=(
    "option_one"
    "option_two"
    "display_sub_menu"
)

# -----------------------------------------------------------------------------
# @var SUB_MENU
# @brief Array defining the sub-menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the sub-menu.
#
# @example
# SUB_MENU=(
#     "option_three"
#     "display_main_menu"
# )
# -----------------------------------------------------------------------------
SUB_MENU=(
    "option_three"
    "display_main_menu"
)

# -----------------------------------------------------------------------------
# @brief Sets up and logs debug information for the calling function.
# @details Checks if the "debug" flag is passed in the arguments, logs the
#          function call details (function name, caller name, and caller line)
#          if debugging is enabled, and returns the debug status.
#
# @param $@ Arguments passed to the function.
#
# @return Outputs "debug" if the "debug" flag is detected; otherwise, outputs
#         an empty string.
#
# @global FUNCNAME Used to get the current and caller function names.
# @global BASH_LINENO Used to get the caller line number.
#
# @example
# Usage in a function:
#   local debug
#   debug=$(start_debug "$@")
# -----------------------------------------------------------------------------
start_debug() {
    # Find "debug" in arguments
    local debug=""
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            shift  # Remove "debug" from arguments
            break
        fi
    done
    local func_name="${FUNCNAME[1]}"
    local caller_name="${FUNCNAME[2]}"
    local caller_line="${BASH_LINENO[1]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Return debug flag if present
    printf "%s\n" "${debug:-}"
}

# -----------------------------------------------------------------------------
# @brief Logs debug information when a function exits.
# @details If the "debug" flag is enabled, this function logs the name of the
#          exiting function and the line number where the function exits.
#
# @param $1 Optional debug flag. If "debug" is provided, debug information is printed.
#
# @global FUNCNAME Used to get the name of the exiting function.
# @global BASH_LINENO Used to get the line number of the function exit.
#
# @example
# Usage in a function:
#   end_debug "$debug"
# -----------------------------------------------------------------------------
end_debug() {
    # Debug log: function exit
    local debug="${1:-}"
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()' at line number %d.\n" "${FUNCNAME[1]}" "${BASH_LINENO[0]}" >&2
}

# -----------------------------------------------------------------------------
# @brief Pauses execution and waits for user input to continue.
# @details This function displays a message prompting the user to press any key
#          to continue. It waits for a single key press, then resumes execution.
#
# @example
# pause
# -----------------------------------------------------------------------------
pause() {
    printf "Press any key to continue.\n"
    read -n 1 -sr < /dev/tty || true
    printf "\n"
}

# -----------------------------------------------------------------------------
# @brief Test function one
# -----------------------------------------------------------------------------
option_one() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Do stuff
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Test function otwo
# -----------------------------------------------------------------------------
option_two() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Do stuff
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Test function three
# -----------------------------------------------------------------------------
option_three() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Do stuff
    printf "\nRunning %s().\n" "$FUNCNAME"
    pause

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays a menu based on the given menu array.
# @details The menu items are numbered sequentially and prompt the user for input.
#
# @param $1 Array of menu keys to display.
# @param $2 Debug flag for optional debug output.
#
# @global MENU_ITEMS Uses this global array to retrieve menu details.
# @global MENU_HEADER Prints the global menu header.
#
# @throws Prints an error message if an invalid choice is made.
#
# @return Executes the corresponding function of the selected menu item.
# -----------------------------------------------------------------------------
display_menu() {
    # Debug declarations
    local debug=$(start_debug "$@")

    local choice
    local i=1
    local menu_array=("${!1}")  # Array of menu keys to display

    printf "%s\n\n" "$MENU_HEADER"
    printf "Please select an option:\n\n"
    for func in "${menu_array[@]}"; do
        # Fixed-width format for consistent alignment
        printf "%-4d%-30s\n" "$i" "${MENU_ITEMS[$func]}"
        ((i++))
    done
    printf "%-4d%-30s\n" 0 "Exit"

    # Read user choice
    printf "\nEnter your choice: "
    read -n 1 -sr choice < /dev/tty || true
    printf "%s\n" "$choice"

    # Validate input
    if [[ -z "$choice" ]]; then
        printf "No input provided. Please enter a valid choice.\n"
        return
    elif [[ "$choice" =~ ^[0-9]$ ]]; then
        if [[ "$choice" -eq 0 ]]; then
            printf "\nExiting.\n"
            end_debug "$debug"
            exit 0
        elif [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
            local func="${menu_array[choice-1]}"
            "$func" "$debug"
        else
            printf "Invalid choice. Please try again.\n"
        fi
    else
        printf "Invalid input. Please enter a number.\n"
    fi

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the main menu.
# @details Calls the `display_menu` function with the main menu array.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the main menu array.
# -----------------------------------------------------------------------------
display_main_menu() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Clear screen
    clear
    # Display the menu
    display_menu MAIN_MENU[@] "$debug"

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the sub-menu.
# @details Calls the `display_menu` function with the sub-menu array. Loops
#          within the sub-menu until the user chooses to exit.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the sub-menu array in a loop.
# -----------------------------------------------------------------------------
display_sub_menu() {
    # Debug declarations
    local debug=$(start_debug "$@")

    while true; do
        # Clear screen
        clear
        # Display the menu
        display_menu SUB_MENU[@] "$debug"
    done

    # Debug log: function exit
    end_debug "$debug"
}

# -----------------------------------------------------------------------------
# @brief Entry point for the script.
# @details Initializes debugging if the "debug" flag is passed, starts the
#          main menu loop, and ensures proper debug logging upon exit.
#
# @param $@ Arguments passed to the script. Pass "debug" for debug mode.
#
# @example
# Execute the script with:
#   ./script_name.sh debug
# -----------------------------------------------------------------------------
main() {
    # Debug declarations
    local debug=$(start_debug "$@")

    # Main script execution starts here
    while true; do
        display_main_menu "$debug"
    done

    # Debug log: function exit
    end_debug "$debug"
}

main "$@"
exit 0
