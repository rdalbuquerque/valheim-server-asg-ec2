resource "aws_ecs_cluster" "valheim_ec2_cluster" {
  name = "valheim-ec2-cluster"
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

resource "aws_ecs_capacity_provider" "ec2_spot_valheim" {
  name = "ec2-spot-valheim"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.valheim.arn
  }
}