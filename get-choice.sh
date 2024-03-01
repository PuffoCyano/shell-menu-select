#!/bin/bash

CHAR__GREEN='\033[0;32m'
CHAR__RED='\033[0;31m'
CHAR__RESET='\033[0m'
CHAR__BOLD='\033[1m'
CHAR__UNDERLINE='\033[4m'
menuStr=""
returnOrExit=""
LINES=$(tput lines)
COLS=$(tput cols)

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
  if [[ $1 = true ]]; then
    local msgLineCount=$((itemsLength*2+3))
  else
    local msgLineCount=$((itemsLength+2))
  fi
  # moves the cursor up N lines so the output overwrites it
  echo -en "\033[${msgLineCount}A"

  # clear to end of screen to ensure there's no text left behind from previous input
  [ $2 ] && tput ed
}

function renderMenu {
  local start=0
  local selector=""
  local instruction="$1"
  local selectedIndex=$2
  local listLength=$itemsLength
  local firstLine="$5"
  local middleLine="$6"
  local lastLine="$7"
  local showHeader="$8"

  local drawTable=true
  if [[ $firstLine = "" ]]; then
    drawTable=false
  fi

  menuStr="\n ${CHAR__BOLD}$instruction${CHAR__RESET} (Q to exit, C to continue without selection)\n"

  if [[ $drawTable = true ]]; then
    menuStr+="\n $firstLine"
  fi

  if [ $3 -ne 0 ]; then
    listLength=$3

    if [ $selectedIndex -ge $listLength ]; then
      start=$(($selectedIndex+1-$listLength))
      listLength=$(($selectedIndex+1))
    fi
  fi

  for (( i=$start; i<$listLength; i++ )); do
    local currItem="${matrix[$i,0]}"
    currItemLength=${#matrixNoColors[$i,0]}
    if [[ $showHeader = true ]]; then
      index=$((i-1))
    else
      index=$i
    fi
    local startSpace=0
    local endSpace=${currItemLength}
    if [[ $i = $selectedIndex ]]; then
      currentSelection="${currItem}"
      selector="${CHAR__GREEN}ᐅ${CHAR__RESET}"
      currItem="${CHAR__GREEN}${matrixNoColors[$i,0]}${CHAR__RESET}"
      optionIndex="${CHAR__GREEN}${index})${CHAR__RESET}"
    else
      if [[ $i = 0 && $showHeader = true ]]; then
        selector=" "
        optionIndex="  "
        currItem="${CHAR__UNDERLINE}${CHAR__BOLD}$currItem${CHAR__RESET}"
        local diff=$((${#colSpaces[0]}-currItemLength))
        local mid=$((diff/2))
        (( diff != 0 )) && startSpace=$((mid-(1-diff%2)))
        (( diff != 0 )) && endSpace=$((${#colSpaces[0]}-mid-1))
      else
        selector=" "
        optionIndex="${index})"
      fi
    fi
    if [[ $i -ge 10 ]]; then
      offset=""
    else
      offset=" "
    fi
    currItem="${optionIndex} ${colSpaces[0]:0:startSpace}${currItem}${colSpaces[0]:endSpace}"
    if [[ $drawTable = true ]]; then
      # Loop for columns to complete row item
      for (( j=1; j<${#colSpaces[@]}; j++)); do
        local newCol="${matrix[$i,$j]}"
        currItemLength=${#matrixNoColors[$i,$j]}
        endSpace=${currItemLength}
        if [[ $i = 0 && $showHeader = true ]]; then
          newCol="${CHAR__UNDERLINE}${CHAR__BOLD}$newCol${CHAR__RESET}"
          local diff=$((${#colSpaces[$j]}-currItemLength))
          local mid=$((diff/2))
          (( diff != 0 )) && startSpace=$((mid-(1-diff%2)))
          (( diff != 0 )) && endSpace=$((${#colSpaces[$j]}-mid-1))
        fi
        currItem="${currItem}${offset}│ ${colSpaces[$j]:0:startSpace}${newCol}${colSpaces[$j]:endSpace}"
      done
    fi

    if [[ $drawTable = true ]]; then
      menuStr+="\n │${selector} ${currItem}${offset}│"
      if [[ $i -ne  $((listLength-1)) ]]; then
        menuStr+="\n $middleLine"
      fi
    else
      menuStr+="\n ${selector} ${currItem}${offset}"
    fi
  done

  if [[ $drawTable = true ]]; then
    menuStr+="\n $lastLine"
  fi

  # whether or not to overwrite the previous menu output
  [ $4 ] && [ $4 = true ] && clearLastMenu $drawTable

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
  echo "  -t, --table              Display menu in table style, otherwise display classic list menu."
  echo "  -sh, --showHeader        Show first row as header of the table."
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
    if [[ $1 = true ]]; then
      selectedChoiceIndex="$((selectedIndex-1))"
    else
      selectedChoiceIndex="${selectedIndex}"
    fi
  fi
}

function getChoice {
  local KEY__ARROW_UP=$(echo -e "[A")
  local KEY__ARROW_DOWN=$(echo -e "[B")
  local KEY__ENTER=$(echo -e "\n")
  local KEY__QUIT=$(echo -e "q")
  local KEY__CONTINUE=$(echo -e "c")
  local captureInput=true
  local displayHelp=false
  local tableStyle=false
  local showHeader=false
  local maxViewable=0
  local instruction="Select an item from the list:"
  local selectedIndex=0
  declare -A matrix=()
  declare -A matrixNoColors=()
  declare colSpaces=()

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
      -t|--table)
        tableStyle=true
        shift
        ;;
      -sh|--showHeader)
        showHeader=true
        shift
        ;;
      *)
        remainingArgs+=("$1")
        shift
        ;;
    esac
  done

  if [[ $showHeader = true ]]; then selectedIndex=$((selectedIndex+1)); fi

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

  (( selectedIndex >= itemsLength )) && selectedIndex=$((itemsLength-1))

  local colWidths=()
  local longest=0
  local line0=""
  local line1=""
  local line2=""
  local firstLine=""
  local middleLine=""
  local lastLine=""


  if [ $tableStyle = true ]; then
    # Prepare all variable for table style
    for (( i=0; i<$itemsLength; i++ )); do
      IFS='|' read -ra splitted <<< "${menuItems[i]}"
      for (( j=0; j<${#splitted}; j++ )); do
        matrix[$i,$j]="${splitted[j]}"
        itemWithoutColor=$(echo -e "${splitted[j]}" | sed "s/$(echo -e "\e")[^m]*m//g")
        matrixNoColors[$i,$j]=${itemWithoutColor}
        if (( ${#itemWithoutColor} > colWidths[j] )); then
          colWidths[j]=${#itemWithoutColor}
        fi
      done
    done
    # Prepare main arguments to pass in renderMenu to improve performance of that function
    longest=$((5*(${#colWidths[@]}-1)))
    for (( i=0; i<${#colWidths[@]}; i++)); do
      local factor=8
      if (( i != 0 )); then
        factor=4
      fi
      # Get the longest item from the list so that we know how many spaces to add
      # to ensure there's no overlap from longer items when a list is scrolling up or down.
      colSpaces[$i]=$(printf ' %.0s' $(eval "echo {1.."$((${colWidths[i]}))"}"))
      longest=$((longest+colWidths[i]))
      firstLineSeparator="┬"
      middleLineSeparator="┼"
      lastLineSeparator="┴"
      if (( i == ${#colWidths[@]}-1 )); then
        firstLineSeparator=""
        middleLineSeparator=""
        lastLineSeparator=""
      fi
      line0+=$(printf "%-$((colWidths[i]+factor))s%s" "─" "$firstLineSeparator")
      line1+=$(printf "%-$((colWidths[i]+factor))s%s" "─" "$middleLineSeparator")
      line2+=$(printf "%-$((colWidths[i]+factor))s%s" "─" "$lastLineSeparator")
    done
    firstLine=$(echo -n "╭${line0// /─}╮")
    middleLine=$(echo -n "├${line1// /─}┤")
    lastLine=$(echo -n "╰${line2// /─}╯")
  else
    # Prepare all variable for simple menu
    for (( i=0; i<$itemsLength; i++ )); do
      matrix[$i,0]=${menuItems[$i]}
      itemWithoutColor=$(echo -e "${menuItems[i]}" | sed "s/$(echo -e "\e")[^m]*m//g")
      matrixNoColors[$i,0]=${itemWithoutColor}
    done
  fi

  local menuLength=$((itemsLength*2+1))
  if [[ $menuLength -gt $LINES ]]; then
    printf "\033[8;$((menuLength+20));${COLS}t"
  fi

  renderMenu "$instruction" $selectedIndex $maxViewable false "$firstLine" "$middleLine" "$lastLine" $showHeader
  hideCursor

  while $captureInput; do
    read -rsn1 key # `3` captures the escape (\033'), bracket ([), & type (A) characters. `1` captures only the first char of those described previously
    if [[ "$key" = $'\E' ]]; then
        read -rsn2 key
        case "$key" in
          "$KEY__ARROW_UP")
            selectedIndex=$((selectedIndex-1))
            if [[ $selectedIndex -lt 0 || ($showHeader = true && $selectedIndex -eq 0) ]]; then selectedIndex=$((itemsLength-1)); fi

            renderMenu "$instruction" $selectedIndex $maxViewable true "$firstLine" "$middleLine" "$lastLine" $showHeader
            ;;

          "$KEY__ARROW_DOWN")
            firstValue=0
            if [[ $showHeader = true ]]; then firstValue=1; fi
            selectedIndex=$((selectedIndex+1))
            (( $selectedIndex == $itemsLength )) && selectedIndex=$firstValue

            renderMenu "$instruction" $selectedIndex $maxViewable true "$firstLine" "$middleLine" "$lastLine" $showHeader
            ;;

          "$KEY__ENTER")
            handleEnterKey $showHeader
            ;;
        esac
    else
      case "$key" in
        "$KEY__ENTER")
          handleEnterKey $showHeader
          ;;
        "$KEY__QUIT")
          echo ""
          echo "Quit..."
          showCursor
          $returnOrExit 0
          ;;
        "$KEY__CONTINUE")
          # Continue without exit from script; this is useful when you use getChoice into a loop
          echo ""
          echo "Continue..."
          showCursor
          captureInput=false
          ;;
        *)
          if [[ $showHeader = true ]]; then addend=1; else addend=0; fi
          if [[ -n ${key//[0-9]/} ]];
          then
            selectedIndex=0
          else
            read -rsn1 -t 0.2 unit
            if [[ $unit ]] && [[ $unit =~ ^-?[0-9]+$ ]]; then
              number=${key}${unit}
            else
              number=${key}
            fi
            selectedIndex=${number}
            (( selectedIndex+addend >= itemsLength )) && selectedIndex=0
          fi
          selectedIndex=$((selectedIndex+addend))
          renderMenu "$instruction" $selectedIndex $maxViewable true "$firstLine" "$middleLine" "$lastLine" $showHeader
          ;;
      esac
    fi
  done
}