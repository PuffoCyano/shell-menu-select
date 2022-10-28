#!/bin/bash

CHAR__GREEN='\033[0;32m'
CHAR__RED='\033[0;31m'
CHAR__RESET='\033[0m'
CHAR__BOLD='\033[1m'
menuStr=""
returnOrExit=""
LINES=$(tput lines)
COLS=$(tput cols)

if [[ $SHELL = '/bin/bash' ]] || grep -qi microsoft /proc/version; then
  # Enable arrow keys
  ENABLE_ARROW_KEYS='1'
else
  ENABLE_ARROW_KEYS='0'
fi

function hideCursor {
  printf "\033[?25l"

  # capture CTRL+C so cursor can be reset
  trap "showCursor && echo '' && ${returnOrExit} 0" SIGINT
}

function showCursor {
  printf "\033[?25h"
  trap - SIGINT
}

function clearLastMenu {
  local msgLineCount=$(printf "$menuStr" | wc -l)
  # moves the cursor up N lines so the output overwrites it
  echo -en "\033[${msgLineCount}A"

  # clear to end of screen to ensure there's no text left behind from previous input
  [ $1 ] && tput ed
}

function renderMenu {
  local start=0
  local selector=""
  local instruction="$1"
  local selectedIndex=$2
  local listLength=$itemsLength
  local spaces=$5
  local firstLine="$6"
  local middleLine="$7"
  local lastLine="$8"

  menuStr="\n ${CHAR__BOLD}$instruction${CHAR__RESET} (Q to exit)\n"

  menuStr+="\n $firstLine"

  if [ $3 -ne 0 ]; then
    listLength=$3

    if [ $selectedIndex -ge $listLength ]; then
      start=$(($selectedIndex+1-$listLength))
      listLength=$(($selectedIndex+1))
    fi
  fi

  for (( i=$start; i<$listLength; i++ )); do
    local currItem="${menuItems[i]}"
    currItemLength=${#currItem}

    if [[ $i = $selectedIndex ]]; then
      currentSelection="${currItem}"
      selector="${CHAR__GREEN}ᐅ${CHAR__RESET}"
      currItem="${CHAR__GREEN}${currItem}${CHAR__RESET}"
      optionIndex="${CHAR__GREEN}${i})${CHAR__RESET}"
    else
      selector=" "
      optionIndex="${i})"
    fi
    if [[ $i -ge 10 ]]; then
      offset=" "
    else
      offset="  "
    fi

    currItem="${optionIndex} ${spaces:0:0}${currItem}${spaces:currItemLength}${offset}"

    menuStr+="\n │${selector} ${currItem}│"

    if [[ $i -ne  $((listLength-1)) ]]; then
      menuStr+="\n $middleLine"
    fi
  done

  menuStr+="\n $lastLine"

  # whether or not to overwrite the previous menu output
  [ $4 ] && [ $4 = true ] && clearLastMenu

  printf "${menuStr}"
}

function renderHelp {
  echo;
  echo "Usage: getChoice [OPTION]..."
  echo "Renders a keyboard navigable menu with a visual indicator of what's selected."
  echo;
  echo "  -h, --help               Displays this message"
  echo "  -i, --index              The initially selected index for the options"
  echo "  -m, --max                Limit how many options are displayed"
  echo "  -o, --options            An Array of options for a user to choose from"
  echo "  -q, --query              Question or statement presented to the user"
  echo "  -v, --selectionVariable  Variable the selected choice will be saved to. Defaults to the 'selectedChoice' variable."
  echo;
  echo "Example:"
  echo "  foodOptions=(\"pizza\" \"burgers\" \"chinese\" \"sushi\" \"thai\" \"italian\" \"shit\")"
  echo;
  echo "  getChoice -q \"What do you feel like eating?\" -o foodOptions -i 6 -m 4 -v \"firstChoice\""
  echo "  printf \"\\n First choice is '\${firstChoice}'\\n\""
  echo;
  echo "  getChoice -q \"Select another option in case the first isn't available\" -o foodOptions"
  echo "  printf \"\\n Second choice is '\${selectedChoice}'\\n\""
  echo;
}

function handleEnterKey {
#  clearLastMenu true
  showCursor
  captureInput=false

  if [[ "${selectionVariable}" != "" ]]; then
    printf -v "${selectionVariable}" "${currentSelection}"
  else
    selectedChoice="${currentSelection}"
    selectedChoiceIndex="${selectedIndex}"
  fi
}

function getChoice {
  local KEY__ARROW_UP=$(echo -e "[A")
  local KEY__ARROW_DOWN=$(echo -e "[B")
  local KEY__ENTER=$(echo -e "\n")
  local KEY__QUIT=$(echo -e "q")
  local captureInput=true
  local displayHelp=false
  local maxViewable=0
  local instruction="Select an item from the list:"
  local selectedIndex=0

  unset selectedChoice
  unset selectedChoiceIndex
  unset selectionVariable

  if [[ "${PS1}" == "" ]]; then
    # running via script
    returnOrExit="exit"
  else
    # running via CLI
    returnOrExit="return"
  fi

  if [[ "${BASH}" == "" ]]; then
    printf "\n ${CHAR__RED}[ERROR] This function utilizes Bash expansion, but your current shell is \"${SHELL}\"${CHAR__RESET}\n"
    $returnOrExit 1
  elif [[ $# == 0 ]]; then
    printf "\n ${CHAR__RED}[ERROR] No arguments provided${CHAR__RESET}\n"
    renderHelp
    $returnOrExit 1
  fi

  local remainingArgs=()
  while [[ $# -gt 0 ]]; do
    local key="$1"

    case $key in
      -h|--help)
        displayHelp=true
        shift
        ;;
      -i|--index)
        selectedIndex=$2
        shift 2
        ;;
      -m|--max)
        maxViewable=$2
        shift 2
        ;;
      -o|--options)
        menuItems=$2[@]
        menuItems=("${!menuItems}")
        shift 2
        ;;
      -q|--query)
        instruction="$2"
        shift 2
        ;;
      -v|--selectionVariable)
        selectionVariable="$2"
        shift 2
        ;;
      *)
        remainingArgs+=("$1")
        shift
        ;;
    esac
  done

  # just display help
  if $displayHelp; then
    renderHelp
    $returnOrExit 0
  fi

  set -- "${remainingArgs[@]}"
  local itemsLength=${#menuItems[@]}

  # no menu items, at least 1 required
  if [[ $itemsLength -lt 1 ]]; then
    printf "\n ${CHAR__RED}[ERROR] No menu items provided${CHAR__RESET}\n"
    renderHelp
    $returnOrExit 1
  fi

  local longest=0
  # Get the longest item from the list so that we know how many spaces to add
  # to ensure there's no overlap from longer items when a list is scrolling up or down.
  for (( i=0; i<$itemsLength; i++ )); do
    if (( ${#menuItems[i]} > longest )); then
      itemWithoutColor=$(echo -e "${menuItems[i]}" | sed "s/$(echo -e "\e")[^m]*m//g")
      longest=${#itemWithoutColor}
    fi
  done

  # Prepare main arguments to pass in renderMenu to improve performance of that function
  local spaces=$(printf ' %.0s' $(eval "echo {1.."$(($longest))"}"))

  local line0=$(printf "%-$((longest+9))s" "─")
  local firstLine=$(echo -n "╭${line0// /─}╮")
  local middleLine="$(echo -n "├${line0// /─}┤")"
  local lastLine=$(echo -n "╰${line0// /─}╯")

  local menuLength=$((itemsLength*2+1))
  if [[ $menuLength -gt $LINES ]]; then
    printf "\033[8;$((menuLength+20));${COLS}t"
  fi

  renderMenu "$instruction" $selectedIndex $maxViewable false "$spaces" "$firstLine" "$middleLine" "$lastLine"
  hideCursor

  while $captureInput; do
    read -rsn1 key # `3` captures the escape (\033'), bracket ([), & type (A) characters. `1` captures only the first char of those described previously
    if [[ "$key" = $'\E' ]]; then
        read -rsn2 key
        case "$key" in
          "$KEY__ARROW_UP")
            selectedIndex=$((selectedIndex-1))
            (( $selectedIndex < 0 )) && selectedIndex=$((itemsLength-1))

            renderMenu "$instruction" $selectedIndex $maxViewable true "$spaces" "$firstLine" "$middleLine" "$lastLine"
            ;;

          "$KEY__ARROW_DOWN")
            selectedIndex=$((selectedIndex+1))
            (( $selectedIndex == $itemsLength )) && selectedIndex=0

            renderMenu "$instruction" $selectedIndex $maxViewable true "$spaces" "$firstLine" "$middleLine" "$lastLine"
            ;;

          "$KEY__ENTER")
            handleEnterKey
            ;;
        esac
    else
      case "$key" in
        "$KEY__ENTER")
          handleEnterKey
          ;;
        "$KEY__QUIT")
          echo ""
          echo "Quit..."
          showCursor
          exit 0
          ;;
        *)
          if [[ -n ${key//[0-9]/} ]];
          then
            selectedIndex=0
          else
            read -rsn1 -t 0.25 unit
            if [[ $unit ]] && [[ $unit =~ ^-?[0-9]+$ ]]; then
              number=${key}${unit}
            else
              number=${key}
            fi
            selectedIndex=${number}
            (( $selectedIndex > $itemsLength )) && selectedIndex=0
          fi
          renderMenu "$instruction" $selectedIndex $maxViewable true "$spaces" "$firstLine" "$middleLine" "$lastLine"
          ;;
      esac
    fi
  done
}