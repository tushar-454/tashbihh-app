from pathlib import Path
import urllib.request, json, hashlib
root=Path(__file__).resolve().parents[1]
ref=Path('/home/tushar/Documents/code/tasbih_web')
report={}
for name in ['index.html','styles.css','script.js','config.js','project-overview.md','readme.md','icon.svg','icon-maskable.svg','manifest.webmanifest','sw.js']:
    remote=urllib.request.urlopen('https://raw.githubusercontent.com/tushar-454/tasbihh/main/'+name).read()
    report[name]={'sha256':hashlib.sha256(remote).hexdigest(),'matches_local':remote== (ref/name).read_bytes()}
(root/'docs/reference-hashes.json').write_text(json.dumps(report,indent=2)+'\n')
for family,files in [('amiri',['Amiri-Regular.ttf','Amiri-Bold.ttf','OFL.txt']),('ibmplexsansarabic',['IBMPlexSansArabic-Regular.ttf','IBMPlexSansArabic-Medium.ttf','IBMPlexSansArabic-SemiBold.ttf','OFL.txt'])]:
    for f in files:
        url=f'https://raw.githubusercontent.com/google/fonts/main/ofl/{family}/{f}'
        try:
            data=urllib.request.urlopen(url).read()
            (root/'assets/fonts'/ (family+'-OFL.txt' if f=='OFL.txt' else f)).write_bytes(data)
            print(f,len(data))
        except Exception as e: print(url,str(e))
