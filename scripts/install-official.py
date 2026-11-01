#!/usr/bin/env python3
"""Atomically install a verified local build, retaining the signed original."""
import argparse,datetime,hashlib,json,os,pathlib,subprocess,uuid
SUPPORT=pathlib.Path.home()/'Library/Application Support/LiXingyunCodex'
TARGET=pathlib.Path('/Applications/ChatGPT.app')
RECEIPT=SUPPORT/'official-install.json'

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()

def verify(app):subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)

def install(candidate):
    marker=candidate/'Contents/Resources/lixingyun-startup/manifest.json'
    manifest=json.loads(marker.read_text());verify(candidate);verify(TARGET)
    if (TARGET/'Contents/Resources/lixingyun-startup').exists():raise RuntimeError('Already patched; restore the original before reinstalling')
    if sha(TARGET/'Contents/Resources/app.asar')!=manifest['originalAsarSha256']:raise RuntimeError('Official version changed since isolated verification')
    signature=subprocess.run(['codesign','-dv','--verbose=4',str(TARGET)],capture_output=True,text=True,check=True).stderr
    if 'TeamIdentifier=2DC432GLL2' not in signature:raise RuntimeError('Expected the original OpenAI signature')
    backup=SUPPORT/'Backups'/('official-'+manifest['officialVersion']+'-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))/'ChatGPT.app'
    backup.parent.mkdir(parents=True,exist_ok=False)
    if backup.parent.stat().st_dev!=TARGET.parent.stat().st_dev:raise RuntimeError('Atomic backup requires the same filesystem')
    stage=TARGET.parent/('.lixingyun-stage-'+uuid.uuid4().hex+'.app')
    subprocess.run(['ditto',str(candidate),str(stage)],check=True);verify(stage)
    if sha(stage/'Contents/Resources/app.asar')!=manifest['patchedAsarSha256']:raise RuntimeError('Staged archive checksum mismatch')
    receipt={'version':'1.2.0','target':str(TARGET),'backup':str(backup),'originalAsarSha256':manifest['originalAsarSha256'],'patchedAsarSha256':manifest['patchedAsarSha256'],'installedAt':datetime.datetime.now().astimezone().isoformat()}
    SUPPORT.mkdir(parents=True,exist_ok=True)
    # Save recovery coordinates before exchanging paths. Never overwrite a
    # running process's mapped executable or resources in place.
    RECEIPT.write_text(json.dumps(receipt,indent=2)+'\n');RECEIPT.chmod(0o600)
    os.rename(TARGET,backup)
    try:os.rename(stage,TARGET)
    except BaseException:os.rename(backup,TARGET);raise
    verify(TARGET);verify(backup)
    print(json.dumps(receipt,indent=2))

def restore():
    receipt=json.loads(RECEIPT.read_text());backup=pathlib.Path(receipt['backup'])
    verify(backup)
    if sha(backup/'Contents/Resources/app.asar')!=receipt['originalAsarSha256']:raise RuntimeError('Backup checksum mismatch')
    if not (TARGET/'Contents/Resources/lixingyun-startup/manifest.json').exists():raise RuntimeError('Current app is not our custom build; refusing to overwrite it')
    running=subprocess.run(['pgrep','-f','^/Applications/ChatGPT.app/Contents/MacOS/ChatGPT'],capture_output=True,text=True)
    if running.returncode==0:raise RuntimeError('请先用 Cmd+Q 完全退出 Codex，再运行恢复工具。')
    disabled=backup.parent/'已停用的自定义版.app'
    if disabled.exists():raise RuntimeError('Recovery destination already exists')
    os.rename(TARGET,disabled)
    try:os.rename(backup,TARGET)
    except BaseException:os.rename(disabled,TARGET);raise
    verify(TARGET);print('已恢复 OpenAI 官方原版；重新打开 Codex 即可。')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=pathlib.Path);p.add_argument('--restore',action='store_true');a=p.parse_args()
    if a.restore:restore()
    elif a.candidate:install(a.candidate.resolve())
    else:p.error('Choose --candidate or --restore')
