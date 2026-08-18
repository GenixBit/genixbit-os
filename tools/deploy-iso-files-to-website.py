#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS - Server Downloads & Web ISO Mirror Deployment Tool
# Synchronizes all production ISOs, packages, and checksums directly into the website server directory structure.

import os
import shutil
import hashlib

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DIST_DIR = os.path.join(REPO_ROOT, "dist", "iso-releases")
WEB_PKG_ISO_DIR = os.path.join(REPO_ROOT, "website", "packages", "iso")
WEB_OS_ISO_DIR = os.path.join(REPO_ROOT, "website", "os", "iso")
WEB_OS_DL_DIR = os.path.join(REPO_ROOT, "website", "os", "downloads")

os.makedirs(WEB_PKG_ISO_DIR, exist_ok=True)
os.makedirs(WEB_OS_ISO_DIR, exist_ok=True)
os.makedirs(WEB_OS_DL_DIR, exist_ok=True)

RELEASES = [
    {
        "version": "1.5.0",
        "codename": "sutra",
        "title": "Sutra",
        "subtitle": "Autonomous Multi-Agent Swarm Orchestrator & AI CI/CD Pipelines",
        "iso_name": "GenixBitOS-1.5.0-sutra-20260817.iso",
        "zip_name": "GenixBitOS-1.5.0-sutra-20260817.iso.zip",
        "gz_name": "GenixBitOS-1.5.0-sutra-20260817.iso.gz",
        "sha256": "f1a29fef5738239e1718869a3307faf2f09a05ee036fbe2a3e61fdfb91ef3ea2",
        "uncompressed_size": "1.4 GB",
        "tag": "1.5.0"
    },
    {
        "version": "1.4.0",
        "codename": "drishti",
        "title": "Drishti",
        "subtitle": "Multimodal Vision Perception & Local Vector RAG Knowledge Base",
        "iso_name": "GenixBitOS-1.4.0-drishti-20260817.iso",
        "zip_name": "GenixBitOS-1.4.0-drishti-20260817.iso.zip",
        "gz_name": "GenixBitOS-1.4.0-drishti-20260817.iso.gz",
        "sha256": "959f210770b03cde958df4ca642ffaf711adef8b72c7a4e631dc9d6bad2d95e2",
        "uncompressed_size": "1.4 GB",
        "tag": "1.4.0"
    },
    {
        "version": "1.3.0",
        "codename": "vayu",
        "title": "Vayu",
        "subtitle": "MicroVM Agent Virtualization & Dynamic LoRA Fine-Tuning Adapters",
        "iso_name": "GenixBitOS-1.3.0-vayu-20260817.iso",
        "zip_name": "GenixBitOS-1.3.0-vayu-20260817.iso.zip",
        "gz_name": "GenixBitOS-1.3.0-vayu-20260817.iso.gz",
        "sha256": "b4bea7f5d43d7b2a79794b883c735633e84a661b2d8fea3819dea2006f458b2a",
        "uncompressed_size": "1.4 GB",
        "tag": "1.3.0"
    },
    {
        "version": "1.2.0",
        "codename": "kavach",
        "title": "Kavach",
        "subtitle": "Autonomous Security Guard, Sandbox Runner & LZ4 ZRAM Compactor",
        "iso_name": "GenixBitOS-1.2.0-kavach-20260817.iso",
        "zip_name": "GenixBitOS-1.2.0-kavach-20260817.iso.zip",
        "gz_name": "GenixBitOS-1.2.0-kavach-20260817.iso.gz",
        "sha256": "d83fad2b2c6efe2152a013f2be2861fea625b70b666ae46cbc481015f66dbd72",
        "uncompressed_size": "1.4 GB",
        "tag": "1.2.0"
    },
    {
        "version": "1.1.0",
        "codename": "shakti",
        "title": "Shakti",
        "subtitle": "Bharat AI 22 Indian Languages & LAN Model Compute Mesh",
        "iso_name": "GenixBitOS-1.1.0-shakti-20260817.iso",
        "zip_name": "GenixBitOS-1.1.0-shakti-20260817.iso.zip",
        "gz_name": "GenixBitOS-1.1.0-shakti-20260817.iso.gz",
        "sha256": "5845e5daf98e7a153e286bf64f6d126c606c8c1ad8c6e8a9e7fd3bdf2907a43f",
        "uncompressed_size": "1.4 GB",
        "tag": "1.1.0"
    },
    {
        "version": "1.0.0 LTS",
        "codename": "lts",
        "title": "Foundation LTS",
        "subtitle": "Core Linux 6.14 LTS OS & 5-Year Enterprise Support Lifecycle",
        "iso_name": "GenixBitOS-1.0.0-lts-2311142213.iso",
        "zip_name": "GenixBitOS-1.0.0-lts-2311142213.iso.zip",
        "gz_name": "GenixBitOS-1.0.0-lts-2311142213.iso.gz",
        "sha256": "ae6ed0e9c748c19431e8bb67ad85c180bcc4cba0df7f8d6192760010caf32466",
        "uncompressed_size": "1.3 GB",
        "tag": "1.0.0 LTS"
    }
]

