#!/usr/bin/env python3
"""Two local, in-memory Coolify fixtures. Never reads .env or contacts a real instance."""
import copy
import datetime
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class Fixture(ThreadingHTTPServer):
    def __init__(self, port, source):
        super().__init__(("127.0.0.1", port), Handler)
        self.events = []
        self.source = source
        self.variables = [
            {"uuid": "url", "key": "API_URL", "value": "https://source.example" if source else "https://destination.example", "is_preview": False, "is_runtime": True, "is_buildtime": True},
            {"uuid": "only", "key": "SOURCE_ONLY" if source else "DESTINATION_ONLY", "value": "fixture-value", "is_preview": False},
            {"uuid": "preview", "key": "PREVIEW_ONLY", "value": "preview-value", "is_preview": True},
        ]
        self.executions = [{"uuid": "failed-backup", "status": "failed", "message": "Fixture storage unavailable", "created_at": now(), "size": "0"}]
        self.lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log headers, tokens, or variable bodies.

    def respond(self, payload, status=200):
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        with self.server.lock:
            self.get()

    def get(self):
        parsed = urlsplit(self.path)
        path = parsed.path.removeprefix("/api/v1")
        if path == "/__fixture/events":
            return self.respond(self.server.events)
        if path == "/version":
            return self.respond("4.3.23")
        if path == "/health":
            return self.respond("OK")
        if path == "/team":
            return self.respond({"id": 1, "name": "Fixture team"})
        if path == "/projects":
            return self.respond([])
        if path == "/servers":
            return self.respond([{"uuid": "server", "name": "Fixture server", "is_reachable": 1}])
        if path == "/applications":
            return self.respond([{"uuid": "web", "id": 1, "name": "Fixture Web", "status": "running:healthy", "fqdn": "https://fixture.example"}])
        if path == "/databases":
            return self.respond([{"uuid": "db", "name": "Fixture Postgres", "database_type": "standalone-postgresql", "status": "running:healthy"}])
        if path == "/services":
            return self.respond([])
        if path == "/deployments":
            return self.respond([])
        if path == "/deployments/applications/web":
            query = parse_qs(parsed.query)
            take = int(query.get("take", [20])[0])
            skip = int(query.get("skip", [0])[0])
            return self.respond({"count": 25, "deployments": [self.deployment(i) for i in range(skip, min(skip + take, 25))]})
        if path.startswith("/deployments/build-"):
            result = self.deployment(int(path.rsplit("-", 1)[1]))
            result["logs"] = json.dumps([{"timestamp": "2026-09-29T12:00:00Z", "output": "Installing dependencies"}, {"timestamp": "2026-09-29T12:00:10Z", "output": "ERROR: fixture build failed"}])
            return self.respond(result)
        if path.endswith("/envs"):
            return self.respond(copy.deepcopy(self.server.variables))
        if path.endswith("/logs"):
            return self.respond({"logs": "2026-09-29T12:00:00Z Fixture ready\n"})
        if path == "/databases/db/backups":
            return self.respond([{"uuid": "daily", "enabled": "1", "frequency": "daily", "databases_to_backup": "app", "executions": self.server.executions}])
        return self.respond({"message": "Fixture endpoint not found"}, 404)

    @staticmethod
    def deployment(index):
        return {"deployment_uuid": f"build-{index}", "application_id": 1, "status": "failed" if index == 0 else "finished", "commit": "0123456789abcdef", "commit_message": f"Fixture deployment {index + 1}", "created_at": "2026-09-29T12:00:00Z", "finished_at": "2026-09-29T12:00:10Z"}

    def do_POST(self):
        self.write()

    def do_PATCH(self):
        self.write()

    def do_DELETE(self):
        self.write()

    def write(self):
        with self.server.lock:
            path = urlsplit(self.path).path.removeprefix("/api/v1")
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            self.server.events.append({"method": self.command, "path": path})
            if path == "/databases/db/backups/daily" and body == {"backup_now": True}:
                self.server.executions.insert(0, {"uuid": f"backup-{len(self.server.executions)}", "status": "success", "message": "Fixture backup completed", "created_at": now(), "size": "1024", "filename": "fixture.sql"})
                return self.respond({"message": "Database backup configuration updated"})
            if path.endswith("/envs"):
                target = next((v for v in self.server.variables if v["key"] == body["key"] and v.get("is_preview", False) == body.get("is_preview", False)), None)
                if self.command == "POST":
                    if target:
                        return self.respond({"message": "Already exists"}, 409)
                    target = {"uuid": f"v-{len(self.server.variables)}"}
                    self.server.variables.append(target)
                if target is None:
                    return self.respond({"message": "Not found"}, 404)
                target.update(body)
                return self.respond(target, 201)
            if "/envs/" in path and self.command == "DELETE":
                self.server.variables[:] = [v for v in self.server.variables if v["uuid"] != path.rsplit("/", 1)[1]]
                return self.respond({"message": "Deleted"})
            if path == "/deploy" or path.endswith("/restart"):
                return self.respond({"message": "Queued", "deployments": []})
            return self.respond({"message": "Fixture write not supported"}, 404)


if __name__ == "__main__":
    servers = [Fixture(18081, True), Fixture(18082, False)]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("Fixture Coolify servers listening on 127.0.0.1:18081 and :18082", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()
