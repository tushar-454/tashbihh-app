const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs=require('node:fs'); const path=require('node:path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN || '/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
 const page=await browser.newPage();
 const icon=fs.readFileSync(root+'/assets/branding/icon.svg','utf8');
 const mask=fs.readFileSync(root+'/assets/branding/icon-maskable.svg','utf8');
 async function save(file,size,svg=icon,{opaque=false,padding=0}={}){
  const b64=await page.evaluate(async({svg,size,opaque,padding})=>{
   const image=new Image();image.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await image.decode();
   const c=document.createElement('canvas');c.width=c.height=size;const x=c.getContext('2d');
   if(opaque){x.fillStyle='#151a26';x.fillRect(0,0,size,size);}
   x.drawImage(image,size*padding,size*padding,size*(1-2*padding),size*(1-2*padding));
   return c.toDataURL('image/png').split(',')[1];
  },{svg,size,opaque,padding});
  fs.mkdirSync(path.dirname(root+'/'+file),{recursive:true});fs.writeFileSync(root+'/'+file,Buffer.from(b64,'base64'));
 }
 for(const [density,size] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]) {
  await save(`android/app/src/main/res/mipmap-${density}/ic_launcher.png`,size);
  await save(`android/app/src/main/res/mipmap-${density}/ic_launcher_foreground.png`,size*108/48,mask.replace(/<rect[^>]+\/>/,''),{padding:.1});
 }
 const adaptive='android/app/src/main/res/mipmap-anydpi-v26';fs.mkdirSync(root+'/'+adaptive,{recursive:true});
 fs.writeFileSync(root+'/'+adaptive+'/ic_launcher.xml','<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n  <background android:drawable="@color/launcher_background"/>\n  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n');
 fs.writeFileSync(root+'/android/app/src/main/res/values/colors.xml','<resources>\n  <color name="launcher_background">#151a26</color>\n</resources>\n');
 for(const platform of ['ios','macos']) {
  const folder=`${platform}/Runner/Assets.xcassets/AppIcon.appiconset`;
  const entries=JSON.parse(fs.readFileSync(root+'/'+folder+'/Contents.json')).images;
  for(const i of entries) await save(folder+'/'+i.filename,parseFloat(i.size)*parseFloat(i.scale),icon,{opaque:platform==='ios'});
 }
 for(const size of [192,512]) {await save(`web/icons/Icon-${size}.png`,size);await save(`web/icons/Icon-maskable-${size}.png`,size,mask);}
 await save('web/favicon.png',32);
 await save('assets/branding/linux-icon.png',256);
 const png=fs.readFileSync(root+'/assets/branding/linux-icon.png');
 const header=Buffer.alloc(22);header.writeUInt16LE(1,2);header.writeUInt16LE(1,4);header[6]=0;header[7]=0;header.writeUInt16LE(1,10);header.writeUInt16LE(32,12);header.writeUInt32LE(png.length,14);header.writeUInt32LE(22,18);
 fs.writeFileSync(root+'/windows/runner/resources/app_icon.ico',Buffer.concat([header,png]));
 console.log('Generated original-brand Android adaptive/legacy, iOS opaque, macOS, web, Windows, Linux icons.');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
