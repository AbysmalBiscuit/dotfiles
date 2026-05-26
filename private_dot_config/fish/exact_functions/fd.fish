if type -q fdfind
  function fd --wraps=fdfind --description 'alias fd=fdfind'
    fdfind $argv    
  end
else if type -q fd
  :
else
  function fd
    echo "fdfind is not installed"
  end
end
