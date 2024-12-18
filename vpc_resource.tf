resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_subnet" "private_sub_a" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.private_sub_a_cidr
  availability_zone = var.az1
  tags = {
    Name = "${var.name}-private-sub-a"
  }
}

resource "aws_subnet" "private_sub_b" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.private_sub_b_cidr
  availability_zone = var.az2
  tags = {
    Name = "${var.name}-private-sub-b"
  }
}

resource "aws_subnet" "public_sub_a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = var.public_sub_a_cidr
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name}-public-sub-a"
  }
}

resource "aws_subnet" "public_sub_b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = var.public_sub_b_cidr
  availability_zone       = var.az2
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name}-public-sub-b"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_default_route_table" "rt1" {
  default_route_table_id = aws_vpc.my_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "${var.name}-route-table"
  }
}

resource "aws_security_group" "my_sg" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "${var.name}-sg"
  }

  ingress {
    description = "allow SSH protocol"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow HTTP protocol"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "my_launch_template" {
  name = "${var.name}-launch-template"

  image_id      = var.image_id 
  instance_type = var.instance_type

  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    subnet_id = aws_subnet.public_sub_a.id
    security_groups = [aws_security_group.my_sg.id]
  }
  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              echo "<h1>welcome to homepage</h1>" > /var/www/html/index.html
              systemctl start nginx
              systemctl restart nginx
              systemctl enable nginx
              EOF
            )
  tags = {
    Name = "${var.name}-launch-template"
  }
}
resource "aws_autoscaling_group" "my_asg" {
  desired_capacity     = 3
  max_size             = 5
  min_size             = 2
  vpc_zone_identifier  = [aws_subnet.public_sub_a.id, aws_subnet.public_sub_b.id]
  launch_template {
    id      = aws_launch_template.my_launch_template.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout  = "0"

  tag {
    key                     = "Name"
    value                   = "${var.name}-asg-instance"
    propagate_at_launch     = true
  }
  target_group_arns = [aws_lb_target_group.my_target_group.arn]
}


resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up_policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name  = aws_autoscaling_group.my_asg.name
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name                = "scale_up_alarm"
  comparison_operator       = "LessThanThreshold"  
  evaluation_periods        = "1"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "20"

  alarm_actions             = [aws_autoscaling_policy.scale_up.arn]
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.my_asg.name
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name        = "${var.name}-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
  target_type = "instance"

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
tags = {
    Name = "${var.name}-target-group"
  }
}

resource "aws_lb" "my_alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.my_sg.id]
  subnets           = [aws_subnet.public_sub_a.id, aws_subnet.public_sub_b.id]
  enable_deletion_protection = false

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code    = 200
      content_type   = "text/plain"
      message_body   = "welcome to homepage"
    }
  }
}
