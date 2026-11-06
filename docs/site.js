// What both pages do: choose a theme, resize the columns, and — where the page has them — read the
// sample panel and follow the outline. One file, so the two pages cannot drift apart.

(() => {
  const root = document.documentElement;

  /* ---------------------------------------------------------------- day and night */

  // No choice means the platform decides. The stylesheet's own media query is left in charge by
  // writing no attribute at all, so a reader who never touches the switch sees the system theme,
  // and sees it change with the system.
  const THEME_KEY = "moonacp-theme";
  const platform = matchMedia("(prefers-color-scheme: dark)");
  const toggle = document.querySelector(".theme-toggle");

  const chosenTheme = () => {
    try {
      const saved = localStorage.getItem(THEME_KEY);
      return saved === "light" || saved === "dark" ? saved : null;
    } catch (error) {
      return null;
    }
  };

  const shownTheme = () => chosenTheme() || (platform.matches ? "dark" : "light");

  const paintTheme = () => {
    const choice = chosenTheme();
    if (choice) {
      root.dataset.theme = choice;
    } else {
      delete root.dataset.theme;
    }
    if (!toggle) return;
    const dark = shownTheme() === "dark";
    toggle.setAttribute("aria-pressed", String(dark));
    toggle.setAttribute(
      "aria-label",
      dark ? "Switch to light theme" : "Switch to dark theme",
    );
  };

  if (toggle) {
    // A double click hands the decision back to the system, and says nothing about it.
    toggle.addEventListener("dblclick", () => {
      try {
        localStorage.removeItem(THEME_KEY);
      } catch (error) {
        // Nothing to forget.
      }
      delete root.dataset.theme;
      paintTheme();
    });
    toggle.addEventListener("click", () => {
      const next = shownTheme() === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try {
        localStorage.setItem(THEME_KEY, next);
      } catch (error) {
        // Not remembered, but this page still switches.
      }
      paintTheme();
    });
  }

  // While no choice has been made, the system is the one that decides.
  platform.addEventListener("change", paintTheme);
  paintTheme();

  /* ---------------------------------------------------------------- column widths */

  // Three columns, two handles. The handles only exist where the columns do: under the width where
  // the margin column folds away, the stylesheet takes over and the handles step out.
  const shell = document.querySelector(".shell");
  const splitters = [...document.querySelectorAll(".splitter")];
  const SIDES = {
    nav: { min: 184, max: 380, width: 244, edge: ".side" },
    rail: { min: 232, max: 460, width: 304, edge: ".rail" },
  };

  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  const widthOf = (side) => {
    const element = document.querySelector(SIDES[side].edge);
    return element ? element.getBoundingClientRect().width : SIDES[side].width;
  };

  const setWidth = (side, width) => {
    const value = Math.round(clamp(width, SIDES[side].min, SIDES[side].max));
    root.style.setProperty(`--${side}-w`, `${value}px`);
    return value;
  };

  const remember = (side, width) => {
    try {
      localStorage.setItem(`moonacp-${side}-w`, String(Math.round(width)));
    } catch (error) {
      // Not remembered, but this page stays as it was dragged.
    }
  };

  const forget = (side) => {
    try {
      localStorage.removeItem(`moonacp-${side}-w`);
    } catch (error) {
      // Nothing to forget.
    }
  };

  for (const splitter of splitters) {
    const side = splitter.dataset.resize;
    const limits = SIDES[side];
    if (!shell || !limits) continue;

    const sync = () => {
      const width = widthOf(side);
      splitter.setAttribute("aria-valuenow", String(Math.round(width)));
    };

    const fromPointer = (clientX) => {
      const box = shell.getBoundingClientRect();
      return side === "nav" ? clientX - box.left : box.right - clientX;
    };

    splitter.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      try {
        splitter.setPointerCapture(event.pointerId);
      } catch (error) {
        // A pointer that cannot be captured still drags; it just stops at the edge of the handle.
      }
      splitter.dataset.dragging = "true";
      document.body.classList.add("resizing");
      sync();
    });

    splitter.addEventListener("pointermove", (event) => {
      if (!splitter.dataset.dragging) return;
      setWidth(side, fromPointer(event.clientX));
      sync();
    });

    const release = () => {
      if (!splitter.dataset.dragging) return;
      delete splitter.dataset.dragging;
      document.body.classList.remove("resizing");
      remember(side, widthOf(side));
    };

    splitter.addEventListener("pointerup", release);
    splitter.addEventListener("pointercancel", release);

    // A double click puts the column back where the page was designed to have it.
    splitter.addEventListener("dblclick", () => {
      root.style.removeProperty(`--${side}-w`);
      forget(side);
      sync();
    });

    // The same drag, from the keyboard: an arrow moves the edge, and the ends go all the way.
    splitter.addEventListener("keydown", (event) => {
      const step = event.shiftKey ? 48 : 16;
      const grows = side === "nav" ? "ArrowRight" : "ArrowLeft";
      const shrinks = side === "nav" ? "ArrowLeft" : "ArrowRight";
      let next = null;
      if (event.key === grows) next = widthOf(side) + step;
      else if (event.key === shrinks) next = widthOf(side) - step;
      else if (event.key === "Home") next = limits.min;
      else if (event.key === "End") next = limits.max;
      if (next === null) return;
      event.preventDefault();
      setWidth(side, next);
      remember(side, widthOf(side));
      sync();
    });

    sync();
  }

  /* ---------------------------------------------------------------- the sample panel */

  // Keys, strings, numbers and literals told apart, by rebuilding the text as spans — never by
  // handing the browser a string of HTML.
  const token = /("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?)|\b(true|false|null)\b/g;

  const colour = (node) => {
    const text = node.textContent;
    node.textContent = "";
    let at = 0;
    for (const match of text.matchAll(token)) {
      if (match.index > at) node.append(text.slice(at, match.index));
      const span = document.createElement("span");
      if (match[1] && match[2] !== undefined) {
        span.className = "k";
        span.textContent = match[1];
        node.append(span, match[2]);
      } else if (match[1]) {
        span.className = "s";
        span.textContent = match[1];
        node.append(span);
      } else if (match[3]) {
        span.className = "n";
        span.textContent = match[3];
        node.append(span);
      } else {
        span.className = "b";
        span.textContent = match[0];
        node.append(span);
      }
      at = match.index + match[0].length;
    }
    node.append(text.slice(at));
  };

  for (const node of document.querySelectorAll(".rail.wire .what, .rail.wire .sample code")) {
    colour(node);
  }

  // Two transports, one panel.
  const tabs = [...document.querySelectorAll(".rail .tabs button")];
  const views = [...document.querySelectorAll(".rail .view")];

  for (const tab of tabs) {
    tab.addEventListener("click", () => {
      for (const other of tabs) {
        other.setAttribute("aria-selected", String(other === tab));
      }
      for (const view of views) {
        view.hidden = view.dataset.view !== tab.dataset.view;
      }
    });
  }

  const copy = document.querySelector(".rail .copy");
  if (copy) {
    copy.addEventListener("click", async () => {
      const shown = document.querySelector(".rail .view:not([hidden])");
      try {
        await navigator.clipboard.writeText(shown.innerText);
        copy.textContent = "Copied";
      } catch (error) {
        copy.textContent = "Select it";
      }
      setTimeout(() => {
        copy.textContent = "Copy";
      }, 1400);
    });
  }

  /* ---------------------------------------------------------------- the outline */

  // The section being read is the one the sidebar shows.
  const links = [...document.querySelectorAll(".side nav a[href^='#']")];
  const sections = links
    .map((link) => document.querySelector(link.getAttribute("href")))
    .filter(Boolean);

  if (sections.length) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          for (const link of links) {
            link.toggleAttribute(
              "aria-current",
              link.getAttribute("href") === `#${entry.target.id}`,
            );
          }
        }
      },
      { rootMargin: "-20% 0px -70% 0px" },
    );
    for (const section of sections) observer.observe(section);
  }

  /* ---------------------------------------------------------------- the page's own edge */

  const markTop = () => root.classList.toggle("at-top", scrollY === 0);
  addEventListener("scroll", markTop, { passive: true });
  markTop();
})();
