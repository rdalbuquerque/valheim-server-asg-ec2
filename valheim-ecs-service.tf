
resource "random_string" "valheim_pwd" {
  length  = 6
  numeric = true
  special = false
}

locals {
  access_points = {
    "valheim-saves"   = "/home/steam/.config/unity3d/IronGate/Valheim"
    "valheim-server"  = "/home/steam/valheim"
    "valheim-backups" = "/home/steam/backups"
  }
  ecs_task_mount_points = jsonencode([
    for k, v in local.access_points : {
      "sourceVolume" : "${k}"
      "containerPath" : "${v}"
    }
  ])
  ecs_task_container_definition = templatefile("valheim-task-container-definition.tftpl", {
    aws_region   = data.aws_region.current.name
    mount_points = local.ecs_task_mount_points
    server_name  = "platworld2.0"
    word_name    = "platworld2.0"
    password     = random_string.valheim_pwd.result
    timezone     = "America/Sao_paulo"
  })
}

resource "aws_ecs_service" "valheim_ec2_cluster" {
  depends_on = [
    aws_ebs_volume.valheim
  ]
  name                 = "valheim"
  cluster              = aws_ecs_cluster.valheim_ec2_cluster.name
  task_definition      = aws_ecs_task_definition.valheim.arn
  force_new_deployment = true
  desired_count        = 1
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_spot_valheim.name
    base              = 1
    weight            = 100
  }
}

data "aws_iam_role" "valheim_task" {
  name = "valheim_ecs_task"
}

resource "aws_ebs_volume" "valheim" {
  for_each          = local.access_points
  availability_zone = local.config_default_az
  size              = 5

  tags = {
    "Name" = each.key
  }
}

resource "aws_ecs_task_definition" "valheim" {
  family             = "valheim-ec2"
  cpu                = "900"
  memory             = "3500"
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

output "pwd" {
  value = random_string.valheim_pwd.result
}