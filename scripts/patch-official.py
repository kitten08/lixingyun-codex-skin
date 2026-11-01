#!/usr/bin/env python3
"""Patch a COPY first. Leaves original ASAR data intact and appends a new entry."""
import argparse, hashlib, json, pathlib, plistlib, shutil, struct, subprocess

def sign(app,info,ent_path):
    framework=app/'Contents/Frameworks/Codex Framework.framework'
    binary=(framework/'Versions/Current/Codex Framework').resolve()
    data=bytearray(binary.read_bytes());sentinel=b'AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A'
    pos=data.find(sentinel)
    if pos<0 or data.find(sentinel,pos+1)>=0:raise RuntimeError('Unsupported ASAR integrity digest layout')
    values=info['ElectronAsarIntegrity'];digest=hashlib.sha256()
    for key in sorted(values):
        for value in [key,values[key]['algorithm'],values[key]['hash']]:digest.update(value.encode())
    data[pos+32:pos+66]=bytes([1,1])+digest.digest()
    binary.write_bytes(data)
    # Keep integrity validation enabled. Update its digest to cover this build.
    helpers=sorted(framework.glob('Versions/*/Helpers/*.app'))
    seen=set()
    for helper in helpers:
        helper=helper.resolve()
        if helper in seen:continue
        seen.add(helper)
        subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent_path),str(helper)],check=True)
    subprocess.run(['codesign','--force','--sign','-',str(framework)],check=True)
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent_path),str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)

def patch(app, project):
    resources=app/'Contents/Resources'
    marker=resources/'lixingyun-startup'
    if marker.exists():
        raise RuntimeError('Already patched: restore a pristine backup before patching')
    archive=resources/'app.asar'
    raw=archive.read_bytes()
    header_size=struct.unpack_from('<I',raw,4)[0]
    json_size=struct.unpack_from('<I',raw,12)[0]
    header=json.loads(raw[16:16+json_size])
    data_start=8+header_size
    def entry(name):
        value=header
        for component in name.split('/'):value=value['files'][component]
        return value
    pkg=entry('package.json');offset=data_start+int(pkg['offset'])
    main=json.loads(raw[offset:offset+pkg['size']])['main']
    item=entry(main);offset=data_start+int(item['offset'])
    bootstrap=b"/* LiXingyun native startup v1.2 */\ntry { require(require('node:path').join(process.resourcesPath,'lixingyun-startup/native-startup.cjs')).install(); } catch(e) { console.error('LiXingyun startup:',e); }\n"
    original=raw[offset:offset+item['size']]
    if original.startswith(b'#!'):raise RuntimeError('Unexpected shebang')
    patched=bootstrap+original
    block_size=item.get('integrity',{}).get('blockSize',4194304)
    item.update(size=len(patched),offset=str(len(raw)-data_start),integrity={'algorithm':'SHA256','hash':hashlib.sha256(patched).hexdigest(),'blockSize':block_size,'blocks':[hashlib.sha256(patched[i:i+block_size]).hexdigest() for i in range(0,len(patched),block_size)]})
    encoded=json.dumps(header,separators=(',',':'),ensure_ascii=False).encode()
    padding=bytes((-len(encoded))%4)
    packed=struct.pack('<II',len(encoded)+len(padding)+4,len(encoded))+encoded+padding
    output=struct.pack('<II',4,len(packed))+packed+raw[data_start:]+patched
    archive.write_bytes(output)
    info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
    info['ElectronAsarIntegrity']['Resources/app.asar']['hash']=hashlib.sha256(encoded).hexdigest()
    info_path.write_bytes(plistlib.dumps(info))
    marker.mkdir()
    for name in ['native-startup.cjs','intro-renderer.mjs','wallpaper-layer.mjs']:
        shutil.copy2(project/'runtime'/name,marker/name)
    shutil.copytree(project/'runtime/vendor',marker/'vendor')
    shutil.copytree(project/'Assets',marker/'Assets')
    manifest={'version':'1.2.0','officialVersion':info.get('CFBundleShortVersionString'),'main':main,'originalAsarSha256':hashlib.sha256(raw).hexdigest(),'patchedAsarSha256':hashlib.sha256(output).hexdigest()}
    (marker/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    # Ad-hoc signatures cannot claim OpenAI's restricted identity entitlements.
    entitlements={'com.apple.security.app-sandbox':False,'com.apple.security.cs.allow-jit':True,'com.apple.security.cs.allow-unsigned-executable-memory':True,'com.apple.security.automation.apple-events':True,'com.apple.security.device.audio-input':True,'com.apple.security.device.camera':True,'com.apple.security.files.user-selected.read-write':True,'com.apple.security.network.client':True}
    ent_path=marker/'local-entitlements.plist';ent_path.write_bytes(plistlib.dumps(entitlements))
    sign(app,info,ent_path)
    print(json.dumps(manifest,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('app',type=pathlib.Path);parser.add_argument('--project',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parent.parent)
    args=parser.parse_args();patch(args.app.resolve(),args.project.resolve())
