/*====
The VPC
======*/

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

/*====
Subnets
======*/
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  }
}

/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]

  tags = {
    Name        = "${var.environment}-nat"
    Environment = var.environment
  }
}

/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnets_cidr
  availability_zone       = var.availability_zones
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-public-subnet"
    Environment = var.environment
  }
}

/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.private_subnets_cidr
  availability_zone       = var.availability_zones
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-private-subnet"
    Environment = var.environment
  }
}

/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = var.environment
  }
}

/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = var.environment
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

/* Route table associations */
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

/*====
VPC's Default Security Group
======*/
resource "aws_security_group" "default" {
  name        = "${var.environment}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }

  tags = {
    Environment = var.environment
  }
}

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


/*====
RDS
======*/

/* subnet used by rds */
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "${var.environment}-rds-subnet-group"
  description = "RDS subnet group"
  subnet_ids  = [aws_subnet.private_subnet.id]
  tags = {
    Environment = var.environment
  }
}

/* Security Group for resources that want to access the Database */
resource "aws_security_group" "db_access_sg" {
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.environment}-db-access-sg"
  description = "Allow access to RDS"

  tags = {
    Name        = "${var.environment}-db-access-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}-rds-sg"
  description = "${var.environment} Security Group"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-rds-sg"
    Environment = var.environment
  }

  // allows traffic from the SG itself
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  //allow traffic for TCP 5432
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db_access_sg.id]
  }

  // outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds" {
  identifier             = "${var.environment}-database"
  allocated_storage      = var.allocated_storage
  engine                 = "postgres"
  engine_version         = "9.6.6"
  instance_class         = var.instance_class
  multi_az               = var.multi_az
  name                   = var.database_name
  username               = var.database_username
  password               = var.database_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  #snapshot_identifier    = "rds-${var.environment}-snapshot"
  tags = {
    Environment = var.environment
  }
}





# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++





/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "wiki" {
  name = "wiki"

  tags = {
    Environment = var.environment
    Application = "wiki"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "wiki_app" {
  name = var.repository_name
}

/*====
ECS cluster
======*/
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

/*====
ECS task definitions
======*/

/* the task definition for the web service */
data "template_file" "web_task" {
  template = file("${path.module}/tasks/web_task_definition.json")

  vars = {
    image           = aws_ecr_repository.wiki_app.repository_url
    secret_key_base = var.secret_key_base
    database_url    = "postgresql://${var.database_username}:${var.database_password}@${aws_db_instance.rds.address}:5432/${var.database_name}?encoding=utf8&pool=40"
    log_group       = aws_cloudwatch_log_group.wiki.name
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.environment}_web"
  container_definitions    = data.template_file.web_task.rendered
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn
}

/* the task definition for the db migration */
data "template_file" "db_migrate_task" {
  template = file("${path.module}/tasks/db_migrate_task_definition.json")

  vars = {
    image           = aws_ecr_repository.wiki_app.repository_url
    secret_key_base = var.secret_key_base
    database_url    = "postgresql://${var.database_username}:${var.database_password}@${aws_db_instance.rds.address}:5432/${var.database_name}?encoding=utf8&pool=40"
    log_group       = "wiki"
  }
}

resource "aws_ecs_task_definition" "db_migrate" {
  family                   = "${var.environment}_db_migrate"
  container_definitions    = data.template_file.db_migrate_task.rendered
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn
}

/*====
App Load Balancer
======*/
resource "random_id" "target_group_sufix" {
  byte_length = 2
}

resource "aws_alb_target_group" "alb_target_group" {
  name        = "${var.environment}-alb-target-group-${random_id.target_group_sufix.hex}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "web_inbound_sg" {
  name        = "${var.environment}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-web-inbound-sg"
  }
}

resource "aws_alb" "alb_wiki" {
  name            = "${var.environment}-alb-wiki"
  subnets         = ["${aws_subnet.public_subnet.id}"]
  security_groups = [aws_security_group.default.id,aws_security_group.db_access_sg.id,aws_security_group.web_inbound_sg.id]

  tags = {
    Name        = "${var.environment}-alb-wiki"
    Environment = var.environment
  }
}

resource "aws_alb_listener" "wiki" {
  load_balancer_arn = aws_alb.alb_wiki.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.alb_target_group]

  default_action {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    type             = "forward"
  }
}

/*
* IAM service role
*/
data "aws_iam_policy_document" "ecs_service_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_role" {
  name               = "ecs_role"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_role.json
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress",
    ]
  }
}

/* ecs service scheduler role */
resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name = "ecs_service_role_policy"

  #policy = "${file("${path.module}/policies/ecs-service-role.json")}"
  policy = data.aws_iam_policy_document.ecs_service_policy.json
  role   = aws_iam_role.ecs_role.id
}

/* role that the Amazon ECS container agent and the Docker daemon can assume */
resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = file("${path.module}/policies/ecs-task-execution-role.json")
}

resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  name   = "ecs_execution_role_policy"
  policy = file("${path.module}/policies/ecs-execution-role-policy.json")
  role   = aws_iam_role.ecs_execution_role.id
}

/*====
ECS service
======*/

/* Security Group for ECS */
resource "aws_security_group" "ecs_service" {
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.environment}-ecs-service-sg"
  description = "Allow egress from container"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-ecs-service-sg"
    Environment = var.environment
  }
}

/* Simply specify the family to find the latest ACTIVE revision in that family */
data "aws_ecs_task_definition" "web" {
  task_definition = aws_ecs_task_definition.web.family
  depends_on      = [aws_ecs_task_definition.web]
}

resource "aws_ecs_service" "web" {
  name = "${var.environment}-web"
  task_definition = "${aws_ecs_task_definition.web.family}:${max(
    aws_ecs_task_definition.web.revision,
    data.aws_ecs_task_definition.web.revision,
  )}"
  desired_count = 2
  launch_type   = "FARGATE"
  cluster       = aws_ecs_cluster.cluster.id
  depends_on    = [aws_iam_role_policy.ecs_service_role_policy]

  network_configuration {
    security_groups = [aws_security_group.default.id,aws_security_group.db_access_sg.id, aws_security_group.ecs_service.id]
    subnets         = ["${aws_subnet.private_subnet.id}"]
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    container_name   = "web"
    container_port   = "80"
  }
}

/*====
Auto Scaling for ECS
======*/

resource "aws_iam_role" "ecs_autoscale_role" {
  name               = "${var.environment}_ecs_autoscale_role"
  assume_role_policy = file("${path.module}/policies/ecs-autoscale-role.json")
}

resource "aws_iam_role_policy" "ecs_autoscale_role_policy" {
  name   = "ecs_autoscale_role_policy"
  policy = file("${path.module}/policies/ecs-autoscale-role-policy.json")
  role   = aws_iam_role.ecs_autoscale_role.id
}

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = aws_iam_role.ecs_autoscale_role.arn
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "up" {
  name               = "${var.environment}_scale_up"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

resource "aws_appautoscaling_policy" "down" {
  name               = "${var.environment}_scale_down"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

/* metric used for auto scale */
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.environment}_wiki_web_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.web.name
  }

  alarm_actions = [aws_appautoscaling_policy.up.arn]
  ok_actions    = [aws_appautoscaling_policy.down.arn]
}

