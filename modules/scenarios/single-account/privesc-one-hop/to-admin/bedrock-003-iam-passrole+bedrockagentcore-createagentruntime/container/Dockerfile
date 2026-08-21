FROM python:3.12-slim

WORKDIR /app

COPY server.py .

# AgentCore Runtime invokes the container over HTTP on port 8080.
# The runtime platform requires:
#   GET  /ping         → health check, must return 200
#   POST /invocations  → inference/command endpoint, must return 200
EXPOSE 8080

CMD ["python", "server.py"]
