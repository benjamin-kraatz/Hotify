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
        # Two projects. The first has two environments, one of them with a stopped app, and one resource that fails.
        self.projects = [
            {"id": 1, "uuid": "storefront", "name": "Storefront", "description": "The shop, its API, and what they store.", "created_at": "2026-03-02T09:30:00.000000Z", "environments": [
                {"id": 1, "uuid": "env-prod", "name": "production", "description": None},
                {"id": 2, "uuid": "env-staging", "name": "staging", "description": "Release candidates"},
            ]},
            {"id": 2, "uuid": "tools", "name": "Internal tools", "description": None, "created_at": "2026-06-11T14:00:00.000000Z", "environments": [
                {"id": 3, "uuid": "env-tools", "name": "production", "description": None},
            ]},
        ]
        # Shared variables by scope: a project uuid, or a project uuid and an environment uuid.
        self.shared = {
            ("storefront",): [
                {"id": 1, "key": "API_URL", "value": "https://api.fixture.example", "is_literal": True, "comment": "Used by web and the API"},
                {"id": 2, "key": "STRIPE_SECRET_KEY", "is_shown_once": True},
            ],
            ("storefront", "env-prod"): [{"id": 3, "key": "LOG_LEVEL", "value": "warn"}],
        }
        # Applications, the database, and the standing service carry the settings the Settings tab edits.
        health = {
            "health_check_enabled": 1, "health_check_type": "http", "health_check_method": "GET",
            "health_check_scheme": "http", "health_check_host": "localhost", "health_check_port": None,
            "health_check_path": "/", "health_check_return_code": 200, "health_check_response_text": None,
            "health_check_interval": 5, "health_check_timeout": 5, "health_check_retries": 10,
            "health_check_start_period": 5,
        }
        self.applications = {
            "web": {"uuid": "web", "id": 1, "name": "Fixture Web", "description": None, "status": "running:healthy", "fqdn": "https://fixture.example", "environment_id": 1, "build_pack": "nixpacks", "redirect": "both", "preview_url_template": "{{pr_id}}.{{domain}}", "git_repository": "coollabsio/coolify", "git_branch": "main", "settings": {"is_preview_deployments_enabled": 1, "is_force_https_enabled": 1}, **health},
            # Not on github.com, so its previews go without pull request titles.
            "api": {"uuid": "api", "id": 2, "name": "Fixture API", "description": None, "status": "running:unhealthy", "fqdn": "https://api.fixture.example", "environment_id": 1, "build_pack": "dockerfile", "redirect": "both", "preview_url_template": "{{pr_id}}.{{domain}}", "git_repository": "https://gitlab.fixture.example/shop/api.git", "git_branch": "main", "settings": {"is_force_https_enabled": 1}, **health, "health_check_path": "/health", "health_check_port": "8080"},
            "web-staging": {"uuid": "web-staging", "id": 3, "name": "Fixture Web", "description": None, "status": "exited", "fqdn": "https://staging.fixture.example", "environment_id": 2, "build_pack": "nixpacks", "redirect": "both", "git_repository": "coollabsio/coolify", "git_branch": "develop", "settings": {"is_force_https_enabled": 0}, **health, "health_check_enabled": 0},
        }
        self.database = {"uuid": "db", "name": "Fixture Postgres", "description": None, "database_type": "standalone-postgresql", "status": "running:healthy", "environment_id": 1, "is_public": False, "public_port": None, "health_check_enabled": True, "health_check_interval": 15, "health_check_timeout": 5, "health_check_retries": 5, "health_check_start_period": 5}
        self.standing = {"uuid": "metrics", "name": "metrics", "description": None, "service_type": "grafana-with-postgresql", "status": "running:healthy", "environment_id": 3, "applications": [
            {"id": 1, "name": "grafana", "human_name": "Grafana", "status": "running:healthy", "fqdn": "https://grafana.fixture.example"},
            {"id": 2, "name": "postgres", "status": "running:healthy"},
        ]}
        # New environments and shared variables count up from here, clear of the ids above.
        self.next_id = 100
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
            return self.respond([{k: p.get(k) for k in ("id", "uuid", "name", "description")} for p in self.server.projects])
        if path.startswith("/projects/"):
            parts = path.split("/")[2:]
            project = next((p for p in self.server.projects if p["uuid"] == parts[0]), None)
            if project is None:
                return self.respond({"message": "Project not found."}, 404)
            if len(parts) == 1:
                return self.respond(project)
            if parts[-1] == "envs":
                return self.respond(copy.deepcopy(self.server.shared.get(self.scope(project, parts), [])))
        if path == "/servers/server/destinations":
            return self.respond([{"uuid": "fixture-network", "name": "Fixture network", "network": "coolify", "server_uuid": "server"}])
        if path == "/servers":
            return self.respond([{"uuid": "server", "name": "Fixture server", "is_reachable": 1}])
        if path == "/applications":
            return self.respond(list(self.server.applications.values()))
        if path.startswith("/applications/") and path.count("/") == 2:
            record = self.server.applications.get(path.split("/")[2])
            return self.respond(record) if record else self.respond({"message": "Application not found"}, 404)
        if path == "/databases":
            return self.respond([self.server.database])
        if path == "/databases/db":
            return self.respond(self.server.database)
        if path == "/services":
            return self.respond([self.server.standing] + [self.server.service(uuid) for uuid in self.server.services])
        if path == "/services/metrics":
            return self.respond(self.server.standing)
        if path.startswith("/services/") and path.endswith("/envs"):
            record = self.server.services.get(path.split("/")[2])
            return self.respond(copy.deepcopy(record["envs"])) if record else self.respond({"message": "Service not found."}, 404)
        if path.startswith("/services/") and path.count("/") == 2:
            uuid = path.split("/")[2]
            return self.respond(self.server.service(uuid)) if uuid in self.server.services else self.respond({"message": "Service not found."}, 404)
        if path == "/deployments":
            return self.respond([{"deployment_uuid": "api-pr-7", "application_id": 2, "application_name": "Fixture API", "pull_request_id": 7, "status": "in_progress"}])
        if path == "/deployments/applications/api":
            return self.respond({"count": 3, "deployments": [
                {"deployment_uuid": "api-pr-7", "application_id": 2, "pull_request_id": 7, "status": "in_progress", "commit": "9f2c1ab4", "commit_message": "feat: rate limits", "created_at": now()},
                {"deployment_uuid": "api-2", "application_id": 2, "pull_request_id": 0, "status": "finished", "commit": "5aa01e77", "commit_message": "fix: retry on 502", "created_at": "2026-09-30T16:20:00Z", "finished_at": "2026-09-30T16:21:30Z"},
                {"deployment_uuid": "api-pr-5", "application_id": 2, "pull_request_id": 5, "status": "failed", "commit": "77aa01e0", "commit_message": "chore: bump node to 24", "created_at": "2026-09-28T09:00:00Z", "finished_at": "2026-09-28T09:00:40Z"},
            ]})
        if path == "/deployments/applications/web-staging":
            return self.respond({"count": 1, "deployments": [
                {"deployment_uuid": "staging-1", "application_id": 3, "pull_request_id": 0, "status": "failed", "commit": "c0ffee12", "commit_message": "feat: new checkout", "created_at": "2026-09-30T08:00:00Z", "finished_at": "2026-09-30T08:01:10Z"},
            ]})
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
        if path.startswith("/deployments/") and path.count("/") == 2:
            return self.respond({"deployment_uuid": path.rsplit("/", 1)[1], "status": "finished", "commit_message": "Fixture deployment", "logs": [{"output": "Fixture build output"}]})
        if path.endswith("/envs"):
            return self.respond(copy.deepcopy(self.server.variables))
        if path.endswith("/logs"):
            return self.respond({"logs": "2026-09-29T12:00:00Z Fixture ready\n"})
        if path == "/databases/db/backups":
            return self.respond([{"uuid": "daily", "enabled": "1", "frequency": "daily", "databases_to_backup": "app", "executions": self.server.executions}])
        return self.respond({"message": "Fixture endpoint not found"}, 404)

    @staticmethod
    def scope(project, parts):
        """`[uuid, "envs"]` is the project. `[uuid, "environments", ref, "envs", ...]` is one environment."""
        if parts[1] != "environments":
            return (project["uuid"],)
        environment = next((e for e in project["environments"] if parts[2] in (e["uuid"], e["name"])), None)
        return (project["uuid"], environment["uuid"] if environment else parts[2])

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
            if path.startswith("/projects/"):
                return self.write_project(path.split("/")[2:], body)
            if self.command == "PATCH" and path.count("/") == 2 and not path.startswith("/services/svc-"):
                handled = self.write_settings(path, body)
                if handled is not None:
                    return handled
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


    HEALTH = {"health_check_enabled", "health_check_interval", "health_check_timeout", "health_check_retries", "health_check_start_period"}
    APPLICATION_FIELDS = HEALTH | {"name", "description", "domains", "redirect", "is_force_https_enabled", "docker_compose_domains", "force_domain_override", "health_check_type", "health_check_command", "health_check_method", "health_check_scheme", "health_check_host", "health_check_port", "health_check_path", "health_check_return_code", "health_check_response_text"}

    def write_settings(self, path, body):
        """Settings of an application, the database, and the standing service, with Coolify's 422 for a field it
        does not take and 409 for an address containing `taken.example` until it is forced."""
        kind, uuid = path.split("/")[1:3]
        if kind == "applications":
            record, allowed = self.server.applications.get(uuid), self.APPLICATION_FIELDS
        elif kind == "databases" and uuid == "db":
            record, allowed = self.server.database, self.HEALTH | {"name", "description", "is_public", "public_port"}
        elif kind == "services" and uuid == "metrics":
            record, allowed = self.server.standing, {"name", "description", "urls", "force_domain_override"}
        else:
            return None
        if record is None:
            return self.respond({"message": "Not found."}, 404)
        extra = set(body) - allowed
        if extra:
            return self.respond({"message": "Validation failed.", "errors": {field: ["This field is not allowed."] for field in extra}}, 422)
        addresses = [body.get("domains") or ""] + [item.get("url") or "" for item in body.get("urls", [])] + [item.get("domain") or "" for item in body.get("docker_compose_domains", [])]
        taken = [a for a in ",".join(addresses).split(",") if "taken.example" in a]
        if taken and not body.get("force_domain_override"):
            return self.respond({"message": "Domain conflicts detected. Use force_domain_override=true to proceed.", "conflicts": [{"domain": a, "resource_name": "Fixture Web", "resource_type": "application"} for a in taken], "warning": "Shared domains split traffic."}, 409)
        if kind == "databases" and body.get("is_public") and body.get("public_port") == 5432:
            return self.respond({"message": "Public port already used by another database."}, 400)
        for item in body.pop("urls", []):
            for container in record["applications"]:
                if container["name"] == item["name"]:
                    container["fqdn"] = item["url"] or None
        body.pop("force_domain_override", None)
        if "domains" in body:
            record["fqdn"] = body.pop("domains") or None
        if "is_force_https_enabled" in body:
            record.setdefault("settings", {})["is_force_https_enabled"] = body.pop("is_force_https_enabled")
        if "docker_compose_domains" in body:
            record["docker_compose_domains"] = json.dumps({item["name"]: {"domain": item["domain"]} for item in body.pop("docker_compose_domains")})
        record.update(body)
        if kind == "applications":
            return self.respond({"uuid": uuid})
        if kind == "databases":
            return self.respond({"message": "Database updated."})
        return self.respond({"uuid": uuid, "domains": [c["fqdn"] for c in record["applications"] if c.get("fqdn")]})

    def write_project(self, parts, body):
        """Renames, new environments, and shared variables. Like Coolify, it answers 422 to a field it does not list."""
        project = next((p for p in self.server.projects if p["uuid"] == parts[0]), None)
        if project is None:
            return self.respond({"message": "Project not found."}, 404)
        if "envs" in parts:
            return self.write_shared(project, parts, body)
        allowed = {"name"} if self.command == "POST" else {"name", "description"}
        extra = set(body) - allowed
        if extra or len(body.get("name") or "xxx") < 3:
            errors = {field: ["This field is not allowed."] for field in extra} or {"name": ["The name must be at least 3 characters."]}
            return self.respond({"message": "Validation failed.", "errors": errors}, 422)
        if len(parts) == 1 and self.command == "PATCH":
            project.update(body)
            return self.respond({k: project.get(k) for k in ("uuid", "name", "description")}, 201)
        taken = [e for e in project["environments"] if e["name"] == body.get("name")]
        if parts[1:] == ["environments"] and self.command == "POST":
            if taken:
                return self.respond({"message": "Environment with this name already exists."}, 409)
            self.server.next_id += 1
            environment = {"id": self.server.next_id, "uuid": f"env-{self.server.next_id}", "name": body["name"], "description": None}
            project["environments"].append(environment)
            return self.respond({"uuid": environment["uuid"]}, 201)
        if len(parts) == 3 and parts[1] == "environments" and self.command == "PATCH":
            environment = next((e for e in project["environments"] if parts[2] in (e["uuid"], e["name"])), None)
            if environment is None:
                return self.respond({"message": "Environment not found."}, 404)
            if any(e is not environment for e in taken):
                return self.respond({"message": "Environment with this name already exists."}, 409)
            environment.update(body)
            return self.respond({k: environment.get(k) for k in ("uuid", "name", "description")})
        return self.respond({"message": "Fixture write not supported"}, 404)

    def write_shared(self, project, parts, body):
        variables = self.server.shared.setdefault(self.scope(project, parts), [])
        extra = set(body) - {"key", "value", "is_literal", "is_multiline", "is_shown_once", "comment"}
        if extra:
            return self.respond({"message": "Validation failed.", "errors": {field: ["This field is not allowed."] for field in extra}}, 422)
        if parts[-1] == "envs" and self.command == "POST":
            if any(v["key"] == body.get("key") for v in variables):
                return self.respond({"message": "Environment variable already exists. Use PATCH request to update it."}, 409)
            self.server.next_id += 1
            variables.append({"id": self.server.next_id, **body})
            return self.respond({"id": self.server.next_id}, 201)
        target = next((v for v in variables if str(v["id"]) == parts[-1]), None)
        if target is None:
            return self.respond({"message": "Environment variable not found."}, 404)
        if self.command == "DELETE":
            variables.remove(target)
            return self.respond({"message": "Environment variable deleted."})
        target.update(body)
        if target.get("is_shown_once"):
            target.pop("value", None)
        return self.respond(target)


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
