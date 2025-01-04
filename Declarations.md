<!-- omit in toc -->
# Global Declarations

Many of these will be used to define how you prefer your script to operate.  

* **[Global Customizable Declarations - Static](#global-customizable-declarations---static):** These are set in the script header to define functionality and are not changed programmatically.
* **[Global Customizable Declarations - Dynamic](#global-customizable-declarations---dynamic):** These are set in the script header to default values in most cases and may be updated by the script * programmatically. An example is `SEM_VER`; the script will formulate the current semantic version based on Git environment information if executed from a * header.
* **[Global Placeholder Declarations](#global-placeholder-declarations):** These are defined as globals in the script header to be set and used programmatically within the script.
* **[Escape Sequences (ANSI Colors)](#escape-sequences-ansi-colors):** These are values used for test/log colorization and may also be used in your own strings. e.g.:

 ``` bash
    local text_string="${FGRED}${BOLD}This is a text string.${RESET}"
    logD "$text_string"
 ```

 Produces:

 ![Image of a formatted text string](images/formatted_text_string.png)

<!-- omit in toc -->
## Table of Contents
- [Global Customizable Declarations - Static](#global-customizable-declarations---static)
- [Global Customizable Declarations - Dynamic](#global-customizable-declarations---dynamic)
- [Global Placeholder Declarations](#global-placeholder-declarations)
- [Escape Sequences (ANSI Colors)](#escape-sequences-ansi-colors)

## Global Customizable Declarations - Static

These may be set in the script header or runtime environment.

* `FALLBACK_SCRIPT_NAME`: Sometimes, one runs a script by piping it from the Internet (GitHub, for example.) In this case, we can know it was piped, but we cannot know its name. This lets us see the script name in various display areas and set the default log name.
* `DRY_RUN`: This is a feature flag of sorts. Apt packages, for instance, are feature-toggled to allow the script to run and not make any changes to the system. You can wrap your own functions in an if-block using this variable. Generally, this stays set to "false" and is set in the environment, but you can do whatever you like.
* **Menu Variables**:  There are four variables configured now. However, these may be expanded to meet your needs. They are declared in the file header and defined later in the script;
    * `MENU_ITEMS`"  This list of zero to many potential menu items may be pulled into a menu or sub-menu.
 ``` bash
      # -----------------------------------------------------------------------------
      # @var MENU_ITEMS
      # @brief Stores menu item details.
      # @details Keys are unique identifiers for menu items, and values are formatted
      #          strings containing display names and the corresponding function to call.
      # -----------------------------------------------------------------------------
      MENU_ITEMS["option_one"]="Option One"
      MENU_ITEMS["option_two"]="Option Two"
      MENU_ITEMS["option_three"]="Option Three"
      MENU_ITEMS["display_sub_menu"]="Display Sub Menu"
      MENU_ITEMS["display_main_menu"]="Display Main Menu"
 ```
    * `MAIN_MENU`: The items in the "main menu."  These are the names of the `MENU_ITEM` array index, which is also the function name it will call when executed. In the examples provided, qa given menu is called with `display_menu MAIN_MENU[@] "$debug"` where `display_menu()` is an existing function and `MAIN_MENU` is the array we have created that passes into the function to be parsed and displayed.
 ``` bash
      # -----------------------------------------------------------------------------
      # @var MAIN_MENU
      # @brief Array defining the main menu options.
      # @details Contains keys that correspond to the `MENU_ITEMS` associative array.
      #          These keys define the options available in the main menu.
      # -----------------------------------------------------------------------------
      MAIN_MENU=(
          "option_one"
          "option_two"
          "display_sub_menu"
      )
 ```
    * `SUB_MENU`: In the examples of `MAIN_MENU` is a menu that can be displayed from an initial menu. It is named, defined, and instantiated in the same way:
 ``` bash
      # -----------------------------------------------------------------------------
      # @var SUB_MENU
      # @brief Array defining the sub-menu options.
      # @details Contains keys that correspond to the `MENU_ITEMS` associative array.
      #          These keys define the options available in the sub-menu.
      # -----------------------------------------------------------------------------
      SUB_MENU=(
          "option_three"
          "display_main_menu"
      )
 ```
* **Command Line Arguments** There are two variables defined. They are declared in the file header and defined later in the script. Argument parsing and usage instructions both leverage these to automatically extend this functionality.
    * `ARGUMENTS_LIST`: The list of single-word arguments defined in a list:
 ``` bash
        # -----------------------------------------------------------------------------
        # @brief List of word arguments.
        # @details Each entry in the list corresponds to a word argument and contains
        #          the argument name, the associated function, a brief description,
        #          and a flag indicating whether the function should exit after
        #          processing the argument.
        #
        # @var ARGUMENTS_LIST
        # @brief List of word arguments.
        # @details The list holds the word arguments, their corresponding functions,
        #          descriptions, and exit flags. Each word argument triggers a
        #          specific function when encountered on the command line.
        # -----------------------------------------------------------------------------
        ARGUMENTS_LIST=(
            "word1 word_arg_one Handles word argument one 0"
            "word2 word_arg_two Handles word argument two 1"
        )
 ```
    * `OPTIONS_LIST`: The list of -f|--flagged options with or without secondary arguments defined in a list:
 ``` bash
        # -----------------------------------------------------------------------------
        # @brief List of flagged arguments.
        # @details Each entry in the list corresponds to a flagged argument containing
        #          the flag(s), a complex flag indicating if a secondary argument is
        #          required, the associated function, a description, and an exit flag
        #          indicating whether the function should terminate after processing.
        #
        # @var OPTIONS_LIST
        # @brief List of flagged arguments.
        # @details This list holds the flags (which may include multiple pipe-delimited
        #          options), the associated function to call, whether a secondary
        #          argument is required, and whether the function should exit after
        #          processing.
        # -----------------------------------------------------------------------------
        OPTIONS_LIST=(
            "-1|--flag_1 0 flag_arg_one Handles flag_arg_one 0"
            "-2|--flag_2 0 flag_arg_two Handles flag_arg_two 1"
            "-3|--flag_3 1 flag_arg_tre Handles flag_arg_tre 0"
            "-4|--flag_4 1 flag_arg_fwr Handles flag_arg_fwr 1"
            "-h|--help 0 usage Show these instructions 1"
        )
 ```

* `GIT_DIRS`: This is a list of directories passed to the Git functions to download them specifically (as opposed to a clone) from a Git repo.
* `MENU_HEADER`: This is the default menu header for the application.
* `TERSE`: This is a capture guard that removes some verbosity and can be checked to remove others. It is intended to be used when a script or application is automated and choices and verbiage are unnecessary.
* `REQUIRE_SUDO`: If true, the script will require that it be executed with `sudo` privileges.
* `REQUIRE_INTERNET`: If true, the script will validate the system has Internet connectivity. It will check for Google.com and 1.1.1.1.
* `MIN_BASH_VERSION`: The minimum bash version is required. Generally, 4 is about as low as we should support; 5 is probably a better choice for new work. Use "none" for no version-specific requirements.
* `MIN_OS`: The minimum version of the OS. This works for Debian and probably Ubuntu. As written, this will check `/etc/os-release` for `VERSION_ID` and validate it against the requirements.
* `MAX_OS`: The maximum version of the OS supported, or -1 if there is no max.
* `SUPPORTED_BITNESS`: `32`, `64`, or `both` are supported as enforceable options.
* `SUPPORTED_MODELS`: This is very specifically for Raspbian. In my case, I needed to exclude some of the compute models and the Pi 5, so these are marked as "Not Supported" within the array.
* `LOG_OUTPUT`:  One of `file`, `console`, or `both`. Controls the default destination of the logging (e.g., `logD()`) functions.
* `USE_CONSOLE`: This can be used programmatically to turn off the console logging. toggle_console_log will use this and `CONSOLE_STATE` to temporarily turn the console logging on or off.
* `LOG_LEVEL`: The lowest console level that will print. One of:
    * `"DEBUG"`: Detailed messages for troubleshooting and development.
    * `"INFO"`: Informational messages about normal operations.
    * `"WARN"`: Warning messages indicating potential issues.
    * `"ERROR"`: Errors that require immediate attention.
    * `"CRITICAL"`: Critical issues that may cause the script to fail.
* `LOG_FILE`: The path and filename of the log file. If blank, it will default to the script basename.log in the user's home directory.
* `DEPENDENCIES`: A list of system dependencies (`awk`, `grep`, etc.) the script needs to function.
* `ENV_VARS_BASE`: A list of which environment variables the script expects to be present.
* `SYSTEM_READS`: System paths, such as `/etc/os-release`, that the script will need to access.
* `APT_PACKAGES`: A list of packages that will be installed if not present.
* `WARN_STACK_TRACE`: Whether to trigger a stack trace on `warn() `calls. By default, these will only trigger on `die().`

## Global Customizable Declarations - Dynamic

By default, and when `get_proj_params()` is called, these will be updated from the local Git environment. If you are not running in a Got environment, you may want to populate the default values here if you will be doing Git calls.

* `REPO_ORG="${REPO_ORG:-lbussy}"`
* `REPO_NAME="${REPO_NAME:-bash-template}"`
* `REPO_BRANCH="${REPO_BRANCH:-main}"`
* `GIT_TAG="${GIT_TAG:-1.2.0}"`
* `SEM_VER="${GIT_TAG:-1.2.0}"`
* `LOCAL_REPO_DIR="${LOCAL_REPO_DIR:-}"`
* `LOCAL_WWW_DIR="${LOCAL_WWW_DIR:-}"`
* `LOCAL_SCRIPTS_DIR="${LOCAL_SCRIPTS_DIR:-}"`
* `GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"`
* `GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"`

## Global Placeholder Declarations

These are all derived during script execution and may be read for deterministic processing.

* `IS_PATH` - The script is being executed from a system `PATH` location.
* `IS_REPO` - The script is being executed within a Git repo.
* `USER_HOME` - The location of the actual user's home directory.
* `REAL_USER` - The user or the name of the user calling `sudo`.
* `CONSOLE_STATE` - A placeholder to remember the last console state when toggled.

## Escape Sequences (ANSI Colors)

These are used within the script, such as in logging, but may also be used for your needs since they are global.

* Utility Sequences
    * `RESET` - Resets to the default terminal appearance.
    * `BOLD` - Bolds text.
    * `SMSO` - Sets standout mode, which may differ depending on the terminal type.
    * `RMSO` - Useta standout mode.
    * `UNDERLINE` - Underlines text.
    * `NO_UNDERLINE` - Turns off underline.
    * `BLINK` - Blinks text. For the love of God, please only use this in the event of an impending nuclear strike.
    * `NO_BLINK` - Turns off blinking text mode.
    * `ITALIC` - Italicises text.
    * `NO_ITALIC` - Turns off italics.
    * `MOVE_UP` - Moves the cursor up a line (often used with `CLEAR_LINE`.)
    * `CLEAR_LINE` - Clears the current line of text.
* Foreground Colors
    * `FGBLK` - Green text
    * `FGRED` - Red text
    * `FGGRN` - Green text
    * `FGYLW` - Yellow text
    * `FGBLU` - Blue text
    * `FGMAG` - Magenta text
    * `FGCYN` - Cyan text
    * `FGWHT` - White text
    * `FGGLD` - Gold text
    * `FGRST` - Reset FG color
* Background Colors
    * `BGBLK` - Black background
    * `BGRED` - Red background
    * `BGGRN` - Green background
    * `BGYLW` - Yellow background
    * `BGBLU` - Blue background
    * `BGMAG` - Magenta background
    * `BGCYN` - Cyan background
    * `BGWHT` - White background
    * `BGRST` - Background color reset
