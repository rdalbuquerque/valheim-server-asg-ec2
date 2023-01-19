resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}


data "aws_iam_policy" "ecs_agent" {
  name = "AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = data.aws_iam_policy.ecs_agent.arn
}

data "aws_iam_policy" "ebs_driver" {
  name = "AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_ebs_driver" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = data.aws_iam_policy.ebs_driver.arn
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}