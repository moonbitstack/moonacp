#!/usr/bin/env python3
"""Generate the API reference page from the sources and their doc comments.

`pkg.generated.mbti` is the authority on what is public; the `///` comments beside each definition
are the authority on what it means. This script reads both, and fails if a public item in the
interfaces has no entry in the page, so nothing can quietly drop out of the reference.

    python scripts/gen_api.py            # write docs/api.html
    python scripts/gen_api.py --check    # fail if the file is not what the sources say
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "docs" / "api.html"
HOME = ROOT / "docs" / "index.html"

PACKAGES = [
    ("moonacp", "The protocol, its types, and the contracts on both sides.", SRC),
    ("moonacp/stdio", "Serving an agent on the process's own streams.", SRC / "stdio"),
    ("moonacp/asgi", "Serving an agent over HTTP streams and a WebSocket.", SRC / "asgi"),
    (
        "moonacp/otel",
        "Tracing both sides with the OpenTelemetry GenAI conventions.",
        SRC / "otel",
    ),
]

PROMOTED = {
    "equal",
    "not_equal",
    "to_json",
    "from_json",
    "to_repr",
    "output",
    "to_string",
    "default",
    "compare",
    "hash",
}

GROUPS = [
    ("Values", ("pub let", "pub fn")),
    ("Errors", ("suberror",)),
    ("Types and methods", ("struct", "enum", "type ")),
    ("Traits", ("trait",)),
]


def source_items(directory: Path) -> list[dict]:
    """Every documented public item in a package, in the order it is written."""
    items: list[dict] = []
    for path in sorted(directory.glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        lines = path.read_text(encoding="utf-8").split("\n")
        doc: list[str] = []
        index = 0
        while index < len(lines):
            line = lines[index]
            if line.startswith("///|"):
                doc = []
                index += 1
                continue
            if line.startswith("///"):
                doc.append(line[3:].strip())
                index += 1
                continue
            if line.startswith("#"):
                # An attribute belongs to the declaration below it, and the docs to that.
                index += 1
                continue
            if not re.match(r"pub[ (]", line) or re.match(r"pub (extend|impl)\b", line):
                doc = []
                index += 1
                continue
            # Collect the declaration, which may run over several lines up to its body.
            declaration = [line]
            while (
                index + 1 < len(lines)
                and lines[index + 1].strip()
                and not re.match(r"(pub|///|#|\}|impl |priv )", lines[index + 1])
                and not declaration[-1].rstrip().endswith(("{", "=", "__"))
            ):
                index += 1
                declaration.append(lines[index])
            text = " ".join(part.strip() for part in declaration)
            text = re.sub(r"\s*\{\s*$", "", text).strip()
            items.append({"text": text, "doc": "\n".join(doc), "file": path.name})
            doc = []
            index += 1
    return items


def mbti_names(directory: Path) -> set[str]:
    """The names `pkg.generated.mbti` says are public."""
    names: set[str] = set()
    path = directory / "pkg.generated.mbti"
    if not path.exists():
        return names
    # A name here is what a reader looks up: `Session::update`, or `Prompt` for a type.
    pattern = re.compile(
        r"^pub (?:async )?fn(?:\[[^\]]*\])?\s+([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)"
        r"|^pub (?:async )?(?:let|const|trait)\s+([A-Za-z_][\w]*)"
        r"|^pub (?:\w+\s+)?(?:struct|enum|suberror|type)\s+([A-Za-z_][\w]*)"
    )
    for line in path.read_text(encoding="utf-8").split("\n"):
        match = pattern.match(line.replace("pub(all)", "pub"))
        if not match:
            continue
        name = next(group for group in match.groups() if group)
        # Methods a trait implementation promotes are documented on the trait, not here.
        if name.rsplit("::", 1)[-1] in PROMOTED:
            continue
        names.add(name)
    return names


def item_names(items: list[dict]) -> set[str]:
    names: set[str] = set()
    for item in items:
        text = item["text"].replace("pub(all)", "pub")
        match = re.match(
            r"pub (?:async )?fn(?:\[[^\]]*\])?\s+([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)", text
        )
        if not match:
            match = re.match(
                r"pub (?:\w+\s+)*(?:let|struct|enum|suberror|trait|type)\s+([A-Za-z_][\w]*)", text
            )
        if match:
            names.add(match.group(1))
    return names


def kind_of(text: str) -> str:
    if re.search(r"\btrait\b", text):
        return "trait"
    if re.search(r"\bsuberror\b", text):
        return "error"
    if re.search(r"\bstruct\b", text):
        return "struct"
    if re.search(r"\benum\b", text):
        return "enum"
    if re.search(r"\btype\b", text):
        return "alias"
    if re.search(r"\blet\b", text):
        return "value"
    return "function"


def split_signature(text: str) -> tuple[str, str]:
    """The name a reader looks up, and the rest of the line: what it takes and gives back."""
    match = re.match(r"(?:async\s+)?fn\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)", text)
    if match:
        return match.group(1), text[match.end() :].strip()
    match = re.match(r"(?:let|const)\s+([A-Za-z_]\w*)\s*(.*)", text)
    if match:
        return match.group(1), match.group(2).strip()
    match = re.match(r"(?:\(all\)\s*)?(?:struct|enum|suberror|type|trait)\s+([A-Za-z_]\w*)", text)
    if match:
        return match.group(1), ""
    return text, ""


def slug(name: str) -> str:
    """An anchor for a group heading: "Types and methods" becomes "types-and-methods"."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def inline_markup(text: str) -> str:
    """Documentation prose: escaped, with `code` spans turned into real ones."""
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text))