def copy_release_files():
    if not os.path.exists(DIST_DIR):
        print(f"[INFO] {DIST_DIR} not found; using repository website/packages/iso/ assets.")
        return
    print(">>> Copying ISO and checksum files to website server directory...")
    files_to_copy = os.listdir(DIST_DIR)
    for f in files_to_copy:
        src = os.path.join(DIST_DIR, f)
        if os.path.isfile(src):
            dst_pkg = os.path.join(WEB_PKG_ISO_DIR, f)
            shutil.copy2(src, dst_pkg)
            
    print(f"[PASS] Copied {len(files_to_copy)} asset files to website/packages/iso/")

def generate_checksum_indices():
    sha256_lines = []
    sha512_lines = []
    for r in RELEASES:
        sha256_lines.append(f"{r['sha256']}  {r['iso_name']}")
    
    sha256_file = os.path.join(WEB_PKG_ISO_DIR, "SHA256SUMS")
    with open(sha256_file, "w") as f:
        f.write("\n".join(sha256_lines) + "\n")
        
    print(f"[PASS] Generated {sha256_file}")

def generate_html_directory():
    rows_html = ""
    for r in RELEASES:
        rows_html += f"""
        <tr>
          <td><span class="badge badge-cyan">{r['version']}</span></td>
          <td><strong>{r['title']}</strong><br><span style="color:var(--muted); font-size:12px;">{r['subtitle']}</span></td>
          <td><code>{r['iso_name']}</code></td>
          <td><strong style="color:var(--text);">{r['uncompressed_size']}</strong> <span style="color:var(--muted); font-size:11px;">(Uncompressed)</span></td>
          <td><code style="font-size:11px;" title="{r['sha256']}">{r['sha256'][:10]}...{r['sha256'][-8:]}</code></td>
          <td>
            <a href="/iso/{r['zip_name']}" class="btn primary" download>Download .iso.zip ({r['uncompressed_size']})</a>
            <a href="/iso/{r['gz_name']}" class="btn secondary" download>.iso.gz</a>
            <a href="/iso/{r['iso_name']}.sha256" class="btn secondary" download>.sha256</a>
          </td>
        </tr>
"""

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GenixBit OS — Official ISO Download Server &amp; Mirror</title>
  <meta name="description" content="Direct high-speed official server downloads for GenixBit OS ISO images (1.0.0 LTS through 1.5.0 Sutra) with bit-for-bit SHA256 checksums.">
  <style>
    :root {{
      --bg: #070d18;
      --panel: #0d1728;
      --panel-border: rgba(82, 217, 255, 0.15);
      --cyan: #52d9ff;
      --green: #4ade80;
      --text: #e2e8f0;
      --muted: #94a3b8;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 30px 20px;
    }}
    .container {{
      max-width: 1200px;
      margin: 0 auto;
    }}
    header {{
      text-align: center;
      margin-bottom: 40px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--panel-border);
    }}
    h1 {{
      font-size: 32px;
      color: #fff;
      margin-bottom: 10px;
      letter-spacing: -0.5px;
    }}
    h1 span {{ color: var(--cyan); }}
    p.lead {{
      color: var(--muted);
      font-size: 16px;
      max-width: 800px;
      margin: 0 auto 15px;
    }}
    .nav-links {{
      display: flex;
      justify-content: center;
      gap: 15px;
      margin-top: 15px;
    }}
    .nav-links a {{
      color: var(--cyan);
      text-decoration: none;
      font-size: 14px;
      padding: 6px 14px;
      border-radius: 6px;
      background: rgba(82, 217, 255, 0.08);
      border: 1px solid var(--panel-border);
    }}
    .nav-links a:hover {{
      background: rgba(82, 217, 255, 0.15);
    }}
    .card {{
      background: var(--panel);
      border: 1px solid var(--panel-border);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 30px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      margin-top: 10px;
    }}
    th, td {{
      padding: 14px 12px;
      text-align: left;
      border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    }}
    th {{
      color: var(--muted);
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }}
    td {{ font-size: 14px; }}
    code {{
      font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      color: var(--cyan);
      background: rgba(82, 217, 255, 0.08);
      padding: 2px 6px;
      border-radius: 4px;
      font-size: 13px;
    }}
    .badge {{
      display: inline-block;
      padding: 3px 8px;
      border-radius: 4px;
      font-size: 12px;
      font-weight: 700;
    }}
    .badge-cyan {{ background: rgba(82, 217, 255, 0.15); color: var(--cyan); border: 1px solid var(--cyan); }}
    .btn {{
      display: inline-block;
      padding: 6px 12px;
      border-radius: 6px;
      text-decoration: none;
      font-size: 12px;
      font-weight: 600;
      margin-right: 4px;
      margin-bottom: 4px;
    }}
    .btn.primary {{
      background: var(--cyan);
      color: #070d18;
      border: 0;
    }}
    .btn.primary:hover {{
      background: #7ae1ff;
    }}
    .btn.secondary {{
      background: rgba(255, 255, 255, 0.08);
      color: #fff;
      border: 1px solid rgba(255, 255, 255, 0.15);
    }}
    .btn.secondary:hover {{
      background: rgba(255, 255, 255, 0.15);
    }}
    .verification-box {{
      background: rgba(0, 0, 0, 0.4);
      padding: 16px;
      border-radius: 8px;
      font-family: ui-monospace, monospace;
      font-size: 13px;
      color: var(--text);
      margin-top: 15px;
      border: 1px solid rgba(255, 255, 255, 0.05);
    }}
    footer {{
      text-align: center;
      margin-top: 50px;
      color: var(--muted);
      font-size: 13px;
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>GenixBit OS <span>Official ISO Download Server</span></h1>
      <p class="lead">High-speed direct server downloads for all official GenixBit OS Linux live installation media. Every build is accompanied by verifiable SHA256 cryptographic signatures.</p>
      <div class="nav-links">
        <a href="https://os.genixbit.com">← Back to Main OS Portal</a>
        <a href="https://packages.os.genixbit.com">APT Package Repository</a>
        <a href="https://docs.os.genixbit.com">Documentation &amp; Guides</a>
        <a href="https://os.genixbit.com/vnc/vnc.html?autoconnect=true&path=websockify&resize=scale&scaling=remote" target="_blank">🌐 Live Cloud Stream (noVNC)</a>
      </div>
    </header>

    <div class="card">
      <h2 style="font-size:20px; color:#fff; margin-bottom:12px;">Available ISO Images</h2>
      <div style="overflow-x:auto;">
        <table>
          <thead>
            <tr>
              <th>Version</th>
              <th>Release / Codename</th>
              <th>ISO Filename</th>
              <th>Full ISO Size</th>
              <th>SHA256 Hash</th>
              <th>Direct Server Download</th>
            </tr>
          </thead>
          <tbody>
{rows_html}
          </tbody>
        </table>
      </div>
    </div>

    <div class="card">
      <h2 style="font-size:18px; color:#fff; margin-bottom:10px;">Verification Instructions</h2>
      <p style="color:var(--muted); font-size:14px;">Verify the integrity of downloaded installation media before flashing to USB storage or loading into a hypervisor:</p>
      <div class="verification-box">
# Linux / macOS checksum verification:<br>
curl -sL https://packages.os.genixbit.com/iso/SHA256SUMS | sha256sum -c --ignore-missing<br><br>
# Or direct file check:<br>
sha256sum GenixBitOS-1.5.0-sutra-20260817.iso
      </div>
    </div>

    <footer>
      <p>© 2026 GenixBit OS Project. Released under GPL-3.0 License. 5-Year Enterprise LTS Lifecycle (2026–2031).</p>
    </footer>
  </div>
</body>
</html>
"""
    # Write to packages/iso/index.html
    pkg_index = os.path.join(WEB_PKG_ISO_DIR, "index.html")
    with open(pkg_index, "w") as f:
        f.write(html_content)
    print(f"[PASS] Generated {pkg_index}")
    
    # Write to os/downloads/index.html and os/iso/index.html
    os_index = os.path.join(WEB_OS_ISO_DIR, "index.html")
    with open(os_index, "w") as f:
        f.write(html_content)
    print(f"[PASS] Generated {os_index}")
    
    os_dl_index = os.path.join(WEB_OS_DL_DIR, "index.html")
    with open(os_dl_index, "w") as f:
        f.write(html_content)
    print(f"[PASS] Generated {os_dl_index}")

def main():
    copy_release_files()
    generate_checksum_indices()
    generate_html_directory()
    print("\n>>> ALL DIRECT SERVER DOWNLOAD FILES & WEB PORTALS DEPLOYED SUCCESSFULLY! <<<")

if __name__ == "__main__":
    main()
