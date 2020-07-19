provider "aws" {
	region = "ap-south-1"
	profile = "jg"
}

resource "aws_efs_file_system" "new_efs" {
  creation_token = "jg_new_efs"

  tags = {
    Name = "Jayesh"
  }
}
data "aws_vpc" "default" {
  default="true"
}
data "aws_subnet" "subnets" {
  vpc_id = data.aws_vpc.default.id
  availability_zone="ap-south-1a"
}
resource "aws_efs_mount_target" "subnet1" {
  depends_on = [aws_efs_file_system.new_efs]
  file_system_id = aws_efs_file_system.new_efs.id
  subnet_id      = data.aws_subnet.subnets.id
}

// To Create Security Group

resource "aws_security_group" "allow_http" {
  depends_on = [aws_efs_mount_target.subnet1]
  name        = "allow_http_ssh"
  description = "Allow http & ssh inbound traffic"

  ingress{
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress{
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress{
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
 }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

//To launch Instance

resource "aws_instance" "os1" {

depends_on = [
    aws_security_group.allow_http,
  ]

  ami           = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  availability_zone="ap-south-1a"
  key_name = "mykey"
  security_groups = [aws_security_group.allow_http.name]
  tags = {
    Name = "os1_from_Terraform"
  }

   //To connect to instance
   connection {
       type     = "ssh"
       user     = "ec2-user"
       private_key = file("mykey.pem")
       host     = aws_instance.os1.public_ip
     }
   //To run commands in instance
   provisioner "remote-exec" {
     inline = [
         "sudo yum install httpd php git amazon-efs-utils -y",
         "sudo mount -t efs ${aws_efs_file_system.new_efs.id}:/ /var/www/html",
         "echo '${aws_efs_file_system.new_efs.id}:/ /var/www/html efs _netdev 0 0' | sudo tee -a sudo tee -a /etc/fstab",
       ]
     }
} 

//To print public ip address of instance
output "publicip"{
value = aws_instance.os1.public_ip
}

resource "null_resource" "git_upload"{
depends_on = [
    aws_instance.os1,
             ]

 connection {
       type     = "ssh"
       user     = "ec2-user"
       private_key = file("mykey.pem")
       host     = aws_instance.os1.public_ip
     }

   //To run commands in instance
   provisioner "remote-exec" {
     inline = [
         "sudo rm -rf /var/www/html/*",
         "sudo git clone https://github.com/jayesh4433/myrepo.git /var/www/html/",
         "sudo systemctl start httpd",
         "sudo systemctl enable httpd",
    
            ]
                          }
}


//To create S3 Bucket
resource "aws_s3_bucket" "bucket1" {
depends_on = [
    aws_instance.os1,
  ]
  bucket = "jgmy-newbucket1"
  acl    = "public-read"

  tags = {
    Name        = "my bucket 1"
    Environment = "Dev"
  }
}

//To upload object in bucket
resource "aws_s3_bucket_object" "img1" {
depends_on = [ 
aws_s3_bucket.bucket1,
]
  bucket = aws_s3_bucket.bucket1.id
  key    = "tera_aws.png"
  source = "tera_aws.png"
  acl = "public-read"
}

//To create cloudFront of above object
resource "aws_cloudfront_distribution" "s3_img_distribution" {
depends_on = [ 
aws_s3_bucket_object.img1,
]
  origin {
    domain_name = aws_s3_bucket.bucket1.bucket_regional_domain_name
    origin_id   = "my-s3-origin-img"
	}
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Distribution for IMG1"
  default_root_object = "tera_aws.png"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "my-s3-origin-img"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    viewer_protocol_policy = "redirect-to-https"
  }
  price_class = "PriceClass_All"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "img_distribution_domain_name"{
value =  aws_cloudfront_distribution.s3_img_distribution.domain_name
}

resource "null_resource" "img_update"{
depends_on = [
    aws_cloudfront_distribution.s3_img_distribution,
             ]

//To connect to instance
   connection {
       type     = "ssh"
       user     = "ec2-user"
       private_key = file("mykey.pem")
       host     = aws_instance.os1.public_ip
               }

//To get img from aws distribution and append at the end of alredy created index.php file
provisioner "remote-exec" {
    inline = [
    "echo '<img src='https://${aws_cloudfront_distribution.s3_img_distribution.domain_name}' height = '450px' weidth = '450px'>' | sudo tee -a /var/www/html/index.php",
            ]
                          }
}

//To run website

resource "null_resource" "runwebpage"  {
depends_on = [
    null_resource.img_update,
  ]

	provisioner "local-exec" {
	    command = "chrome ${aws_instance.os1.public_ip}"
  	}
}

//To launch Instance

resource "aws_instance" "os2" {

depends_on = [
    null_resource.git_upload,
  ]

  ami           = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  availability_zone="ap-south-1a"
  key_name = "mykey"
  security_groups = [aws_security_group.allow_http.name]
  tags = {
    Name = "os2_from_Terraform"
  }

   //To connect to instance
   connection {
       type     = "ssh"
       user     = "ec2-user"
       private_key = file("mykey.pem")
       host     = aws_instance.os2.public_ip
     }
   //To run commands in instance
   provisioner "remote-exec" {
     inline = [
         "sudo yum install httpd php git amazon-efs-utils -y",
         "sudo mount -t efs ${aws_efs_file_system.new_efs.id}:/ /var/www/html",
         "echo '${aws_efs_file_system.new_efs.id}:/ /var/www/html efs _netdev 0 0' | sudo tee -a sudo tee -a /etc/fstab",
         "sudo systemctl start httpd",
         "sudo systemctl enable httpd",
       ]
     }
} 

//To print public ip address of instance
output "publicip2"{
value = aws_instance.os2.public_ip
}

//To run website

resource "null_resource" "runwebpage2"  {
depends_on = [
    null_resource.img_update,
  ]

	provisioner "local-exec" {
	    command = "chrome ${aws_instance.os2.public_ip}"
  	}
}