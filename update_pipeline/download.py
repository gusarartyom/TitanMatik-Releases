"""Fresh anonymous Drive downloads; never publish source names or URLs."""
import http.cookiejar
import json
import os
import re
import urllib.parse
import urllib.request
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from archive import sha256

def allowed_url(url):
    p = urllib.parse.urlsplit(url)
    return p.scheme == 'https' and not p.username and not p.password and p.port in (None, 443) and (p.hostname in ('drive.google.com', 'drive.usercontent.google.com') or (p.hostname or '').endswith('.googleusercontent.com'))

class DriveRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, url):
        if not allowed_url(url): raise ValueError('Login or unexpected source redirect')
        return super().redirect_request(req, fp, code, msg, headers, url)

class DownloadForm(HTMLParser):
    def __init__(self):
        super().__init__(); self.active=False; self.action=None; self.fields={}
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if tag=='form' and a.get('id')=='download-form':
            self.active=True; self.action=a.get('action')
        if tag=='input' and self.active and a.get('type')=='hidden':
            if a.get('name') in self.fields: raise ValueError('Duplicate confirmation field')
            self.fields[a.get('name')]=a.get('value','')
    def handle_endtag(self, tag):
        if tag=='form': self.active=False

def confirmation_url(html, file_id):
    text=html.lower()
    if 'too large for google to scan for viruses' not in text or any(marker in text for marker in ('identified as malware','identified as spam','g-recaptcha','request access')):
        raise ValueError('Source is not publicly downloadable')
    form=DownloadForm(); form.feed(html)
    if form.action!='https://drive.usercontent.google.com/download' or form.fields.get('id')!=file_id:
        raise ValueError('Unexpected confirmation form')
    if form.fields.get('export')!='download' or form.fields.get('confirm')!='t' or set(form.fields)-{'id','export','confirm','uuid'}:
        raise ValueError('Unsupported confirmation')
    return form.action+'?'+urllib.parse.urlencode(form.fields)

def open_response(opener,url):
    if not allowed_url(url): raise ValueError('Unexpected source address')
    return opener.open(urllib.request.Request(url,headers={'User-Agent':'TitanMatik-build/1.0'}),timeout=180)

def download_current(directory='build'):
    directory=Path(directory); directory.mkdir(parents=True,exist_ok=True)
    target=directory/'source.zip'; partial=directory/'source.zip.part'
    target.unlink(missing_ok=True); partial.unlink(missing_ok=True)
    (directory/'source-metadata.json').unlink(missing_ok=True)
    try:
        file_id=os.environ['UPDATE_DRIVE_FILE_ID']
        if not re.fullmatch('[A-Za-z0-9_-]+',file_id): raise ValueError('Invalid source configuration')
        opener=urllib.request.build_opener(DriveRedirect,urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        url='https://drive.google.com/uc?'+urllib.parse.urlencode({'export':'download','id':file_id})
        total=0
        for attempt in range(2):
            with open_response(opener,url) as response:
                first=response.read(4)
                if first!=b'PK\x03\x04':
                    if attempt: raise ValueError('Confirmation did not return ZIP')
                    html=first+response.read(512*1024+1)
                    if len(html)>512*1024: raise ValueError('Unexpected source response')
                    url=confirmation_url(html.decode('utf-8',errors='replace'),file_id)
                    continue
                declared=response.headers.get('Content-Length')
                with partial.open('wb') as output:
                    output.write(first); total=len(first)
                    while chunk:=response.read(1024*1024):
                        total+=len(chunk)
                        if total>2*1024**3: raise ValueError('Source exceeds size limit')
                        output.write(chunk)
                if declared and total!=int(declared): raise ValueError('Incomplete download')
                break
        with zipfile.ZipFile(partial) as archive:
            if not archive.infolist(): raise ValueError('Empty ZIP')
        digest=sha256(partial); partial.replace(target)
        (directory/'source-metadata.json').write_text(json.dumps({'origin':'public-drive','size':total,'source_sha256':digest}),encoding='utf-8')
        return digest
    finally:
        partial.unlink(missing_ok=True)

def main():
    digest=download_current()
    with open(os.environ['GITHUB_OUTPUT'],'a',encoding='utf-8') as output:
        output.write('sha256='+digest+'\n')

if __name__=='__main__':
    try: main()
    except Exception:
        print('Source download failed: unavailable, blocked, incomplete or invalid ZIP. Source URLs and identity suppressed.')
        raise SystemExit(1)
