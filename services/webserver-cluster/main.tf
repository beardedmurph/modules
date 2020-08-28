variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

variable "ssh_port" {
  description = "The port the server will use for SSH requests"
  type        = number
  default     = 22
}

data "aws_availability_zones" "all" {}

resource "aws_launch_configuration" "testInstance" {
  image_id		 = "ami-0a13d44dccf1f5cf6"
  instance_type		 = var.instance_type
  key_name		 = "terraformuser"
  security_groups	 = [aws_security_group.instance.id]

  user_data = <<-EOF
	      #!/bin/bash
	      wget https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-x86_64
        mv busybox-x86_64 busybox
        chmod +x busybox
	      instance_id="${data.terraform_remote_state.instance.outputs.ip}"
	      echo "Hello, World. This instance is $instance_id" >> index.html
	      nohup ./busybox httpd -f -p "${var.server_port}" &
	      EOF

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.testInstance.id
  availability_zones   = data.aws_availability_zones.all.names

  min_size = var.min_size
  max_size = var.max_size

  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}"
    propagate_at_launch = true
  }
}

resource "aws_elb" "example" {
  name               = "${var.cluster_name}-elb"
  security_groups    = [aws_security_group.elb.id] 
  availability_zones = data.aws_availability_zones.all.names

  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  
  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    # Replace this with your bucket name!
    bucket = "terraform-up-and-running-state20200826a"
    key    = "stage/data-stores/mysql/terraform.tfstate"
    region = "eu-west-2"
  }
}

resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-instance-sg"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb" {
  name = "${var.cluster_name}-elb"
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

