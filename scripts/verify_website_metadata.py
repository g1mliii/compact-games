#!/usr/bin/env python3
"""Validate the canonical Compact Games website metadata without dependencies."""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEBSITE = ROOT / "compact-games-site-package" / "website"
BASE_URL = "https://compactgames.app"
OLD_SITE_URL = "g1mliii.github.io/compact-games"
SUPPORT_EMAIL = "support@compactgames.app"
LEGACY_SUPPORT_EMAIL = "info@anchored.site"
PAGES = {
    "index.html": f"{BASE_URL}/",
    "faq.html": f"{BASE_URL}/faq.html",
    "privacy.html": f"{BASE_URL}/privacy.html",
    "tos.html": f"{BASE_URL}/tos.html",
}


def fail(message: str) -> None:
    print(f"Website metadata check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


for filename, expected_url in PAGES.items():
    html = (WEBSITE / filename).read_text(encoding="utf-8")
    canonicals = re.findall(r'<link\s+rel="canonical"\s+href="([^"]+)"', html)
    if canonicals != [expected_url]:
        fail(f"{filename} canonical is {canonicals!r}; expected {expected_url!r}")
    if OLD_SITE_URL in html:
        fail(f"{filename} still references the legacy GitHub Pages URL")
    local_assets = re.findall(
        r'(?:src|href)="(\./(?:app\.js|styles\.css|site\.webmanifest|assets/[^"?]+)(?:\?[^\"]*)?)"',
        html,
    )
    unversioned_assets = [asset for asset in local_assets if "?v=" not in asset]
    if unversioned_assets:
        fail(
            f"{filename} has unversioned cacheable assets: "
            f"{unversioned_assets!r}"
        )

tree = ET.parse(WEBSITE / "sitemap.xml")
namespace = {"sitemap": "http://www.sitemaps.org/schemas/sitemap/0.9"}
sitemap_urls = {
    element.text for element in tree.findall("sitemap:url/sitemap:loc", namespace)
}
if sitemap_urls != set(PAGES.values()):
    fail(f"sitemap URLs are {sorted(sitemap_urls)!r}; expected {sorted(PAGES.values())!r}")

image_namespace = {
    **namespace,
    "image": "http://www.google.com/schemas/sitemap-image/1.1",
}
image_urls = {
    element.text
    for element in tree.findall(
        "sitemap:url/image:image/image:loc",
        image_namespace,
    )
}
expected_image_urls = {f"{BASE_URL}/assets/hero-app-deadlock.png"}
if image_urls != expected_image_urls:
    fail(
        f"sitemap image URLs are {sorted(image_urls)!r}; "
        f"expected {sorted(expected_image_urls)!r}"
    )

robots = (WEBSITE / "robots.txt").read_text(encoding="utf-8")
expected_sitemap = f"Sitemap: {BASE_URL}/sitemap.xml"
if expected_sitemap not in robots:
    fail(f"robots.txt must include {expected_sitemap!r}")

security_txt = (WEBSITE / ".well-known" / "security.txt").read_text(
    encoding="utf-8"
)
expected_security_canonical = f"Canonical: {BASE_URL}/.well-known/security.txt"
if expected_security_canonical not in security_txt:
    fail(f"security.txt must include {expected_security_canonical!r}")
if "security/advisories/new" not in security_txt:
    fail("security.txt must point to private vulnerability reporting")

reference_files = [
    ROOT / "README.md",
    ROOT / "installer" / "compact_games.iss",
    ROOT / "steam" / "README.md",
]
for path in reference_files:
    if OLD_SITE_URL in path.read_text(encoding="utf-8"):
        fail(f"{path.relative_to(ROOT)} still references the legacy GitHub Pages URL")

support_files = [WEBSITE / filename for filename in PAGES]
support_files.append(WEBSITE / "app.js")
for path in support_files:
    content = path.read_text(encoding="utf-8")
    if LEGACY_SUPPORT_EMAIL in content:
        fail(f"{path.relative_to(ROOT)} still references the legacy support email")
    if SUPPORT_EMAIL not in content:
        fail(f"{path.relative_to(ROOT)} must reference {SUPPORT_EMAIL}")

print(f"Website metadata verified for {BASE_URL}.")
