# Defined in - @ line 1
function wanip --wraps='dig' --description 'alias wanip=dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com'
  dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com $argv;
end
