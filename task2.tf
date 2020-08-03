provider "aws" {
  region = "ap-south-1"
  profile = "aditi"
}

resource "aws_vpc" "first_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myvpc"
  }
}


resource "aws_internet_gateway" "first_gw" {
  vpc_id = aws_vpc.first_vpc.id

  tags = {
    Name = "my-internetGW"
  }
  depends_on = [
      aws_vpc.first_vpc,
      ]
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.first_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.first_gw.id
  }

  tags = {
    Name = "route-table for inbound traffic to vpc"
  }
  depends_on = [
      aws_internet_gateway.first_gw,
      ]
}

resource "aws_subnet" "first_subnet" {
  vpc_id     = aws_vpc.first_vpc.id
  availability_zone = "ap-south-1a"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "mysubnet"
  }
  depends_on = [
      aws_vpc.first_vpc,
      ]
}

resource "aws_route_table_association" "rt_association" {
  subnet_id      = aws_subnet.first_subnet.id
  route_table_id = aws_route_table.route_table.id

  depends_on = [
      aws_subnet.first_subnet,
      aws_route_table.route_table
      ]
}


resource "aws_security_group" "first_sg" {
  name        = "security_grouup"
  description = "Allow TLS inbound traffic"
  vpc_id      = "${aws_vpc.first_vpc.id}"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "firewall"
  }
  depends_on = [
      aws_route_table_association.rt_association
      ]
}

resource "tls_private_key" "pkey" {
  algorithm   = "RSA"
  rsa_bits = 4096
  
  depends_on = [
      aws_security_group.first_sg
      ]
}

resource "local_file" "private-key" {
    content     = tls_private_key.pkey.private_key_pem
    filename    = "mykey.pem"
}

resource "aws_key_pair" "mykey" {
  key_name   = "mykey111"
  public_key = tls_private_key.pkey.public_key_openssh

  depends_on = [
      tls_private_key.pkey
      ]
}

resource "aws_instance" "instance_ec2" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name 	=  aws_key_pair.mykey.key_name
  vpc_security_group_ids = ["${aws_security_group.first_sg.id}"]
  subnet_id = aws_subnet.first_subnet.id

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install httpd php git amazon-efs-utils -y",
      "sudo service httpd start",
      "sudo chkconfig httpd on",
    ]
  }
  tags = {
    Name = "first-os"
  }
  
  depends_on = [
    aws_key_pair.mykey
  ]
}

resource "aws_efs_file_system" "efs_volume" {
  creation_token = "my-efs"
  tags = {
    Name = "efs-volume"
  }
  depends_on = [
    aws_instance.instance_ec2
  ]
}

resource "aws_efs_mount_target" "efs_target" {
  file_system_id = aws_efs_file_system.efs_volume.id
  subnet_id      = aws_subnet.first_subnet.id
  security_groups = ["${aws_security_group.first_sg.id}"]
  
  depends_on = [
   aws_efs_file_system.efs_volume 
  ]
}

resource "null_resource" "mount_efs_volume"  {

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo echo ${aws_efs_file_system.efs_volume.id}:/ /var/www/html efs dataults,_netdev 0 0 >>sudo /etc/fstab",
      "sudo mount -t efs ${aws_efs_file_system.efs_volume.id}:/ /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/aditigarg4/task2file.git /var/www/html/"
      
    ]
  }
  depends_on = [
      aws_instance.instance_ec2,  
      aws_efs_file_system.efs_volume , 
      aws_efs_mount_target.efs_target,
  ]
}

resource "aws_s3_bucket" "first_bucket" {
  bucket = "mybucketforimage"
  acl    = "public-read"

  tags = {
    Name  = "My-s3-bucket"
  }

  depends_on = [
      null_resource.mount_efs_volume
  ]
}

resource "aws_s3_bucket_object" "image" {

  bucket = aws_s3_bucket.first_bucket.bucket
  key    = "task2.jpeg"
  source = "C:/Users/user/Desktop/task2.jpeg"
  acl 	 = "public-read"

  depends_on = [
    aws_s3_bucket.first_bucket,
  ]
}


locals {
  s3_origin_id = "s3-bucket-origin-id"
}

resource "aws_cloudfront_distribution" "s3_distribution" {


depends_on = [
    aws_s3_bucket_object.image,
  ]

  origin {
    domain_name = aws_s3_bucket.first_bucket.bucket_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.pkey.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  } 

 
  provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image.key}' height='200' width='200'>\">> /var/www/html/index.php","END",
    ]
  }
}
output "public_ip" {
    value = "${aws_instance.instance_ec2.public_ip}"
}

resource "null_resource" "openwebsite" {


depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

 provisioner "local-exec" {
    command = "start chrome http://${aws_instance.instance_ec2.public_ip}/"
    
  }  
}



