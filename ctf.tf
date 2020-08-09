variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

variable "admin_cidr" {
  type = string
}

variable "github_auth" {
  type = string
}

variable "flag" {
  type = string
}

provider "aws" {
  region     = "eu-north-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

resource "aws_vpc" "ctf_vpc" {
  cidr_block = "10.10.1.0/24"
}

resource "aws_subnet" "ctf_subnet" {
  vpc_id                  = aws_vpc.ctf_vpc.id
  cidr_block              = aws_vpc.ctf_vpc.cidr_block
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "ctf_igw" {
  vpc_id = aws_vpc.ctf_vpc.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.ctf_subnet.id
  route_table_id = aws_route_table.ctf_rt.id
}

resource "aws_route_table" "ctf_rt" {
  vpc_id = aws_vpc.ctf_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ctf_igw.id
  }

}

resource "aws_security_group" "ctf_web_sg" {
  name        = "ctf_web_sg"
  description = "Allow web traffic on port 80 and ssh on 22"
  vpc_id      = aws_vpc.ctf_vpc.id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "image_proxy_eip" {
  instance = aws_instance.web.id
  vpc      = true
}

resource "aws_instance" "web" {
  ami                    = "ami-04697c9bb5d6135a2"
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.ctf_subnet.id
  key_name               = "ctf-key"
  vpc_security_group_ids = [aws_security_group.ctf_web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.flag_reader.name

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("./.terraform/ctf-key.pem")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y git",
      "git clone https://${var.github_auth}@github.com/movitz-s/image-proxy-ctf",
      "cd image-proxy-ctf",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash",
      ". ~/.nvm/nvm.sh",
      "nvm install node",
      "npm install",
      "setsid nohup node index.js &"
    ]
  }

}

resource "aws_s3_bucket" "b" {
  bucket = "flag-bucket-soniccdn"
}

resource "aws_iam_role_policy" "flag_reader_policy" {
  name = "flag_reader_policy"
  role = aws_iam_role.flag_s3_reader_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "s3:List*"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "s3:Get*",
              "s3:List*"
          ],
        "Resource": "${aws_s3_bucket.b.arn}/*"
      }
  ]
}
EOF
}

resource "aws_s3_bucket_object" "flag" {
  key     = "flag"
  bucket  = aws_s3_bucket.b.bucket
  content = var.flag
}

resource "aws_iam_instance_profile" "flag_reader" {
  name = "flag_reader"
  role = aws_iam_role.flag_s3_reader_role.name
}

resource "aws_iam_role" "flag_s3_reader_role" {
  name                 = "flag_s3_reader_role"
  max_session_duration = 43200
  assume_role_policy   = <<EOF
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
