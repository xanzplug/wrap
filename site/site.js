const FEED = "https://raw.githubusercontent.com/xanzplug/wrap/main/updates/appcast.xml";

function setDownloads(item) {
  const url = item.querySelector("enclosure")?.getAttribute("url");
  const version = item.getElementsByTagNameNS("*", "shortVersionString")[0]?.textContent;
  if (url) document.querySelectorAll(".download-link").forEach(a => (a.href = url));
  if (version) document.querySelectorAll(".version-label").forEach(el => (el.textContent = `Version ${version}`));
}

function releaseCard(item) {
  const version = item.getElementsByTagNameNS("*", "shortVersionString")[0]?.textContent ?? "";
  const date = new Date(item.querySelector("pubDate")?.textContent ?? "");
  const notes = new DOMParser().parseFromString(item.querySelector("description")?.textContent ?? "", "text/html");
  const card = document.createElement("article");
  card.className = "release";
  const head = document.createElement("div");
  head.className = "rel-head";
  const title = document.createElement("b");
  title.textContent = `Version ${version}`;
  const when = document.createElement("span");
  when.className = "mono dim";
  when.textContent = isNaN(date) ? "" : date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
  head.append(title, when);
  const list = document.createElement("ul");
  notes.querySelectorAll("li").forEach(li => {
    const row = document.createElement("li");
    row.textContent = li.textContent;
    list.append(row);
  });
  card.append(head, list);
  return card;
}

async function loadReleases() {
  try {
    const res = await fetch(FEED, { cache: "no-cache" });
    if (!res.ok) return;
    const xml = new DOMParser().parseFromString(await res.text(), "application/xml");
    const items = [...xml.querySelectorAll("item")];
    if (!items.length) return;
    setDownloads(items[0]);

    const box = document.getElementById("releases");
    box.replaceChildren(...items.slice(0, 3).map(releaseCard));
    if (items.length > 3) {
      const more = document.createElement("button");
      more.className = "more";
      more.textContent = "Show older versions";
      more.onclick = () => {
        more.remove();
        box.append(...items.slice(3).map(releaseCard));
      };
      box.append(more);
    }
  } catch {}
}

function reveal() {
  const targets = document.querySelectorAll(".stage, .stage-intro, .feat, .release, .final > *");
  targets.forEach(el => el.classList.add("reveal"));
  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        e.target.classList.add("in");
        io.unobserve(e.target);
      }
    });
  }, { rootMargin: "0px 0px -10% 0px" });
  targets.forEach(el => io.observe(el));

  const win = document.querySelector(".window");
  requestAnimationFrame(() => setTimeout(() => win?.classList.add("in"), 120));
}

const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
const wait = ms => new Promise(r => setTimeout(r, ms));

function whenVisible(el, start) {
  if (!el) return;
  let running = false;
  new IntersectionObserver(([e]) => {
    el.dataset.visible = e.isIntersecting ? "1" : "";
    if (e.isIntersecting && !running) {
      running = true;
      start(() => el.dataset.visible === "1").finally(() => (running = false));
    }
  }, { threshold: 0.35 }).observe(el);
}

function bump(el) {
  el.classList.remove("bump");
  void el.offsetWidth;
  el.classList.add("bump");
}

function planDemo() {
  const root = document.getElementById("planDemo");
  if (!root || calm) return;
  const items = [...root.querySelectorAll(".shots li")];
  const count = root.querySelector(".shot-count");
  const pct = root.querySelector(".shot-pct");
  const bar = root.querySelector(".shot-bar");
  const set = n => {
    count.textContent = n;
    pct.textContent = Math.round((n / items.length) * 100) + "%";
    bar.style.width = (n / items.length) * 100 + "%";
  };
  whenVisible(root, async visible => {
    while (visible()) {
      await wait(1100);
      for (let i = 3; i < items.length && visible(); i++) {
        items[i].classList.add("done", "just");
        set(i + 1);
        bump(count);
        await wait(900);
        items[i].classList.remove("just");
      }
      await wait(2200);
      if (!visible()) break;
      items.slice(3).forEach(li => li.classList.remove("done"));
      set(3);
    }
  });
}

function editDemo() {
  const root = document.getElementById("editDemo");
  if (!root || calm) return;
  const btn = root.querySelector(".launch");
  const rows = [...root.querySelectorAll(".ws li")];
  const labels = rows.map(li => li.querySelector("em").textContent);
  const reset = () => rows.forEach((li, i) => {
    li.classList.remove("opening", "opened");
    li.querySelector("em").textContent = labels[i];
  });
  whenVisible(root, async visible => {
    while (visible()) {
      await wait(900);
      btn.classList.add("pressed");
      await wait(220);
      btn.classList.remove("pressed");
      for (const [i, li] of rows.entries()) {
        li.classList.add("opening");
        li.querySelector("em").textContent = "Opening";
        await wait(450);
        li.classList.replace("opening", "opened");
        li.querySelector("em").textContent = "Open";
        if (i < rows.length - 1) await wait(120);
      }
      await wait(3000);
      reset();
    }
    reset();
  });
}

function deliverDemo() {
  const root = document.getElementById("deliverDemo");
  if (!root || calm) return;
  const btn = root.querySelector(".dl-btn");
  const progress = root.querySelector(".dl-progress");
  const toast = root.querySelector(".toast");
  toast.classList.add("hidden");
  whenVisible(root, async visible => {
    while (visible()) {
      await wait(900);
      btn.classList.add("pressed");
      await wait(220);
      btn.classList.remove("pressed");
      progress.classList.add("on");
      await wait(1900);
      toast.classList.remove("hidden");
      await wait(3600);
      toast.classList.add("hidden");
      progress.classList.remove("on");
      await wait(700);
    }
  });
}

function navShrink() {
  const nav = document.querySelector(".nav-wrap");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 40);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();
}

function windowTilt() {
  const win = document.querySelector(".window");
  if (!win || calm || !matchMedia("(hover: hover) and (min-width: 900px)").matches) return;
  let frame = 0;
  addEventListener("mousemove", e => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => {
      const r = win.getBoundingClientRect();
      if (r.bottom < 0 || r.top > innerHeight) return;
      const x = (e.clientX / innerWidth - 0.5) * 2;
      const y = (e.clientY / innerHeight - 0.5) * 2;
      win.style.setProperty("--ry", (x * 3).toFixed(2) + "deg");
      win.style.setProperty("--rx", (-y * 2).toFixed(2) + "deg");
    });
  });
}

document.querySelectorAll(".grid .feat").forEach((el, i) => el.style.setProperty("--d", i % 3));
reveal();
navShrink();
windowTilt();
planDemo();
editDemo();
deliverDemo();
loadReleases();
