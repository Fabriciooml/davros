(function () {
  "use strict";

  var NAV = [
    ["index.html", "/overview"],
    ["apps.html", "/apps"],
    ["runbooks.html", "/runbooks"]
  ];

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  function buildShell() {
    var page = document.body.getAttribute("data-page");
    var aside = el("aside");
    var logo = el("div", "logo");
    logo.appendChild(el("span", "eye"));
    logo.appendChild(document.createTextNode("DAVROS"));
    aside.appendChild(logo);
    var nav = el("nav");
    NAV.forEach(function (item) {
      var a = el("a", item[0] === page + ".html" ? "on" : "", item[1]);
      a.href = item[0];
      nav.appendChild(a);
    });
    aside.appendChild(nav);
    document.body.insertBefore(aside, document.body.firstChild);
  }

  function fillStats(apps) {
    var namespaces = {};
    apps.forEach(function (a) { namespaces[a.namespace] = true; });
    var counts = {
      apps: apps.length,
      public: apps.filter(function (a) { return a.public; }).length,
      stateful: apps.filter(function (a) { return a.stateful; }).length,
      namespaces: Object.keys(namespaces).length
    };
    Array.prototype.forEach.call(document.querySelectorAll("[data-stat]"), function (n) {
      var key = n.getAttribute("data-stat");
      if (Object.prototype.hasOwnProperty.call(counts, key)) n.textContent = counts[key];
    });
  }

  window.renderCatalog = function (apps) {
    var grid = document.getElementById("grid");
    var empty = document.getElementById("empty");
    var q = document.getElementById("q");
    var chips = Array.prototype.slice.call(document.querySelectorAll(".chip"));
    var filter = "all";

    function matches(a) {
      var term = q.value.trim().toLowerCase();
      if (term) {
        var hay = (a.name + " " + a.namespace + " " + a.category + " " + a.description).toLowerCase();
        if (hay.indexOf(term) < 0) return false;
      }
      if (filter === "public") return a.public;
      if (filter === "lan") return a.lan;
      if (filter === "stateful") return a.stateful;
      return true;
    }

    function imageLabel(a) {
      if (!a.images.length) return "";
      var first = a.images.filter(function (i) { return i.repo.indexOf(a.name) !== -1; })[0] || a.images[0];
      var label = first.repo.split("/").pop() + ":" + first.tag;
      return a.images.length > 1 ? label + " +" + (a.images.length - 1) : label;
    }

    function card(a) {
      var c = el("article", "card");
      c.appendChild(el("h3", "", a.name));
      c.appendChild(el("div", "ns", "ns/" + a.namespace + (imageLabel(a) ? " · " + imageLabel(a) : "")));
      c.appendChild(el("p", "", a.description));
      var tags = el("div", "tags");
      tags.appendChild(el("span", "tag", a.category));
      if (a.public) tags.appendChild(el("span", "tag pub", "public"));
      if (a.lan) tags.appendChild(el("span", "tag lan", "LAN"));
      if (!a.public && !a.lan) tags.appendChild(el("span", "tag", "internal"));
      a.storage.forEach(function (s) { tags.appendChild(el("span", "tag", "pvc " + s.size)); });
      c.appendChild(tags);
      if (a.hosts.length) {
        var hl = el("div", "hostlist");
        a.hosts.forEach(function (h) { hl.appendChild(el("span", "", h.host)); });
        c.appendChild(hl);
      }
      return c;
    }

    function draw() {
      while (grid.firstChild) grid.removeChild(grid.firstChild);
      var shown = apps.filter(matches);
      shown.forEach(function (a) { grid.appendChild(card(a)); });
      empty.hidden = shown.length > 0;
    }

    q.addEventListener("input", draw);
    chips.forEach(function (chip) {
      chip.addEventListener("click", function () {
        filter = chip.getAttribute("data-filter");
        chips.forEach(function (o) { o.setAttribute("aria-pressed", o === chip ? "true" : "false"); });
        draw();
      });
    });
    draw();
  };

  buildShell();
  var apps = (window.WIKI_APPS && window.WIKI_APPS.apps) || [];
  fillStats(apps);
  if (window.renderCatalog && document.getElementById("grid")) window.renderCatalog(apps);
})();
