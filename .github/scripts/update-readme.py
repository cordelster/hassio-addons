import re
import pathlib

rows = [
    "| Add-on | Description |",
    "|--------|-------------|",
]
for cfg in sorted(pathlib.Path("addons").glob("*/config.yaml")):
    slug = cfg.parent.name
    text = cfg.read_text()
    name = re.search(r'^name:\s*["\']?(.+?)["\']?\s*$', text, re.M)
    desc = re.search(r'^description:\s*["\']?(.+?)["\']?\s*$', text, re.M)
    name = name.group(1) if name else slug
    desc = desc.group(1) if desc else ""
    rows.append(f"| [{name}](addons/{slug}) | {desc} |")

block = "\n".join(rows)
readme = pathlib.Path("README.md").read_text()
updated = re.sub(
    r"<!-- ADDONS_START -->.*?<!-- ADDONS_END -->",
    f"<!-- ADDONS_START -->\n{block}\n<!-- ADDONS_END -->",
    readme,
    flags=re.DOTALL,
)
pathlib.Path("README.md").write_text(updated)
