#!/usr/bin/env node
// Three.js GLB 多角度截图工具
// 用法: _screenshot_threejs.js <model.glb> <output_dir> <resolution> <angles_csv>

const { chromium } = require('/home/kai/.openclaw/workspace/node_modules/playwright');
const fs = require('fs');
const http = require('http');

const args = process.argv.slice(2);
const glbPath = args[0];
const outputDir = args[1];
const resolution = parseInt(args[2]);
const anglesCsv = args[3];

const glbBuffer = fs.readFileSync(glbPath);
console.log(`GLB loaded: ${(glbBuffer.length / 1024 / 1024).toFixed(1)}MB`);

const ANGLES = {
    front:   { x: 0,   y: 1.2, z: 2.5, ty: 0.8 },
    side:    { x: 2.5, y: 1.2, z: 0,   ty: 0.8 },
    top:     { x: 0,   y: 3.0, z: 0.01,ty: 0   },
    '45deg': { x: 1.8, y: 1.2, z: 1.8, ty: 0.8 },
    back:    { x: 0,   y: 1.2, z:-2.5, ty: 0.8 },
    low:     { x: 1.5, y: 0.3, z: 1.5, ty: 0.8 },
    closeup: { x: 0,   y: 1.5, z: 1.0, ty: 1.4 },
};

function makeHtml(cam) {
    return `<!DOCTYPE html><html><head><meta charset="utf-8">
<style>body{margin:0;overflow:hidden;background:#1a1a2e}canvas{display:block}</style>
</head><body>
<script type="importmap">
{"imports":{"three":"https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js","three/addons/":"https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/"}}
</script>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
const W=${resolution},H=${resolution};
const scene=new THREE.Scene();
scene.background=new THREE.Color(0x1a1a2e);
const camera=new THREE.PerspectiveCamera(45,W/H,0.1,100);
camera.position.set(${cam.x},${cam.y},${cam.z});
camera.lookAt(0,${cam.ty},0);
const renderer=new THREE.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});
renderer.setSize(W,H);
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.2;
document.body.appendChild(renderer.domElement);
scene.add(new THREE.AmbientLight(0xffffff,0.5));
const d1=new THREE.DirectionalLight(0xffffff,2);d1.position.set(5,8,5);scene.add(d1);
const d2=new THREE.DirectionalLight(0x8888ff,0.8);d2.position.set(-3,4,-3);scene.add(d2);
new GLTFLoader().load('/model.glb',(gltf)=>{
  const m=gltf.scene;
  const box=new THREE.Box3().setFromObject(m);
  const sz=box.getSize(new THREE.Vector3());
  m.scale.setScalar(1.5/Math.max(sz.x,sz.y,sz.z));
  box.setFromObject(m);
  const c=box.getCenter(new THREE.Vector3());
  m.position.sub(c);
  m.position.y+=box.getSize(new THREE.Vector3()).y/2;
  scene.add(m);
  renderer.render(scene,camera);
  document.title='DONE';
},undefined,e=>{document.title='ERR:'+e;});
</script></body></html>`;
}

async function main() {
    const angles = anglesCsv.split(',');
    let server;

    for (const angle of angles) {
        const cam = ANGLES[angle] || ANGLES['45deg'];
        const outputFile = `${outputDir}/${angle}.png`;

        // Start a fresh HTTP server for each angle
        const html = makeHtml(cam);
        server = http.createServer((req, res) => {
            if (req.url === '/model.glb') {
                res.writeHead(200, { 'Content-Type': 'model/gltf-binary' });
                res.end(glbBuffer);
            } else {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(html);
            }
        });
        await new Promise(r => server.listen(0, '127.0.0.1', r));
        const port = server.address().port;

        const browser = await chromium.launch();
        const page = await browser.newPage();

        try {
            await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load', timeout: 20000 });
            await page.waitForFunction(() => document.title === 'DONE' || document.title.startsWith('ERR'), { timeout: 30000 });
            
            if (await page.title() !== 'DONE') {
                console.log(`  ⚠ ${angle}: ${(await page.title())}`);
            }
            
            await page.screenshot({ path: outputFile });
            const size = fs.statSync(outputFile).size;
            console.log(`  ✓ ${angle} (${(size/1024).toFixed(0)}KB)`);
        } catch (err) {
            console.log(`  ⚠ ${angle}: ${err.message}`);
        }

        await browser.close();
        server.close();
    }
}

main().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
});
