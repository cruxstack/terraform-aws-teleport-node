# terraform-aws-teleport-node

Provision a small, self-healing fleet of EC2 instances that automatically join
an **existing Teleport Cloud** cluster. The nodes can run the Teleport **Node,
App, or Database** services and implements AWS EC2 best practices.

## Features

* **One-Command Deploy** – Launches an Auto Scaling Group behind the scenes;
  nodes bootstrap themselves via cloud-init and join Teleport Cloud
  automatically.
* **Always-latest Build** – Each instance queries the Teleport download
  endpoint and installs the newest stable Cloud release at boot.
* **Spot-friendly** – Supports mixed-instance/spot policies for cost savings.
* **Integrated Observability** – System, cloud-init and Teleport logs are
  streamed to a dedicated CloudWatch Log Group; optional SSM session
  transcripts to S3.
* **Database Service Ready** – IAM & RDS/Redshift permissions wired in when
  `tp_config.db_service.enabled = true`, enabling discovery and IAM auth.
* **Hygienic Networking & IAM** – No public IPs, IMDSv2 enforced, least-priv
  policies, single inbound rule limited to the SG itself for Teleport gossip.

## Usage

```hcl
module "teleport_nodes" {
  source  = "github.com/cruxstack/terraform-aws-teleport-node"
  version = "x.x.x"

  tp_domain = "acme.teleport.sh"
  tp_join_config = {
    token_name = "iam-role"
  }

  vpc_id              = "vpc-1234567890abcdef"
  vpc_subnet_ids      = ["subnet-1234abcd", "subnet-5678efgh"]
}
```

## Inputs
In addition to the variables documented below, this module includes several
other optional variables (e.g., `name`, `tags`, etc.) provided by the
`cloudposse/label/null` module. Please refer to its [documentation](https://registry.terraform.io/modules/cloudposse/label/null/latest)
for more details on these variables.

| Name                                     | Description                                                                             |          Type         |         Default        | Required |
| ---------------------------------------- | --------------------------------------------------------------------------------------- | :-------------------: | :--------------------: | :------: |
| `tp_domain`                              | Teleport Cloud cluster FQDN (e.g. `example.teleport.sh`).                               |        `string`       |            —           |  **yes** |
| `tp_join_config`                         | Join token config.<br>`token_name` (required) and optional `method` (`iam` \| `token`). |    `object({...})`    |            —           |  **yes** |
| `tp_edition`                             | Teleport edition (`cloud`, `ent`, …).                                                   |        `string`       |        `"cloud"`       |    no    |
| `tp_config`                              | Extra Teleport service configuration (enable DB/App/SSH, label rules, etc.).            |    `object({...})`    |          `{}`          |    no    |
| `instance_capacity`                      | ASG desired/min/max.                                                                    |    `object({...})`    | `{ min = 1, max = 3 }` |    no    |
| `instance_types`                         | List of allowed instance types & weights.                                               | `list(object({...}))` |   see `variables.tf`   |    no    |
| `instance_key_name`                      | Existing EC2 key-pair name (ssh access).                                                |        `string`       |          `""`          |    no    |
| `instance_spot`                          | Spot settings (`enabled`, `allocation_strategy`).                                       |    `object({...})`    |  `{ enabled = true }`  |    no    |
| `logs_bucket_name`                       | S3 bucket for generic logs (unused by SSM).                                             |        `string`       |          `""`          |    no    |
| `ssm_sessions`                           | Toggle SSM logging and target bucket.                                                   |    `object({...})`    |  `{ enabled = false }` |    no    |
| `vpc_id`                                 | Target VPC ID.                                                                          |        `string`       |            —           |  **yes** |
| `vpc_subnet_ids`                         | Subnet IDs for the ASG.                                                                 |     `list(string)`    |          `[]`          |  **yes** |
| `vpc_security_group_ids`                 | Extra SGs to attach.                                                                    |     `list(string)`    |          `[]`          |    no    |
| `experimental_mode`                      | Shorter CW log retention & zero-health refresh for dev.                                 |         `bool`        |         `false`        |    no    |

## Outputs

| Name                  | Description                                     |
| --------------------- | ----------------------------------------------- |
| `teleport_version`    | The Teleport version installed on the nodes.    |
| `teleport_config`     | Fully-rendered Teleport YAML that was injected. |
| `security_group_id`   | ID of the generated node SG.                    |
| `security_group_name` | Name of the generated node SG.                  |

