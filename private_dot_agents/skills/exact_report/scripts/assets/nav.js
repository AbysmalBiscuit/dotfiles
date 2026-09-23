// Mobile TOC toggle.
var toc = document.querySelector(".toc"), btn = document.getElementById("menu-btn");
if(btn && toc){
  btn.addEventListener("click", function(){ toc.classList.toggle("open"); });
  toc.addEventListener("click", function(e){
    if(e.target.tagName==="A" && window.innerWidth<=860) toc.classList.remove("open");
  });
}
// Scrollspy: highlight the current section (supports multiple links per id).
if(toc){
  var links = [].slice.call(toc.querySelectorAll('a[href^="#"]')), map = {};
  links.forEach(function(a){ var id=a.getAttribute("href").slice(1); (map[id]=map[id]||[]).push(a); });
  var targets = Object.keys(map).map(function(id){ return document.getElementById(id); }).filter(Boolean);
  function spy(){
    var y = window.scrollY + 120, cur = null;
    targets.forEach(function(t){ if(t.offsetTop <= y) cur = t.id; });
    links.forEach(function(a){ a.classList.remove("active"); });
    if(cur && map[cur]) map[cur].forEach(function(a){ a.classList.add("active"); });
  }
  window.addEventListener("scroll", spy, {passive:true});
  window.addEventListener("resize", spy); spy();
}