KIND_LABEL = {
    "trait": ("trait", "trait"),
    "error": ("error", "error"),
    "struct": ("type", "struct"),
    "enum": ("type", "enum"),
    "alias": ("type", "alias"),
    "value": ("let", "value"),
    "function": ("fn", "function"),
}


def render(api_doc: str) -> str:
    """The whole page, with one section per package and one card per item."""
    sections = []
    outline: list[tuple[str, str, list[tuple[str, str, int]]]] = []
    for package, blurb, directory in PACKAGES:
        items = source_items(directory)
        groups: dict[str, list[dict]] = {name: [] for name, _ in GROUPS}
        for item in items:
            kind = kind_of(item["text"])
            key = {
                "trait": "Traits",
                "error": "Errors",
                "struct": "Types and methods",
                "enum": "Types and methods",
                "alias": "Types and methods",
                "value": "Values",
                "function": "Values",
            }[kind]
            groups[key].append(item)
        body = []
        for name, _ in GROUPS:
            group = groups[name]
            if not group:
                continue
            body.append(
                f'<h3 class="group" id="{package.replace("/", "-")}-{slug(name)}">'
                f'<span class="label">{name}</span><span class="rule"></span>'
                f'<span class="count">{len(group)}</span></h3>'
            )
            for item in group:
                kind = kind_of(item["text"])
                label, css = KIND_LABEL[kind]
                plain = re.sub(r"\b(pub|async)\b\s*", "", item["text"]).strip()
                name, tail = split_signature(plain)
                doc = ""
                if item["doc"]:
                    paragraphs = [
                        f"<p>{inline_markup(paragraph)}</p>"
                        for paragraph in item["doc"].split("\n\n")
                        if paragraph.strip()
                    ]
                    doc = "\n".join(paragraphs)
                anchor = f"{package.replace('/', '-')}-{len(body)}"
                if " -> " in tail:
                    takes, gives = tail.split(" -> ", 1)
                    inner = (
                        f'<code>{html.escape(takes)} -&gt; </code>'
                        f'<code class="ret">{html.escape(gives)}</code>'
                    )
                else:
                    inner = f"<code>{html.escape(tail)}</code>"
                rest = f'<div class="sig">{inner}</div>' if tail else ""
                body.append(
                    f'<article class="item" id="{html.escape(anchor)}">'
                    f'<div class="entry-name"><span class="kind {css}">{label}</span>'
                    f"<code>{html.escape(name)}</code></div>"
                    f'<div class="entry-body">{rest}<div class="doc">{doc}</div></div>'
                    f"</article>"
                )
        outline.append(
            (
                package.replace("/", "-"),
                package,
                [(slug(name), name, len(groups[name])) for name, _ in GROUPS if groups[name]],
            )
        )
        sections.append(
            f'<section class="package" id="{html.escape(package.replace("/", "-"))}">'
            f'<h2><code>{html.escape(package)}</code>'
            f'<span class="count">{len(items)} items</span></h2>'
            f'<p class="blurb">{html.escape(blurb)}</p>'
            + "\n".join(body)
            + "</section>"
        )
    nav = "\n".join(
        f'<a href="#{html.escape(package.replace("/", "-"))}"><code>{html.escape(package)}</code></a>'
        for package, _, _ in PACKAGES
    )
    contents = "\n".join(
        f'<a href="#{anchor}"><code>{html.escape(package)}</code></a>'
        + "".join(
            f'<a class="sub" href="#{anchor}-{group}">{html.escape(name)}<em>{count}</em></a>'
            for group, name, count in groups
        )
        for anchor, package, groups in outline
    )
    return (
        api_doc.replace("<!-- packages -->", nav)
        .replace("<!-- outline -->", contents)
        .replace("<!-- sections -->", "\n".join(sections))
    )


def stamp_home(page: str, packages: int, items: int) -> str:
    """The two counts the home page states come from the sources, not from a hand that forgets."""
    page = re.sub(
        r"(<dt>Packages</dt><span class=\"lead\"></span><dd>)\d+(</dd>)",
        lambda found: f"{found.group(1)}{packages}{found.group(2)}",
        page,
    )
    return re.sub(
        r"(<dt>Public items</dt><span class=\"lead\"></span><dd>)\d+(</dd>)",
        lambda found: f"{found.group(1)}{items}{found.group(2)}",
        page,
    )


def main(argv: list[str]) -> int:
    expected = set()
    for _, _, directory in PACKAGES:
        expected |= mbti_names(directory)
    documented = set()
    for _, _, directory in PACKAGES:
        documented |= item_names(source_items(directory))
    missing = sorted(expected - documented)
    if missing:
        print("these public items have no entry in the reference:")
        for name in missing:
            print(f"  {name}")
        return 1
    page = render(API_TEMPLATE)
    home = stamp_home(
        HOME.read_text(encoding="utf-8") if HOME.exists() else "", len(PACKAGES), len(documented)
    )
    if "--check" in argv:
        stale = []
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != page:
            stale.append(OUT.relative_to(ROOT))
        if HOME.exists() and HOME.read_text(encoding="utf-8") != home:
            stale.append(HOME.relative_to(ROOT))
        if stale:
            print("these pages are not what the sources say; run scripts/gen_api.py:")
            for path in stale:
                print(f"  {path}")
            return 1
        print(f"{len(documented)} public items, pages are current")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page, encoding="utf-8", newline="\n")
    HOME.write_text(home, encoding="utf-8", newline="\n")
    print(f"{len(documented)} public items written to {OUT.relative_to(ROOT)}")
    return 0


API_TEMPLATE = (ROOT / "scripts" / "api-template.html").read_text(encoding="utf-8")

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
