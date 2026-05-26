if type -q batcat
  function bat --wraps=batcat --description 'alias bat=batcat'
    batcat $argv
  end
else if type -q bat
  :
else
  function bat
    echo "bat is not installed"
  end
end
