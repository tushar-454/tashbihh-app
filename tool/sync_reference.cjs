// Reads the original checkout without modifying it. No user data is imported.
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const source=process.env.TASBIH_WEB_SOURCE || '/home/tushar/Documents/code/tasbih_web';
const sandbox={window:{}};
vm.runInNewContext(fs.readFileSync(path.join(source,'config.js'),'utf8'),sandbox);
fs.writeFileSync(path.join(root,'assets/data/config.json'),JSON.stringify(sandbox.window.TASBIH_CONFIG,null,2)+'\n');
for(const file of ['icon.svg','icon-maskable.svg'])fs.copyFileSync(path.join(source,file),path.join(root,'assets/branding',file));
console.log(`Copied all ${sandbox.window.TASBIH_CONFIG.duas.length} Dhikr definitions and both original SVG assets.`);
