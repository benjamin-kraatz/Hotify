#!/usr/bin/env python3
"""Two local, in-memory Coolify fixtures. Never reads .env or contacts a real instance."""
import copy
import datetime
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


# A Next.js build that fails on a type error, in the shape Coolify reports it.
FAILED_BUILD = [
    "Starting deployment of benn/storefront:main to localhost.",
    "Preparing container with helper image: ghcr.io/coollabsio/coolify-helper:1.0.12",
    "Importing benn/storefront:main (commit sha 77aa01e) to /artifacts/kc8s4w0.",
    "Cloning into '/artifacts/kc8s4w0'...",
    "Generating nixpacks configuration with: nixpacks plan -f json /artifacts/kc8s4w0",
    "Found application type: node.",
    "Building docker image started.",
    "#5 [stage-0  1/10] FROM ghcr.io/railwayapp/nixpacks:ubuntu-1745885067",
    "#5 DONE 0.0s",
    "#8 [stage-0  4/10] RUN nix-env -if .nixpacks/nixpkgs-ffeebf0.nix && nix-collect-garbage -d",
    "#8 CACHED",
    "#10 [stage-0  6/10] RUN npm ci",
    "#10 4.812 npm warn deprecated inflight@1.0.6: This module is not supported, and leaks memory.",
    "#10 5.120 npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported",
    "#10 11.42 added 412 packages, and audited 413 packages in 11s",
    "#10 DONE 12.1s",
    "#11 [stage-0  7/10] COPY . /app/.",
    "#11 DONE 0.4s",
    "#12 [stage-0  8/10] RUN npm run build",
    "#12 0.412 > storefront@2.4.0 build",
    "#12 0.412 > next build",
    "#12 1.902    ▲ Next.js 15.3.1",
    "#12 1.934    Creating an optimized production build ...",
    "#12 19.33  ✓ Compiled successfully in 17.0s",
    "#12 19.34    Linting and checking validity of types ...",
    "#12 27.81 Failed to compile.",
    "#12 27.81 ./src/app/checkout/page.tsx:42:27",
    "#12 27.81 Type error: Property 'currency' does not exist on type 'Cart'.",
    "#12 27.81   40 |   const cart = await getCart();",
    "#12 27.81   41 |   return (",
    "#12 27.81 > 42 |     <Total amount={cart.total} currency={cart.currency} />",
    "#12 27.81      |                           ^",
    "#12 27.85 Next.js build worker exited with code: 1 and signal: null",
    "#12 ERROR: process \"/bin/bash -ol pipefail -c npm run build\" did not complete successfully: exit code: 1",
    "------",
    " > [stage-0  8/10] RUN npm run build:",
    "27.81 Type error: Property 'currency' does not exist on type 'Cart'.",
    "------",
    "Dockerfile:24",
    "ERROR: failed to solve: process \"/bin/bash -ol pipefail -c npm run build\" did not complete successfully: exit code: 1",
    "Deployment failed. Removing the new version of your application.",
    "Oops something is not okay, are you okay? 😢",
]
FINISHED_BUILD = ["Starting deployment of benn/storefront:main to localhost.", "Building docker image completed.", "New container started."]


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
        self.projects = [{"uuid": "fixture-project", "name": "Fixture project", "environments": [{"id": 1, "uuid": "fixture-production", "name": "production"}]}]
        # Services created from templates. Each comes up a few seconds after its start request.
        self.services = {}
        self.lock = threading.Lock()

    def service(self, uuid):
        record = self.services[uuid]
        started = record.get("started_at")
        elapsed = time.monotonic() - started if started else None
        if elapsed is None or elapsed < 3:
            states = ["exited", "exited"]
        elif elapsed < 9:
            states = ["starting", "running:healthy"]
        else:
            states = ["running:healthy", "running:healthy"]
        app, db = record["containers"]
        applications = [{"id": 1, "name": app, "status": states[0], "image": f"{app}:latest", "fqdn": record["fqdn"]}]
        databases = [{"id": 2, "name": db, "status": states[1], "image": "postgres:16-alpine"}]
        status = "running:healthy" if states == ["running:healthy", "running:healthy"] else states[0]
        return {"uuid": uuid, "name": record["name"], "service_type": record["type"], "status": status, "environment_id": 1, "applications": applications, "databases": databases}


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
            return self.respond([{"uuid": p["uuid"], "name": p["name"]} for p in self.server.projects])
        if path.startswith("/projects/"):
            project = next((p for p in self.server.projects if p["uuid"] == path.split("/")[2]), None)
            return self.respond(project) if project else self.respond({"message": "Project not found."}, 404)
        if path == "/servers/server/destinations":
            return self.respond([{"uuid": "fixture-network", "name": "Fixture network", "network": "coolify", "server_uuid": "server"}])
        if path == "/servers":
            return self.respond([{"uuid": "server", "name": "Fixture server", "is_reachable": 1}])
        if path == "/applications":
            return self.respond([{"uuid": "web", "id": 1, "name": "Fixture Web", "status": "running:healthy", "fqdn": "https://fixture.example"}])
        if path == "/applications/web":
            return self.respond({"uuid": "web", "name": "Fixture Web", "git_repository": "coollabsio/coolify", "git_branch": "main", "settings": {"is_preview_deployments_enabled": 1}})
        if path == "/databases":
            return self.respond([{"uuid": "db", "name": "Fixture Postgres", "database_type": "standalone-postgresql", "status": "running:healthy"}])
        if path == "/services":
            return self.respond([self.server.service(uuid) for uuid in self.server.services])
        if path.startswith("/services/") and path.endswith("/envs"):
            record = self.server.services.get(path.split("/")[2])
            return self.respond(copy.deepcopy(record["envs"])) if record else self.respond({"message": "Service not found."}, 404)
        if path.startswith("/services/") and path.count("/") == 2:
            uuid = path.split("/")[2]
            return self.respond(self.server.service(uuid)) if uuid in self.server.services else self.respond({"message": "Service not found."}, 404)
        if path == "/deployments":
            return self.respond([])
        if path == "/deployments/applications/web":
            query = parse_qs(parsed.query)
            take = int(query.get("take", [20])[0])
            skip = int(query.get("skip", [0])[0])
            return self.respond({"count": 25, "deployments": [self.deployment(i) for i in range(skip, min(skip + take, 25))]})
        if path == "/deployments/preview-18":
            return self.respond({"deployment_uuid": "preview-18", "application_id": 1, "status": "finished", "pull_request_id": 18, "commit_message": "Fixture preview deployment", "logs": [{"output": "Preview ready"}]})
        if path.startswith("/deployments/build-"):
            index = int(path.rsplit("-", 1)[1])
            result = self.deployment(index)
            output = FAILED_BUILD if index == 0 else FINISHED_BUILD
            result["logs"] = json.dumps([{"timestamp": "2026-09-29T12:00:00Z", "output": line} for line in output])
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
        return {"deployment_uuid": f"build-{index}", "application_id": 1, "pull_request_id": 18 if index == 1 else 0, "status": "failed" if index == 0 else "finished", "commit": "0123456789abcdef", "commit_message": f"Fixture deployment {index + 1}", "created_at": "2026-09-29T12:00:00Z", "finished_at": "2026-09-29T12:00:10Z"}

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
            handled = self.provision(path, body)
            if handled is not None:
                return handled
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
            if path == "/deploy" and "pull_request_id" in parse_qs(urlsplit(self.path).query):
                query = parse_qs(urlsplit(self.path).query)
                number = int(query["pull_request_id"][0])
                self.server.events[-1]["pull_request_id"] = number
                self.server.events[-1]["resource_uuid"] = query.get("uuid", [None])[0]
                row = {"resource_uuid": "web"}
                if number == 18:
                    row.update({"message": "Queued", "deployment_uuid": "preview-18"})
                else:
                    row["message"] = f"Pull request {number} not found for this resource."
                return self.respond({"deployments": [row]})
            if path == "/deploy" or path.endswith("/restart"):
                return self.respond({"message": "Queued", "deployments": []})
            return self.respond({"message": "Fixture write not supported"}, 404)

    def provision(self, path, body):
        """Creates, sets up, starts, and deletes services the way Coolify 4.3 answers. `None` passes the request on."""
        services = self.server.services
        if path == "/services" and self.command == "POST":
            uuid = f"svc-{len(services) + 1}"
            name = body.get("name") or body["type"]
            fqdn = f"http://{name}-{uuid}.127.0.0.1.sslip.io"
            services[uuid] = {
                "name": name, "type": body["type"], "containers": [body["type"], "postgres"], "fqdn": fqdn,
                "envs": [
                    {"uuid": f"{uuid}-1", "key": "SERVICE_PASSWORD_POSTGRES", "value": "fixture-generated"},
                    {"uuid": f"{uuid}-2", "key": f"SERVICE_URL_{body['type'].upper().replace('-', '_')}", "value": fqdn},
                    {"uuid": f"{uuid}-3", "key": "POSTGRES_DB", "value": body["type"]},
                    {"uuid": f"{uuid}-4", "key": "ADMIN_EMAIL", "value": ""},
                    {"uuid": f"{uuid}-5", "key": "SMTP_PASSWORD", "value": ""},
                ],
            }
            return self.respond({"uuid": uuid, "domains": [fqdn]}, 201)
        if not path.startswith("/services/"):
            if path == "/projects" and self.command == "POST":
                uuid = f"project-{len(self.server.projects) + 1}"
                self.server.projects.append({"uuid": uuid, "name": body["name"], "environments": [{"id": 10 + len(self.server.projects), "uuid": f"{uuid}-production", "name": "production"}]})
                return self.respond({"uuid": uuid}, 201)
            if path.startswith("/projects/") and path.endswith("/environments") and self.command == "POST":
                project = next(p for p in self.server.projects if p["uuid"] == path.split("/")[2])
                uuid = f"{project['uuid']}-{body['name']}"
                project["environments"].append({"id": 20 + len(project["environments"]), "uuid": uuid, "name": body["name"]})
                return self.respond({"uuid": uuid}, 201)
            return None
        uuid = path.split("/")[2]
        record = services.get(uuid)
        if record is None:
            return None
        if path == f"/services/{uuid}" and self.command == "DELETE":
            del services[uuid]
            return self.respond({"message": "Service deletion request queued."})
        if path == f"/services/{uuid}" and self.command == "PATCH":
            for item in body.get("urls", []):
                if "taken.example" in item["url"] and not body.get("force_domain_override"):
                    return self.respond({"message": "Domain conflicts detected. Use force_domain_override=true to proceed.", "conflicts": [{"domain": item["url"], "resource_name": "Fixture Web", "resource_type": "application"}], "warning": "Shared domains split traffic."}, 409)
                record["fqdn"] = item["url"]
            return self.respond({"uuid": uuid, "domains": [record["fqdn"]]})
        if path == f"/services/{uuid}/envs/bulk":
            for item in body["data"]:
                target = next((v for v in record["envs"] if v["key"] == item["key"]), None)
                if target is None:
                    target = {"uuid": f"{uuid}-{len(record['envs']) + 1}", "key": item["key"]}
                    record["envs"].append(target)
                target["value"] = item["value"]
            return self.respond(copy.deepcopy(record["envs"]), 201)
        if path == f"/services/{uuid}/start":
            record["started_at"] = time.monotonic()
            return self.respond({"message": "Service starting request queued."})
        return None


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
