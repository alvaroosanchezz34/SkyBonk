"""
studio_bridge  (herramienta de desarrollo)

Servidor HTTP local para sincronizar Roblox Studio con el repositorio sin el
plugin de Rojo (desde execute_luau del MCP o la barra de comandos de Studio,
con HttpService.HttpEnabled activado en la sesión de edición):

  GET  /list                  rutas y clases de src/ en el DataModel (sin código)
  GET  /file?i=N              código fuente del elemento N de /list
  POST /asset?name=X&part=K   trozo K (hexadecimal) de assets/X.rbxm; K=1 lo reinicia

El repositorio es la fuente de verdad; `rojo build default.project.json`
produce el mismo árbol (los .rbxm de assets/ van a ServerStorage/SkyBonkAssets).

Uso:  python tools/studio_bridge.py      (puerto 34873, solo 127.0.0.1)
"""

import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 34873
MAPPINGS = [
    ("src/shared", "ReplicatedStorage/Shared"),
    ("src/server", "ServerScriptService"),
    ("src/client", "StarterPlayer/StarterPlayerScripts"),
    ("src/character", "StarterPlayer/StarterCharacterScripts"),
]


def classify(file_name):
    for suffix, class_name in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if file_name.endswith(suffix):
            return file_name[: -len(suffix)], class_name
    if file_name.endswith(".model.json"):
        return file_name[: -len(".model.json")], "Model"
    return None, None


def collect(directory, path, out):
    for entry in sorted(os.listdir(directory)):
        full = os.path.join(directory, entry)
        if os.path.isdir(full):
            out.append({"Path": f"{path}/{entry}", "ClassName": "Folder"})
            collect(full, f"{path}/{entry}", out)
            continue
        name, class_name = classify(entry)
        if class_name == "Model":
            with open(full, encoding="utf-8") as handle:
                out.append({"Path": f"{path}/{name}", "ClassName": json.load(handle)["className"]})
        elif name:
            with open(full, encoding="utf-8") as handle:
                out.append({"Path": f"{path}/{name}", "ClassName": class_name, "Source": handle.read()})


def list_all():
    out = []
    for directory, path in MAPPINGS:
        collect(os.path.join(ROOT, directory), path, out)
    return out


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if url.path == "/list":
            items = [
                {"Index": i + 1, "Path": it["Path"], "ClassName": it["ClassName"], "HasSource": "Source" in it}
                for i, it in enumerate(list_all())
            ]
            return self._send(200, json.dumps(items), "application/json")
        if url.path == "/file":
            items = list_all()
            index = int(query.get("i", ["0"])[0])
            if 1 <= index <= len(items) and "Source" in items[index - 1]:
                return self._send(200, items[index - 1]["Source"])
            return self._send(404, "sin código")
        return self._send(404, "not found")

    def do_POST(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if url.path != "/asset":
            return self._send(404, "not found")
        name = query.get("name", [""])[0]
        part = int(query.get("part", ["1"])[0])
        if not re.fullmatch(r"[A-Za-z0-9_]+", name):
            return self._send(400, "nombre inválido")
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode("ascii")
        os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
        path = os.path.join(ROOT, "assets", name + ".rbxm")
        with open(path, "wb" if part <= 1 else "ab") as handle:
            handle.write(bytes.fromhex(body))
        size = os.path.getsize(path)
        print(f"[bridge] assets/{name}.rbxm parte {part} ({size} bytes)", flush=True)
        return self._send(200, f"ok {size}")

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    print(f"[bridge] escuchando en http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
