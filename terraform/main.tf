provider "aws" {
  region = "us-east-1"
}

variable "azs" {
  type    = set(string)
  default = ["us-east-1a", "us-east-1b"]
}

resource "aws_vpc" "main" {
  cidr_block = "10.100.0.0/16"

  tags = {
    Name = "my-app-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.100.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "public_a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "public_b"
  }
}


resource "aws_internet_gateway" "main-igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_security_group" "docker_project_lb_sg" {
  name        = "docker-nginx-project-lb-sg"
  description = "allow incoming HTTP traffic only"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "docker_project_lb" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups = ["${aws_security_group.docker_project_lb_sg.id}"]
  subnets         = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]
  tags = {
    Environment = "dev"
  }
}


resource "aws_lb_target_group" "docker_project_lb_tg" {
  name     = "docker-project-lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    protocol = "HTTP"
    port = 80
  }
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.docker_project_lb.arn
  port              = "80"
  protocol          = "HTTP"


   default_action {
    target_group_arn = aws_lb_target_group.docker_project_lb_tg.arn
    type             = "forward"
  }
}

# creating launch configuration
resource "aws_launch_configuration" "project" {
  image_id        = "ami-007855ac798b5175e"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.docker_project_ec2.id}"]
  user_data       = <<EOF
#!/bin/bash
export PATH=/usr/local/bin:$PATH

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update

# install docker community edition
apt-cache policy docker-ce
apt-get install -y docker-ce

mkdir deployment_files

cd deployment_files

echo "AHMed@786" | docker login --username zubairsource --password-stdin

echo '
version: "3.8"
services:
  nginx:
    restart: always
    container_name: nginx
    image: zubairsource/social-app-nginx:latest
    ports:
      - '80:80'
    depends_on:
      - client
      - api
    networks:
      - socialapp-network
  api:
    container_name: api
    image: zubairsource/social-app-backend:latest
    environment:
      - MONGODB_URL=mongo_url
      - JWT_SECRET=sample
      - PORT=5000
    networks:
      - socialapp-network
    restart: always
  client:
    container_name: client
    image: zubairsource/social-app-frontend:latest
    networks:
      - socialapp-network
    restart: always

networks:
  socialapp-network:
' >docker-compose.yml

docker compose -p " Devops-Project02" up -d

EOF
  lifecycle {
    create_before_destroy = true
  }
}


# creating autoscaling group
resource "aws_autoscaling_group" "docker_project_asg" {
  name                 = "docker-project-autoscaling-group"
  launch_configuration = aws_launch_configuration.project.id
  vpc_zone_identifier  = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]

  target_group_arns = [ "${aws_lb_target_group.docker_project_lb_tg.arn}" ]

  desired_capacity = 2
  max_size         = 5
  min_size         = 1

  health_check_type = "EC2"
  tag {
    key                 = "Name"
    value               = "asg"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "docker_project_ec2" {
  name        = "docker-nginx-project-ec2"
  description = "allow incoming HTTP traffic only"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "url" {
  value = "http://${aws_lb.docker_project_lb.dns_name}/"
}