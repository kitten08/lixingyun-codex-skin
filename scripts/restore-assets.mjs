// Lossless asset storage with no Git LFS or cloud dependency.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const digest=b=>createHash('sha256').update(b).digest('hex');
const manifest=JSON.parse(await fs.readFile(path.join(root,'AssetParts/manifest.json'),'utf8'));
for(const file of manifest.files) {
  if(!file.path.startsWith('Assets/') || file.path.split('/').includes('..'))throw new Error('Invalid asset path');
  const target=path.join(root,file.path);
  try {if(digest(await fs.readFile(target))===file.sha256)continue;}catch(e){if(e.code!=='ENOENT')throw e;}
  const chunks=[];
  for(const part of file.parts){
    if(!/^[a-z0-9._-]+$/.test(part.name))throw new Error('Invalid part path');
    const bytes=await fs.readFile(path.join(root,'AssetParts',part.name));
    if(bytes.length!==part.bytes || digest(bytes)!==part.sha256)throw new Error('Damaged asset part: '+part.name);
    chunks.push(bytes);
  }
  const data=Buffer.concat(chunks);
  if(data.length!==file.bytes || digest(data)!==file.sha256)throw new Error('Asset checksum mismatch: '+file.path);
  await fs.mkdir(path.dirname(target),{recursive:true});
  const temporary=target+'.restore-tmp';await fs.writeFile(temporary,data);await fs.rename(temporary,target);
  console.log('Restored '+file.path);
}
const checks=JSON.parse(await fs.readFile(path.join(root,'Assets/checksums.json'),'utf8'));
for(const file of checks){const data=await fs.readFile(path.join(root,file.path));if(data.length!==file.bytes || digest(data)!==file.sha256)throw new Error('Asset verification failed: '+file.path);}
console.log('All '+checks.length+' media files verified');
