# Defined in - @ line 1
function project-patch --wraps='diff' --description 'alias project-patch=diff -rupN'
  diff -rupN $argv;
end
