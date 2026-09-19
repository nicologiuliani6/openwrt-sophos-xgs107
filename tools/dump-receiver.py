#!/usr/bin/env python3
"""Receive device dumps over HTTP PUT into dumps/ and print their sha256.

The XGS streams straight into it, with no temp files on the appliance:
  xgs-ssh.sh "cat /dev/mtd0" | curl -sS -T - http://<pc>:8000/npu/mtd0.bin

  python3 tools/dump-receiver.py [port]      (Ctrl-C to stop)

Paths are confined to dumps/. Existing files are never overwritten: a
re-upload of the same name is rejected with 409, so a verified dump can't
be clobbered by a bad second attempt.
"""
import hashlib, http.server, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(REPO, 'dumps')


class Handler(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        dest = os.path.realpath(os.path.join(ROOT, self.path.lstrip('/')))
        if not dest.startswith(ROOT + os.sep):
            return self.send_error(403)
        if os.path.exists(dest):
            return self.send_error(409, 'exists')
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        h, n = hashlib.sha256(), 0
        chunked = self.headers.get('Transfer-Encoding', '').lower() == 'chunked'
        left = None if chunked else int(self.headers.get('Content-Length', 0))
        with open(dest + '.part', 'wb') as f:
            while True:
                if chunked:
                    size = int(self.rfile.readline().split(b';')[0], 16)
                    if size == 0:
                        self.rfile.readline()
                        break
                    data = self.rfile.read(size)
                    self.rfile.readline()
                else:
                    if left == 0:
                        break
                    data = self.rfile.read(min(left, 1 << 20))
                    left -= len(data)
                    if not data:
                        break
                f.write(data)
                h.update(data)
                n += len(data)
        os.rename(dest + '.part', dest)
        line = f'{h.hexdigest()}  {n}  {os.path.relpath(dest, REPO)}'
        print(line, flush=True)
        with open(os.path.join(ROOT, 'SHA256SUMS.received'), 'a') as s:
            s.write(line + '\n')
        self.send_response(201)
        self.end_headers()
        self.wfile.write((line + '\n').encode())

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    os.makedirs(ROOT, exist_ok=True)
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f'receiving into {ROOT} on :{port}', flush=True)
    http.server.ThreadingHTTPServer(('', port), Handler).serve_forever()
