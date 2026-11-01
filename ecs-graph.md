# ECS Entity Graph

How an ECS task definition, task, container, and container image relate in the AWS
data model. Ordered left to right by provenance, so every edge points the same way
and the image is the convergence point.

```mermaid
graph LR
    taskdef["ECS Task Definition<br/><small>family:revision — template</small>"]
    task["ECS Task<br/><small>running / stopped</small>"]
    ctr["Container<br/><small>running instance</small>"]
    img["Container Image<br/><small>ECR / registry digest</small>"]

    taskdef -->|"run → creates"| task
    task    -->|"schedules"| ctr
    ctr     -->|"runs"| img
    taskdef -->|"references"| img

    classDef def fill:#e4efe8,stroke:#2f6f4f,color:#1b1f24;
    classDef run fill:#eef1f4,stroke:#8795a3,color:#1b1f24;
    classDef image fill:#fbf0dd,stroke:#b58a30,color:#1b1f24;
    class taskdef def;
    class task,ctr run;
    class img image;
```

| Edge | Relationship | Meaning |
|------|--------------|---------|
| `run → creates` | Task Definition → Task | RunTask / StartTask instantiates the template into a running task |
| `schedules` | Task → Container | A task groups one or more co-scheduled containers |
| `runs` | Container → Image | A running container is one instantiation of an image |
| `references` | Task Definition → Image | Each container definition inside the task def pins an image — the attacker-controllable link |
