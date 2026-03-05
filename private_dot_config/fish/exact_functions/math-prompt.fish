#!/bin/fish
# Open a prompt for doing math calculations.
function math-prompt --wraps math --description "Open a prompt for doing math calculations."
  while true
    read -P '[math]$ ' input
    switch "$input"
      case ""
        echo "No input received."
        echo "Type 'h' or 'help' to see math help documentation."
        echo "Press CTRL+C to exit the math prompt."
      case "h" "help"
        math --help
      case "*"
        math $argv -- "$input"
    end
  end
end

