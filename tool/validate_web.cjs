const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1});
 const page=await context.newPage();const errors=[];const remote=[];
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('request',r=>{if(!r.url().startsWith('http://127.0.0.1:8765')&&!r.url().startsWith('data:')&&!r.url().startsWith('blob:'))remote.push(r.url());});
 const pause=ms=>page.waitForTimeout(ms);
 const snapshot=()=>page.evaluate(()=>{
  const key=Object.keys(localStorage).find(key=>key.endsWith('tasbih.native.snapshot.v1'));
  if(!key)return null;let value=localStorage[key];while(typeof value==='string')value=JSON.parse(value);return value;
 });
 const assert=(condition,message)=>{if(!condition)throw Error(message)};
 await page.goto('http://127.0.0.1:8765/',{waitUntil:'networkidle',timeout:60000});
 await page.waitForSelector('flutter-view');await pause(1000);
 await page.screenshot({path:'docs/validation/chrome-default.png'});
 // Use true pointer input, as an ordinary canvas user, rather than a screen
 // reader's semantic activation (which intentionally treats double tap as tap).
 await page.mouse.click(360,808);await pause(300);
 await page.screenshot({path:'docs/validation/chrome-settings.png'});
 await page.mouse.click(250,568);await pause(500);
 assert((await snapshot()).settings.mode==='custom','Custom Mode was not selected');
 await page.mouse.click(250,635);await pause(300);
 assert((await snapshot()).settings.style==='modern','Modern style was not selected');
 await page.mouse.click(5,240);await pause(300);
 await page.mouse.click(195,446);await pause(500);
 const single=(await snapshot()).state.customCount;
 assert(single===1,'Single pointer tap did not count exactly once: '+single);
 await page.screenshot({path:'docs/validation/chrome-custom-modern.png'});
 await page.mouse.dblclick(195,446,{delay:70});await pause(500);
 const double=(await snapshot()).state.customCount;
 assert(double===0,'Double pointer tap did not reset: '+double);
 await page.mouse.click(360,808);await pause(300);
 await page.mouse.click(250,747);await pause(300);
 await page.screenshot({path:'docs/validation/chrome-reset.png'});
 await page.keyboard.press('Escape');await pause(300);
 await page.evaluate(async()=>{await navigator.serviceWorker.ready;if(!navigator.serviceWorker.controller)await new Promise(r=>navigator.serviceWorker.addEventListener('controllerchange',r,{once:true}));});
 await context.setOffline(true);await page.reload({waitUntil:'networkidle'});await page.waitForSelector('flutter-view');await pause(1000);
 await page.screenshot({path:'docs/validation/chrome-offline-restored.png'});
 const restored=await snapshot();
 assert(restored.settings.mode==='custom'&&restored.settings.style==='modern'&&restored.state.customCount===0,'Offline restore lost progress/settings');
 await page.setViewportSize({width:1440,height:900});await pause(500);await page.screenshot({path:'docs/validation/chrome-large.png'});
 const result={errors,remoteRequests:remote,offlineReload:true,singleTapCount:single,doubleTapCount:double,restoredMode:restored.settings.mode,restoredStyle:restored.settings.style,restoredCount:restored.state.customCount};
 fs.writeFileSync('docs/validation/chrome-results.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 if(errors.length||remote.length)process.exitCode=1;
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
