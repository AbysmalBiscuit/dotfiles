#!/usr/bin/env python3
"""Print the plain-text version of a Wikipedia article to stdout.

Usage: get-wikipedia-text.py <article-url>

Takes any Wikipedia article URL (any language subdomain, any namespace) and
fetches the plain-text extract via the MediaWiki API.
"""

import json
import sys
import urllib.parse
import urllib.request


def parse_url(url: str) -> tuple[str, str]:
    """Return (api_base, title) for a Wikipedia article URL."""
    parsed = urllib.parse.urlparse(url)
    if not parsed.netloc:
        sys.exit(f"not a valid URL: {url!r}")

    api_base = f"{parsed.scheme or 'https'}://{parsed.netloc}/w/api.php"

    # /wiki/<Title> is the canonical article path; ?title=<Title> is the fallback.
    if parsed.path.startswith("/wiki/"):
        title = urllib.parse.unquote(parsed.path[len("/wiki/"):])
    else:
        qs = urllib.parse.parse_qs(parsed.query)
        if "title" not in qs:
            sys.exit(f"cannot find an article title in URL: {url!r}")
        title = qs["title"][0]

    if not title:
        sys.exit(f"empty article title in URL: {url!r}")
    return api_base, title


def fetch_extract(api_base: str, title: str) -> str:
    params = {
        "action": "query",
        "prop": "extracts",
        "explaintext": "1",
        "titles": title,
        "format": "json",
        "redirects": "1",
    }
    req = urllib.request.Request(
        f"{api_base}?{urllib.parse.urlencode(params)}",
        headers={"User-Agent": "get-wikipedia-text/1.0 (personal CLI tool)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)

    pages = data.get("query", {}).get("pages", {})
    for page in pages.values():
        if "missing" in page:
            sys.exit(f"page not found: {title!r}")
        extract = page.get("extract", "")
        if extract:
            return extract
    sys.exit(f"no extractable text for: {title!r}")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        sys.exit(f"usage: {sys.argv[0].split('/')[-1]} <article-url>")
    api_base, title = parse_url(sys.argv[1])
    print(fetch_extract(api_base, title))


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # Downstream reader (head, less) closed the pipe early; exit quietly.
        sys.exit(0)
