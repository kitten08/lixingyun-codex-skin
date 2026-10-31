// Isolated browser QA for our authored intro renderer. Never attaches to Codex.
import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const allowed=new Set(['/tests/intro-harness.html','/runtime/intro-renderer.mjs','/Assets/originals/wind.mp4','/Assets/media/wind-loop.mp4']);
const server=http.createServer(async(req,res)=>{
  try {
    const pathname=new URL(req.url,'http://127.0.0.1').pathname;
    if(req.method==='POST'&&pathname==='/results'){
      const chunks=[];let size=0;
      for await(const data of req){size+=data.length;if(size>65536)throw new Error('Result too large');chunks.push(data);}
      const result=JSON.parse(Buffer.concat(chunks).toString());
      await fsp.mkdir(path.join(root,'build'),{recursive:true});
      await fsp.writeFile(path.join(root,'build/intro-browser-results.json'),JSON.stringify(result,null,2)+'\n');
      res.writeHead(200,{'Content-Type':'application/json'});res.end('{"ok":true}');return;
    }
    const route=pathname==='/'?'/tests/intro-harness.html':pathname;
    if(req.method!=='GET'||!allowed.has(route)){res.writeHead(404);res.end('Not found');return;}
    const file=path.join(root,route),stat=await fsp.stat(file);
    const mime=route.endsWith('.html')?'text/html; charset=utf-8':route.endsWith('.mjs')?'text/javascript; charset=utf-8':'video/mp4';
    const headers={'Content-Type':mime,'Accept-Ranges':'bytes','Cache-Control':'no-store'};
    if(req.headers.range){
      const match=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
      if(!match||Number(match[1])>=stat.size){res.writeHead(416,{'Content-Range':`bytes */${stat.size}`});res.end();return;}
      const start=Number(match[1]),end=Math.min(match[2]?Number(match[2]):stat.size-1,stat.size-1);
      res.writeHead(206,{...headers,'Content-Range':`bytes ${start}-${end}/${stat.size}`,'Content-Length':end-start+1});
      fs.createReadStream(file,{start,end}).pipe(res);
    }else{res.writeHead(200,{...headers,'Content-Length':stat.size});fs.createReadStream(file).pipe(res);}
  }catch(error){res.writeHead(500,{'Content-Type':'text/plain'});res.end(error.message);}
});
server.listen(0,'127.0.0.1',()=>console.log(`INTRO_QA_URL=http://127.0.0.1:${server.address().port}/`));
process.on('SIGTERM',()=>server.close());
