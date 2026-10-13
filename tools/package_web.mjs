import fs from 'node:fs/promises';
import path from 'node:path';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';

// node tools/package_web.mjs <Godot Web export> <site/dist> [game commit]
const [sourceArg, outputArg, commit = 'local'] = process.argv.slice(2);
if (!sourceArg || !outputArg) throw new Error('Provide the Web export and site dist directories.');
const source = path.resolve(sourceArg), output = path.resolve(outputArg);
if (source === output || path.basename(output) !== 'dist') throw new Error('Output must be a separate dist directory.');
await Promise.all(['index.html','index.wasm','index.pck'].map(name=>fs.access(path.join(source,name))));
await fs.mkdir(output, {recursive:true});
// Only replace files in this explicitly selected static-output directory.
for (const entry of await fs.readdir(output, {withFileTypes:true})) {
  if (entry.isFile()) await fs.unlink(path.join(output, entry.name));
}
const assets = {};
let downloadedBytes = 0;
for (const name of ['index.wasm', 'index.pck']) {
  const raw = await fs.readFile(path.join(source, name));
  const packed = gzipSync(raw, {level:9});
  const hash = createHash('sha256').update(raw).digest('hex').slice(0,12);
  const chunks = [];
  for (let offset = 0; offset < packed.length; offset += 8*1024*1024) {
    const file = `${name}.${hash}.${chunks.length}.gz`;
    await fs.writeFile(path.join(output,file),packed.subarray(offset,offset+8*1024*1024));
    chunks.push(file);
  }
  assets[name] = {bytes:raw.length, hostedBytes:packed.length, chunks, mime:name.endsWith('.wasm')?'application/wasm':'application/octet-stream'};
  downloadedBytes += packed.length;
}
for (const name of await fs.readdir(source)) {
  if (['index.wasm','index.pck','index.html'].includes(name)) continue;
  if ((await fs.stat(path.join(source,name))).isFile()) await fs.copyFile(path.join(source,name),path.join(output,name));
}
const loader = `// Download immutable compressed chunks in parallel, then stream-decompress for Godot.
(() => {
  const assets = ${JSON.stringify(assets)};
  const originalFetch = window.fetch.bind(window);
  const downloads = new Map();
  window.fetch = async (input, options) => {
    const url = new URL(input instanceof Request ? input.url : input, location.href);
    const name = url.pathname.split('/').pop();
    const asset = assets[name];
    if (url.origin !== location.origin || !asset) return originalFetch(input,options);
    if (!('DecompressionStream' in window)) throw new Error('Please use a current desktop browser.');
    if (!downloads.has(name)) downloads.set(name,Promise.all(asset.chunks.map(async file => {
      const response = await originalFetch(new URL(file,url),options);
      if (!response.ok) throw new Error('The game download failed. Please refresh.');
      return new Uint8Array(await response.arrayBuffer());
    })));
    const chunks = await downloads.get(name);
    downloads.delete(name);
    const compressed = new ReadableStream({start(controller){for (const chunk of chunks) controller.enqueue(chunk);controller.close();}});
    return new Response(compressed.pipeThrough(new DecompressionStream('gzip')),{headers:{'Content-Type':asset.mime,'Content-Length':String(asset.bytes)}});
  };
})();
`;
const loaderFile = `wasm-loader.${createHash('sha256').update(loader).digest('hex').slice(0,12)}.js`;
await fs.writeFile(path.join(output,loaderFile),loader);
let html = await fs.readFile(path.join(source,'index.html'),'utf8');
html = html.replace(/<title>.*?<\/title>/,'<title>Artifacts Pawn Shop — Playtest</title>');
html = html.replace('<script src="index.js"></script>',`<script src="${loaderFile}"></script>\n\t\t<script src="index.js"></script>`);
await fs.writeFile(path.join(output,'index.html'),html);
await fs.writeFile(path.join(output,'release.json'),JSON.stringify({game_commit:commit,created:new Date().toISOString(),downloadedBytes,assets},null,2));
console.log(JSON.stringify({output,downloadedBytes,rawBytes:Object.values(assets).reduce((n,a)=>n+a.bytes,0),chunks:Object.values(assets).reduce((n,a)=>n+a.chunks.length,0)}));
