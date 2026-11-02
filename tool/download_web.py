"""Render downloads the exact build that passed CI for its commit."""
from pathlib import Path
import hashlib
import io
import os
import re
import urllib.request
import zipfile

commit = os.environ['RENDER_GIT_COMMIT']
if not re.fullmatch(r'[a-f0-9]{40}', commit):
    raise ValueError('Invalid commit')
base = f'https://github.com/klqmy/computer_club/releases/download/web-{commit}'
def download(name):
    with urllib.request.urlopen(base + '/' + name, timeout=90) as response:
        return response.read()
data = download('web.zip')
expected = download('web.zip.sha256').decode().split()[0]
if hashlib.sha256(data).hexdigest() != expected:
    raise ValueError('Build checksum mismatch')
target = Path('site').resolve()
target.mkdir(exist_ok=True)
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for item in archive.infolist():
        if not (target / item.filename).resolve().is_relative_to(target):
            raise ValueError('Unsafe archive path')
    archive.extractall(target)
if not (target / 'index.html').is_file():
    raise ValueError('Missing entry point')
print('Build verified:', commit)
