#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
from pathlib import Path
import hashlib,json,os,plistlib,shutil,stat,subprocess,zipfile
r=Path(__file__).resolve().parents[1]
app=r/'build/Build/Products/Release/HeliPort-MT7902.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='org.samuelnotfound.HeliPortMT7902'
assert 'SUFeedURL' not in info
dest=r/'build/dist'; dest.mkdir(parents=True,exist_ok=True)
stage=r/'build/HeliPort-MT7902-package'
if stage.exists(): shutil.rmtree(stage)
stage.mkdir()
shutil.copytree(app,stage/app.name,symlinks=True)
for name in ('LICENSE','README.md','NOTICE-MT7902.md'): shutil.copy2(r/name,stage/name)
binary=(app/'Contents/MacOS/HeliPort-MT7902').read_bytes()
manifest={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r).decode().strip(),
 'upstream_commit':'898bcd8366844fdcfe047d7ebdf90631e4642b66',
 'driver_service':'itlmt7902','driver_abi':1,'kernel_changes':False,'hardware_validated':False,
 'app_version':info['CFBundleShortVersionString'],'binary_sha256':hashlib.sha256(binary).hexdigest()}
(stage/'build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
archive=dest/'HeliPort-MT7902.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(stage.rglob('*')):
  if p.is_symlink():
   assert p.resolve().is_relative_to(stage)
   item=zipfile.ZipInfo(p.relative_to(stage).as_posix()); item.create_system=3; item.external_attr=(stat.S_IFLNK|0o777)<<16
   z.writestr(item,os.readlink(p))
  elif p.is_file(): z.write(p,p.relative_to(stage))
with zipfile.ZipFile(archive) as z: assert z.testzip() is None
(dest/'SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
(dest/'build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(archive)
