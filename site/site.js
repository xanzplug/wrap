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

reveal();
loadReleases();
