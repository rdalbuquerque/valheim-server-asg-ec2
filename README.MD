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
      - [ASG](#asg)
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
#### ASG
```hcl
locals {
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=valheim-ec2-cluster >> /etc/ecs/ecs.config
docker plugin install rexray/ebs REXRAY_PREEMPT=true EBS_REGION="sa-east-1" --grant-all-permissions
sudo restart ecs
EOF
}

resource "aws_launch_template" "valheim_ec2" {
  name_prefix   = "valheim-ec2"
  image_id      = data.aws_ami.aws_optimized_ecs.image_id
  instance_type = "m6a.large"
  key_name      = "valheim-sa"
  network_interfaces {
    associate_public_ip_address = true
    subnet_id                   = module.vpc.public_subnets[0]
  }
  placement {
    availability_zone = local.config_default_az
  }
  monitoring {
    enabled = false
  }
  instance_market_options {
    market_type = "spot"
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_agent.name
  }
  user_data = base64encode(local.user_data)
}

resource "aws_autoscaling_group" "valheim" {
  name                = "valheim-ec2-cluster"
  vpc_zone_identifier = [module.vpc.public_subnets[0]]
  launch_template {
    id      = aws_launch_template.valheim_ec2.id
    version = "$Latest"
  }

  desired_capacity          = 0
  min_size                  = 0
  max_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
}
```
So here we define two resources to get our auto scaling group going: `aws_launch_template` and `aws_autoscaling_group`.\
In the launch template we are using `m6a.large` instance type. During the initial phase of the game (prior to Mistlands), using an m3.medium was sufficient. However, as we explored more of the map and reached Mistlands, the server began to experience lag and errors during saves. This ultimately resulted in the server crashing and us losing progress from the previous game day.\
The `user_data` declared in `locals` is used to install the rexray plugin in our instance, this allow us to mount EBS storage so we keep our files safe in case our spot instance gets claimed
It's also in launch template where we say we'll be running on spot instances with the option
```hcl
instance_market_options {
  market_type = "spot"
}
```
In the autoscaling group block we declare the usage of the launch template and, in this case, set the desired capacity to 0 because the management of the `asg` is made by [this discord bot](https://github.com/rdalbuquerque/odin-discord-bot)

#### cluster
```hcl
resource "aws_ecs_cluster" "valheim_ec2_cluster" {
  name = "valheim-ec2-cluster"
}

resource "aws_ecs_capacity_provider" "ec2_spot_valheim" {
  name = "ec2-spot-valheim"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.valheim.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "ec2_spot_valheim" {
  cluster_name = aws_ecs_cluster.valheim_ec2_cluster.name

  capacity_providers = [aws_ecs_capacity_provider.ec2_spot_valheim.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2_spot_valheim.name
  }
}
```
In this block we provision a Valheim EC2 cluster with a spot capacity provider and set it's default capacity to be 100 weight, this way we will always be using a spot instance. Because of that, it`s crucial that you maintain a separate storage for you game saves. 

#### service and task
```hcl
resource "aws_ecs_service" "valheim_ec2_cluster" {
  depends_on = [
    aws_ebs_volume.valheim
  ]
  name                 = "valheim"
  cluster              = aws_ecs_cluster.valheim_ec2_cluster.name
  task_definition      = aws_ecs_task_definition.valheim.arn
  force_new_deployment = true
  desired_count        = 0
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_spot_valheim.name
    base              = 1
    weight            = 100
  }
}

resource "aws_ecs_task_definition" "valheim" {
  family             = "valheim-ec2"
  cpu                = "1792"
  memory             = "7680"
  execution_role_arn = data.aws_iam_role.valheim_task.arn
  network_mode       = "host"

  container_definitions = local.ecs_task_container_definition
  dynamic "volume" {
    for_each = local.access_points
    content {
      name = volume.key
      docker_volume_configuration {
        scope  = "shared"
        driver = "rexray/ebs"
      }
    }
  }
}
```
Important notes here:
* `aws_ecs_service`: We make sure that the capacity provider strategy is using spot again in the service definition
* `aws_ecs_service`: The desired count is 0 because in my case this service is managed by [this discord bot](https://github.com/rdalbuquerque/odin-discord-bot)
* `aws_ecs_task_definition`: CPU and memory had to be increased for the last part of the game, where we had more map discovered and got to mistlands, which seems more demanding on the server. We also started to get errors while saving, ending up losing the last game day.
* `aws_ecs_task_definition`: We use dynamic block to configure a volume for each ebs storage. The same iteration keys are used in the creation of EBS storage so we can reference the name of the volume as `volume.key`. 

### Conclusion
Overall, this project on AWS using ECS with ASG capacity provider and EBS was a valuable learning experience. By using ECS, I was able to easily deploy and manage the Valheim server, and by ASG capacity provider, I was able to deploy using spot EC2 instances, drastically lowering costs. Using EBS as the data persistency layer allowed me to store Valheim server data in a central location always available to Valheim ECS task, which helped me to avoid data loss. Overall, this project has demonstrated the power and potential of AWS for containerized applications.

OBS: This conclusion was partially generated by GPT Chat but greately summerized what this project was :)

