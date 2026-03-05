# Defined in - @ line 1
function wanip6 --wraps='dig' --description 'alias wanip6=dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com'
  dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com $argv;
end
