
locals {
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=valheim-ec2-cluster >> /etc/ecs/ecs.config
docker plugin install rexray/ebs REXRAY_PREEMPT=true EBS_REGION="sa-east-1" --grant-all-permissions
sudo restart ecs
EOF
}

data "aws_ami" "aws_optimized_ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami*amazon-ecs-optimized"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"] # AWS
}

resource "aws_launch_template" "valheim_ec2" {
  name_prefix   = "valheim-ec2"
  image_id      = data.aws_ami.aws_optimized_ecs.image_id
  instance_type = "m3.medium"
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