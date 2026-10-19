"""Streamable gzip chunks for the complete runtime, preserving image-pack revision."""
import gzip
import hashlib
import json
import mimetypes
import shutil
from pathlib import Path

CHUNK = 1024 * 1024


def prepare(root):
    root = Path(root)
    # Recover originals removed by a previous preparation before a repeat run.
    previous = root/'runtime-data-manifest.json'
    if previous.exists():
        old = json.loads(previous.read_text())
        for entry in old['files']:
            path = root/entry['path']
            if not path.exists():
                packed = b''.join((root/old['chunks'][i][0]).read_bytes() for i in entry['chunks'])
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(gzip.decompress(packed))
    paths = [p for folder in ('assets', 'canvaskit') for p in (root/folder).rglob('*') if p.is_file()]
    paths += [root/name for name in ('main.dart.js','index.html','flutter_bootstrap.js','map-cache.js','diagnostics.js') if (root/name).exists()]
    dest = root/'runtime-data'
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir()
    files, chunks, by_hash = [], [], {}
    for path in sorted(paths):
        data = path.read_bytes()
        packed = gzip.compress(data, compresslevel=6, mtime=0)
        ids = []
        for start in range(0, len(packed), CHUNK):
            part = packed[start:start+CHUNK]
            digest = hashlib.sha256(part).hexdigest()
            if digest not in by_hash:
                name = f'runtime-data/{digest}.bin'
                (root/name).write_bytes(part)
                by_hash[digest] = len(chunks)
                chunks.append([name,digest,len(part)])
            ids.append(by_hash[digest])
        mime = mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
        if path.suffix == '.wasm': mime = 'application/wasm'
        files.append(dict(path=str(path.relative_to(root)),sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),mime=mime,chunks=ids))
    payload = json.dumps(dict(chunks=chunks,files=files),separators=(',',':')).encode()
    revision = hashlib.sha256(payload).hexdigest()
    manifest = dict(schema=1,revision=revision,bytes=sum(c[2] for c in chunks),chunks=chunks,files=files)
    previous.write_text(json.dumps(manifest,separators=(',',':'))+'\n')
    # These large raw files are served from the verified gzip chunks by the worker.
    # Canonical source assets remain untouched. Avoid duplicating 428 MiB on Pages.
    for entry in files:
        if entry['path'].startswith(('assets/assets/data/prefectures/', 'assets/assets/data/national_territories/')) or entry['path']=='assets/assets/data/japan.json':
            (root/entry['path']).unlink()
    worker = root/'map-cache-worker.js'
    worker.write_text(worker.read_text().replace('__RUNTIME_DATA_REVISION__',revision))
    print(f'Runtime local store: {len(files)} files, {len(chunks)} chunks, {manifest["bytes"]:,} compressed bytes; revision {revision[:12]}')


if __name__ == '__main__':
    import sys
    prepare(Path(sys.argv[1] if len(sys.argv)>1 else 'build/web'))
