#!/usr/bin/env python3
"""Reproduce the public asset pack from tracked application artwork."""
from pathlib import Path
import subprocess,json,hashlib,zipfile
root=Path(__file__).resolve().parents[1]
prefixes=['assets/source/', 'assets/generated/', 'ios/Resources/Assets.xcassets/', 'ios/Release/StoreAssets/']
files=[p for p in subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0') if p and any(p.startswith(x) for x in prefixes) and Path(p).suffix in ['.png','.jpg','.icns','.svg','.json','.html','.md']]
out=root/'ios/Release'/'AssetPack'
out.mkdir(exist_ok=True)
manifest={'application':'YETI3-Cleaner','files':[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest(),'bytes':(root/p).stat().st_size} for p in sorted(files)]}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
archive=root/'output'/'asset-packs'/'YETI3-Cleaner-AssetPack.zip'
archive.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(files): z.write(root/p,p)
 z.write(out/'manifest.json','manifest.json')
 z.write(out/'README.md','README.md')
 assert z.testzip() is None
print(json.dumps({'archive':str(archive),'files':len(files),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}))
