const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN || '/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
 let source='https://tashbihh.vercel.app/';
 try {await page.goto(source,{waitUntil:'networkidle',timeout:25000});}
 catch {source='file:///home/tushar/Documents/code/tasbih_web/index.html';await page.goto(source,{waitUntil:'networkidle'});}
 await page.evaluate(()=>document.fonts.ready);
 await page.screenshot({path:root+'/docs/validation/source-default.png'});
 const metrics=await page.evaluate(()=>Object.fromEntries(['header','duaSelectorWrap','counterWrap','centerCircle','duaMeaning','prayerSelector'].map(id=>{let r=document.getElementById(id).getBoundingClientRect();return [id,{x:r.x,y:r.y,width:r.width,height:r.height}]})));
 await page.click('#duaButton');await page.screenshot({path:root+'/docs/validation/source-dua-menu.png'});
 await page.click('#settingsToggle');await page.screenshot({path:root+'/docs/validation/source-settings.png'});
 await page.click('#modeToggle');await page.screenshot({path:root+'/docs/validation/source-custom.png'});
 await page.click('#styleToggle');await page.click('#settingsToggle');
 for(let i=0;i<25;i++)await page.mouse.click(20,300);
 await page.screenshot({path:root+'/docs/validation/source-modern-partial.png'});
 await page.click('#settingsToggle');await page.click('#resetAllButton');await page.screenshot({path:root+'/docs/validation/source-reset.png'});
 await page.click('#resetCancelButton');await page.setViewportSize({width:1440,height:900});await page.screenshot({path:root+'/docs/validation/source-large.png'});
 fs.writeFileSync(root+'/docs/validation/reference-browser.json',JSON.stringify({source,metrics,date:new Date().toISOString()},null,2));
 // Rasterize the actual SVG including its original text, rather than substituting a glyph.
 for(const [name,filename] of [['icon','icon.svg'],['maskable','icon-maskable.svg']]){
  const svg=fs.readFileSync(root+'/assets/branding/'+filename,'utf8');
  const png=await page.evaluate(async({svg})=>{let image=new Image();image.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await image.decode();let c=document.createElement('canvas');c.width=c.height=1024;c.getContext('2d').drawImage(image,0,0,1024,1024);return c.toDataURL('image/png').split(',')[1];},{svg});
  fs.writeFileSync(root+'/assets/branding/'+name+'.png',Buffer.from(png,'base64'));
 }
 console.log(JSON.stringify({source,metrics}));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
