// Diagram lightbox with pan/zoom. Mermaid renders async, so the SVG is read at
// click time. The clone is sized to its viewBox and moved by a transform on a
// wrapper, so zooming never re-rasterises: SVG stays sharp at any scale.
// Drop this block (and #lightbox) if the report has no diagrams.
var lb = document.getElementById("lightbox");
if(lb){
  var stage = lb.querySelector(".lb-stage"),
      pan   = lb.querySelector(".lb-pan"),
      foot  = lb.querySelector(".lb-foot"),
      cap   = lb.querySelector("#lb-caption"),
      pct   = lb.querySelector("#lb-pct");
  var scale = 1, tx = 0, ty = 0, natW = 0, natH = 0, MIN = 0.05, MAX = 12;

  function apply(){
    pan.style.transform = "translate(" + tx + "px," + ty + "px) scale(" + scale + ")";
    pct.textContent = Math.round(scale * 100) + "%";
  }
  function fitScale(){
    var r = stage.getBoundingClientRect();
    if(!natW || !natH || !r.width || !r.height) return 1;
    return Math.min((r.width - 24) / natW, (r.height - 24) / natH);
  }
  function fit(){
    var r = stage.getBoundingClientRect();
    scale = Math.max(MIN, Math.min(MAX, fitScale()));
    tx = (r.width  - natW * scale) / 2;
    ty = (r.height - natH * scale) / 2;
    apply();
  }
  // Zoom about a fixed point in stage coordinates, so what is under the
  // cursor (or the stage centre, for the buttons) stays put.
  function zoomAt(cx, cy, factor){
    var next = Math.max(MIN, Math.min(MAX, scale * factor));
    if(next === scale) return;
    tx = cx - (cx - tx) * (next / scale);
    ty = cy - (cy - ty) * (next / scale);
    scale = next;
    apply();
  }
  function zoomCentre(factor){
    var r = stage.getBoundingClientRect();
    zoomAt(r.width / 2, r.height / 2, factor);
  }
  function setScale(target){
    var r = stage.getBoundingClientRect();
    zoomAt(r.width / 2, r.height / 2, target / scale);
  }
  function close(){
    lb.classList.remove("open");
    pan.innerHTML = ""; foot.innerHTML = "";
  }

  document.querySelectorAll("figure.diagram button.zoom").forEach(function(btn){
    btn.addEventListener("click", function(){
      var fig = btn.closest("figure.diagram");
      var svg = fig.querySelector("pre.mermaid svg");
      if(!svg) return;
      var clone = svg.cloneNode(true);
      // Prefer the viewBox for intrinsic size; fall back to the rendered box.
      var vb = (clone.getAttribute("viewBox") || "").split(/[\s,]+/).map(Number);
      var box = svg.getBoundingClientRect();
      natW = (vb.length === 4 && vb[2]) ? vb[2] : box.width;
      natH = (vb.length === 4 && vb[3]) ? vb[3] : box.height;
      clone.removeAttribute("width"); clone.removeAttribute("height");
      clone.style.width = natW + "px"; clone.style.height = natH + "px";
      pan.innerHTML = ""; pan.appendChild(clone);

      foot.innerHTML = "";
      var leg = fig.querySelector(".dlegend");
      if(leg) foot.appendChild(leg.cloneNode(true));

      var fc = fig.querySelector("figcaption");
      cap.textContent = fc ? fc.textContent.replace(/\s*Click Expand to enlarge\.?\s*$/, "") : "";
      lb.classList.add("open");
      requestAnimationFrame(fit);   // stage has no size until the box is displayed
    });
  });

  lb.querySelectorAll(".lb-tools button[data-z]").forEach(function(b){
    b.addEventListener("click", function(){
      var z = b.getAttribute("data-z");
      if(z === "in")   zoomCentre(1.25);
      if(z === "out")  zoomCentre(1 / 1.25);
      if(z === "fit")  fit();
      if(z === "full") setScale(1);
    });
  });

  stage.addEventListener("wheel", function(e){
    e.preventDefault();
    var r = stage.getBoundingClientRect();
    zoomAt(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.12 : 1 / 1.12);
  }, {passive:false});

  stage.addEventListener("dblclick", function(e){
    var r = stage.getBoundingClientRect();
    zoomAt(e.clientX - r.left, e.clientY - r.top, 1.6);
  });

  var dragging = false, lastX = 0, lastY = 0;
  stage.addEventListener("pointerdown", function(e){
    dragging = true; lastX = e.clientX; lastY = e.clientY;
    stage.classList.add("dragging");
    stage.setPointerCapture(e.pointerId);
  });
  stage.addEventListener("pointermove", function(e){
    if(!dragging) return;
    tx += e.clientX - lastX; ty += e.clientY - lastY;
    lastX = e.clientX; lastY = e.clientY;
    apply();
  });
  ["pointerup","pointercancel"].forEach(function(evt){
    stage.addEventListener(evt, function(){ dragging = false; stage.classList.remove("dragging"); });
  });

  lb.querySelector(".lb-close").addEventListener("click", close);
  // Only the padding around the stage closes on click; dragging inside the
  // stage never retargets to the overlay itself.
  lb.addEventListener("click", function(e){ if(e.target === lb) close(); });
  document.addEventListener("keydown", function(e){
    if(!lb.classList.contains("open")) return;
    if(e.key === "Escape"){ close(); return; }
    if(e.key === "+" || e.key === "="){ e.preventDefault(); zoomCentre(1.25); return; }
    if(e.key === "-" || e.key === "_"){ e.preventDefault(); zoomCentre(1 / 1.25); return; }
    if(e.key === "0"){ e.preventDefault(); fit(); return; }
    // Arrows pan the view: Right moves the viewport right, so the content
    // shifts left. Shift takes a bigger stride for crossing a wide graph.
    var step = e.shiftKey ? 260 : 70, moved = true;
    switch(e.key){
      case "ArrowLeft":  tx += step; break;
      case "ArrowRight": tx -= step; break;
      case "ArrowUp":    ty += step; break;
      case "ArrowDown":  ty -= step; break;
      default: moved = false;
    }
    if(moved){ e.preventDefault(); apply(); }
  });
  window.addEventListener("resize", function(){ if(lb.classList.contains("open")) fit(); });
}
