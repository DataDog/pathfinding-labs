# Cost Reference (price book)

Infracost-validated monthly costs for the billable AWS resources used across Pathfinding Labs
scenarios. Used by the `scenario-cost-estimator` agent to fill `cost_estimate_when_demo_executed`
for **new-passrole** scenarios without re-deriving every price: a "new X with config C" created
during exploitation is priced identically to an "existing X with config C" that an
**existing-passrole** scenario stands up in Terraform. See `.claude/scenario-readme-schema.md`
(idle vs. running cost) and the agent's "Step 5b: Running cost".

All figures are us-east-1, on-demand, 730 hours/month, rounded to whole dollars. Regenerate a row
by running `infracost scan` on the cited scenario, or by synthesizing a minimal `.tf` for the
resource and scanning it.

## Standing resources (bill a monthly rate until explicitly deleted)

| Resource | Config | $/mo | Source / basis |
|---|---|---|---|
| `aws_instance` | t3.nano | $5 | existing-passrole `ssm-001` (incl. EBS) |
| `aws_instance` | t3.micro | $8 | existing-passrole `ec2-003`, `ssm-002`, `codedeploy-001` (infracost: 1 costed = $8) |
| `aws_instance` | t3.medium | $31 | $0.0416/hr x 730 + EBS |
| `aws_instance` | m5.large | $70 | $0.096/hr x 730 |
| `aws_instance` | m5.xlarge | $140 | $0.192/hr x 730 |
| `aws_instance` (spot) | t3.micro | $3 | spot ~$0.0035/hr x 730 + EBS |
| `aws_sagemaker_notebook_instance` | ml.t3.medium | $37 | existing-passrole `sagemaker-004`, `sagemaker-005` |
| `aws_glue_dev_endpoint` | 2 DPU | $634 | existing-passrole `glue-002` (2 x $0.44/hr x 730) |
| `aws_apprunner_service` | 1 vCPU / 2 GB | $10 | existing-passrole `apprunner-002` |
| `aws_ecs_service` (Fargate) | 0.25 vCPU / 0.5 GB | $9 | existing-passrole `ecs-006` |
| Kinesis Analytics / Managed Flink | 1 parallelism, 1/KPU | $166 | 2 KPU (1 app + 1 orchestration) x $0.11/hr x 730 + 50 GB running storage ($5); infracost does not price kinesisanalyticsv2 |

## Transient resources (run to completion / auto-terminate; no standing monthly cost)

These leave nothing running after the demo, so their running cost is `$0` (= idle) unless a bounded
safeguard makes a one-time burst worth surfacing (then size to the bounded run, e.g. the sysdig
p3.2xlarge GPU capped at 2 hours -> `$6/mo`).

- Lambda invocations; Step Functions executions; EventBridge Scheduler
- SageMaker **training** / **processing** jobs (auto-complete and stop)
- Glue **job runs** (`start-job-run`); Glue interactive **sessions** (idle-timeout bounded)
- AWS Batch jobs; EMR **Serverless** job runs; EMR clusters launched with `--auto-terminate`
- Amazon Braket jobs; HealthOmics workflow runs
- CodeBuild builds; EC2 Image Builder pipeline builds (build instance self-terminates)
- ECS `run-task` (one-shot Fargate task that exits) -- distinct from `create-service` (standing)
- Data Pipeline task-runner instances (terminate after activities; active-pipeline fee < $1/mo)
- CloudFormation itself (free; price whatever the template deploys -- often only IAM/S3)

## Watch-outs when classifying a new-passrole demo

- **Read `demo_attack.sh` to the end.** Some demos stop the created resource to halt billing
  (e.g. `sagemaker-001` runs `stop-notebook-instance` in an exit handler) -- those are effectively
  transient -> `$0`, even though the resource type is "standing".
- `setup_demo_restriction_trap` is the lab-account guard, not a billing cleanup -- ignore it.
- `create-service` (ECS/App Runner) is standing; `run-task` / one-shot invocations are transient.
- A resource launched with `--auto-terminate` (EMR) or a built-in timeout is transient/bounded.
