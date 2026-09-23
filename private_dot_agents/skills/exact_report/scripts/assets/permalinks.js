// Source permalinks: materialise ⎘ links from data-f / data-l, pinned to a commit.
// Fill REPO + SHA when the report cites code; delete this block if it cites none.
var REPO = "{{https://github.com/owner/repo}}", SHA = "{{commit-sha-or-branch}}";
document.querySelectorAll("a.src").forEach(function(a){
  var f = a.getAttribute("data-f"); if(!f) return;
  var l = a.getAttribute("data-l") || "", hash = "";
  if(l){ var p = l.split("-"); hash = p.length>1 ? ("#L"+p[0]+"-L"+p[1]) : ("#L"+p[0]); }
  var enc = f.split("/").map(encodeURIComponent).join("/");
  var sha = a.getAttribute("data-sha") || SHA;          // data-sha overrides per-link
  a.href = REPO + "/blob/" + sha + "/" + enc + hash;
  a.target = "_blank"; a.rel = "noopener";
  if(!a.textContent.trim()){ var n = f.split("/").pop(); a.textContent = n + (l ? (":"+l) : ""); }
});
