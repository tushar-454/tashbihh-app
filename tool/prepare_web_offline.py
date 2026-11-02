"""Run after flutter build web; cache the entire local Flutter app shell."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]/'build/web'
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in ['offline-worker.js','flutter_service_worker.js'] and not p.name.endswith(('.map','.symbols')))
version=hashlib.sha256(b''.join(p.read_bytes() for p in files)).hexdigest()[:16]
urls=['./'+p.relative_to(root).as_posix() for p in files]+['./']
worker='''const CACHE = 'tasbih-native-web-VERSION';
const SHELL = URLS;
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('tasbih-native-web-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith(caches.match(event.request).then(cached => cached || fetch(event.request).catch(error => {
    if (event.request.mode === 'navigate') return caches.match('./index.html');
    throw error;
  })));
});
'''.replace('VERSION',version).replace('URLS',json.dumps(urls))
(root/'offline-worker.js').write_text(worker)
print(f'Offline cache prepared: {len(files)} local files, version {version}')
