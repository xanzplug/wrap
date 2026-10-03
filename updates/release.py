#!/usr/bin/env python3
"""Usage: python3 updates/release.py <export folder> "note" ["note" ...]"""
import base64, html, os, plistlib, subprocess, sys
from datetime import datetime, timezone
from email.utils import format_datetime
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPDATES = os.path.join(ROOT, "updates")
APPCAST = os.path.join(UPDATES, "appcast.xml")
KEY = os.path.join(ROOT, ".release-keys", "sparkle_private_key.txt")
BASE_URL = "https://raw.githubusercontent.com/xanzplug/wrap/main/updates/"

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    folder = sys.argv[1]
    notes = sys.argv[2:] or ["Improvements and fixes."]
    app = folder if folder.endswith(".app") else os.path.join(folder, "Wrap.app")
    info = plistlib.load(open(os.path.join(app, "Contents", "Info.plist"), "rb"))
    short, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    min_os = info.get("LSMinimumSystemVersion", "")

    existing = open(APPCAST).read() if os.path.exists(APPCAST) else ""
    if f"<sparkle:version>{build}</sparkle:version>" in existing:
        sys.exit(f"Build {build} is already published. Raise the version in Xcode first.")
    name = f"Wrap-{short}.zip"
    zip_path = os.path.join(UPDATES, name)
    if os.path.exists(zip_path):
        os.remove(zip_path)
    subprocess.run(["zip", "-qry", zip_path, os.path.basename(app)],
                   cwd=os.path.dirname(os.path.abspath(app)), check=True)

    data = open(zip_path, "rb").read()
    key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(open(KEY).read().strip()))
    signature = base64.b64encode(key.sign(data)).decode()

    items = "".join(f"<li>{html.escape(n)}</li>" for n in notes)
    item = f"""    <item>
      <title>Version {short}</title>
      <pubDate>{format_datetime(datetime.now(timezone.utc))}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{BASE_URL}{name}" length="{len(data)}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
"""
    if not existing:
        existing = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Wrap</title>
    <link>https://github.com/xanzplug/wrap</link>
    <description>New versions of Wrap.</description>
    <language>en</language>
  </channel>
</rss>
"""
    marker = "    <language>en</language>\n"
    updated = existing.replace(marker, marker + item, 1)
    open(APPCAST, "w").write(updated)
    print(f"Published Wrap {short} ({build}): {name}, {len(data) // 1024} KB")

if __name__ == "__main__":
    main()
