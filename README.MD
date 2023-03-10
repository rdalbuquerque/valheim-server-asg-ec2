# Valheim server setup
- [Valheim server setup](#valheim-server-setup)
    - [Description](#description)
    - [Credits](#credits)
    - [Goal](#goal)
    - [Pre-requisites](#pre-requisites)
    - [Provider auth](#provider-auth)
    - [Network config](#network-config)
    - [Rendering container definition](#rendering-container-definition)
    - [Data layer](#data-layer)
    - [ECS - ASG EC2](#ecs---asg-ec2)
      - [cluster](#cluster)
      - [service and task](#service-and-task)
    - [Conclusion](#conclusion)

### Description
In this repository, you will find code to set up a Valheim game server using AWS ECS with the auto-scaling group (EC2) capacity provider. If you prefer an alternative to ASG, check out [this other repository](https://github.com/rdalbuquerque/valheim-server-fargate) that also uses AWS ECS, but with a Fargate (serverless) capacity provider. The former option (this repo) may be more performant and cost-effective, as it gives you more flexibility to adjust and fine-tune cluster configurations and use EBS external volumes, while Fargate only allows for the use of EFS. However, the latter option is much easier to set up and provides greater freedom to experiment with different CPU/memory configurations.

### Credits
This repository is inpired by [this tutorial](https://updateloop.dev/dedicated-valheim-lightsail/) and uses [this image](https://github.com/mbround18/valheim-docker) to host the server with Docker.

### Goal
The goal here is to facilitate the creation and management of the server.

### Pre-requisites
* Terraform
* AWS account

### Provider auth
The AWS provider uses the following environment variables for authentication:
* AWS:
    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * AWS_DEFAULT_REGION 

### Network config
Network configuration:
```hcl
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "valheim"
  cidr = "10.0.0.0/16"

  azs            = [local.config_default_az]
  public_subnets = ["10.0.101.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  manage_default_security_group = true
  default_security_group_ingress = [
    {
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  default_security_group_egress = [
    {
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = {
    Terraform = "true"
  }
}
```
With this `vpc` module I'm creating a public subnet and, since I need to communicate with Steam and other players, rules that allow on traffic from any protocol.
In a more meaningfull project you should create only the necessary inbound and outbound rules with specific protocols.

### Rendering container definition
```hcl
resource "random_string" "valheim_pwd" {
  length  = 6
  numeric = true
  special = false
}

locals {
  access_points = {
    "valheim-saves"   = {
      size = 5
      path = "/home/steam/.config/unity3d/IronGate/Valheim"
    }
    "valheim-server"  = {
      size = 6
      path = "/home/steam/valheim"
    }
    "valheim-backups" = {
      size = 1
      path = "/home/steam/backups"
    }
  }
  ecs_task_mount_points = jsonencode([
    for k, v in local.access_points : {
      "sourceVolume" : "${k}"
      "containerPath" : "${v.path}"
    }
  ])
  ecs_task_container_definition = templatefile("valheim-task-container-definition.tftpl", {
    aws_region   = data.aws_region.current.name
    mount_points = local.ecs_task_mount_points
    password     = random_string.valheim_pwd.result
    server_name  = var.server_name
    word_name    = var.world_name
    timezone     = var.timezone
  })
}
```
Here I create a random password that will used in the valheim server (I use random_string so I can output it in plain text, again, on a more meaningful project, protect your credentials acordingly). The locals block are the variables that will be used to render the [ECS task container definition](valheim-task-container-definition.tftpl).

### Data layer
```hcl
resource "aws_ebs_volume" "valheim" {
  for_each          = local.access_points
  availability_zone = local.config_default_az
  size              = each.value.size

  tags = {
    "Name" = each.key
  }
}
```
In this project I'm using EBS, so I create one for each mount point of my container and give each 5gb size. I am using EBS to improve performance, as it is better suited for my use case. For an alternative using Fargate and EFS please refer to [this other repository](https://github.com/rdalbuquerque/valheim-server-fargate)

### ECS - ASG EC2
#### cluster

#### service and task

### Conclusion
Overall, this project on AWS using ECS with ASG capacity provider and EBS was a valuable learning experience. By using ECS, I was able to easily deploy and manage the Valheim server, and by ASG capacity provider, I was able to deploy using spot EC2 instances, drastically lowering costs. Using EBS as the data persistency layer allowed me to store Valheim server data in a central location always available to Valheim ECS task, which helped me to avoid data loss. Overall, this project has demonstrated the power and potential of AWS for containerized applications.

OBS: This conclusion was partially generated by GPT Chat but greately summerized what this project was :)

