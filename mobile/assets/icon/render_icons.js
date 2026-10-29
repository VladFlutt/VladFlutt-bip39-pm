// Рендер иконки ManagerBIP из app_icon_source.svg во все размеры Android/iOS.
// Запуск из mobile/: node assets/icon/render_icons.js
// Нужен playwright с Chromium. После рендера PNG для iOS надо сохранить без
// альфа-канала (App Store его не принимает), например через Pillow: convert("RGB").
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');
const fgScale=0.64; // передний слой adaptive icon должен уместиться в безопасный круг 66dp
const out=path.join(__dirname,'..','..');
const svg=fs.readFileSync(path.join(__dirname,'app_icon_source.svg'),'utf8');
const m=svg.match(/<rect width="108" height="108"[^>]*\/>/);
const defs=(svg.match(/<defs>[\s\S]*?<\/defs>/)||[''])[0];
const inner=svg.slice(svg.indexOf(m[0])+m[0].length,svg.lastIndexOf('</svg>'));
const W=b=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">${b}</svg>`;
const bgSvg=W(defs+m[0]);
const fgSvg=W(`<g transform="translate(54 54) scale(${fgScale}) translate(-54 -54)">${inner}</g>`);
const legacySvg=W(defs+m[0]+`<g transform="translate(54 54) scale(1.0) translate(-54 -54)">${inner}</g>`);
(async()=>{const b=await chromium.launch();const p=await b.newPage();
async function render(s,size,file,{round=false,inset=0}={}){
  await p.setViewportSize({width:size,height:size});
  // legacy android: icon content clipped to rounded square with small inset
  const style=round?`border-radius:50%;`:'';
  await p.setContent(`<body style="margin:0;background:transparent"><div style="width:${size}px;height:${size}px;overflow:hidden;${style}">${s.replace('<svg ',`<svg width="${size}" height="${size}" `)}</div></body>`);
  fs.mkdirSync(path.dirname(file),{recursive:true});
  await p.screenshot({path:file,omitBackground:true});}
const res=path.join(out,'android/app/src/main/res');
const d={mdpi:1,hdpi:1.5,xhdpi:2,xxhdpi:3,xxxhdpi:4};
for(const [k,f] of Object.entries(d)){
  await render(legacySvg,48*f,`${res}/mipmap-${k}/ic_launcher.png`);
  await render(legacySvg,48*f,`${res}/mipmap-${k}/ic_launcher_round.png`,{round:true});
  await render(fgSvg,108*f,`${res}/mipmap-${k}/ic_launcher_foreground.png`);
  await render(bgSvg,108*f,`${res}/mipmap-${k}/ic_launcher_background.png`);}
// iOS: full-bleed square, no alpha (bg is opaque)
const ios=path.join(out,'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const cj=JSON.parse(fs.readFileSync(ios+'/Contents.json','utf8'));
for(const im of cj.images){const px=Math.round(parseFloat(im.size)*parseInt(im.scale));await render(legacySvg,px,`${ios}/${im.filename}`);}
// store icon
await render(legacySvg,512,path.join(out,'assets/icon/play_store_512.png'));
await b.close();})();
