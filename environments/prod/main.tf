terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      //configuration_aliases = [ aws.prod ]
    }
  }
}


# Create admin user for cleanup scripts
resource "aws_iam_user" "admin_user_for_cleanup" {
  name = "pl-admin-user-for-cleanup-scripts"
}

# Access key for the admin cleanup user
resource "aws_iam_access_key" "admin_user_for_cleanup" {
  user = aws_iam_user.admin_user_for_cleanup.name
}

# Attach AdministratorAccess policy to cleanup user
resource "aws_iam_user_policy_attachment" "admin_user_for_cleanup_admin_access" {
  user       = aws_iam_user.admin_user_for_cleanup.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}



# data "aws_ami" "bastion" {
#   most_recent = true

#   filter {
#     name   = "name"
#     values = ["amzn2-ami-hvm-*-x86_64-ebs"]
#   }

#   owners = ["amazon"] 
# }


# resource "aws_security_group" "intra-sg-access" {
#   name        = "intra-sg-access"
#   description = "intra-sg-access"
#   vpc_id      = var.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 65535
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "intra-sg-access"
#   }
# }

# resource "aws_security_group_rule" "intra-sg-access-ingress" {
#   security_group_id = aws_security_group.intra-sg-access.id

#   type        = "ingress"
#   from_port   = 0
#   to_port     = 65535
#   protocol    = "tcp"
#   self        = true
# }

# output "intra-sg-access-id" {
#   value = aws_security_group.intra-sg-access.id
# }

# resource "aws_instance" "bastion" {
#   ami           = data.aws_ami.bastion.id
#   instance_type = "t3a.nano"
#   subnet_id = var.subnet1_id
#   iam_instance_profile = aws_iam_instance_profile.bastion.name
#   associate_public_ip_address = true
#   vpc_security_group_ids = [ aws_security_group.intra-sg-access.id ]

#   tags = {
#     Name = "bastion"
#   }
# }

# resource "aws_iam_role" "bastion" {
#   name                = "reyna"
#   assume_role_policy  = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ssmcore" {
#   role       = aws_iam_role.bastion.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# }  


# resource "aws_iam_instance_profile" "bastion" {
#   name = "bastion"
#   role = aws_iam_role.bastion.name
# }


# // associate the administratoraccess policy with the bastion role

# resource "aws_iam_role_policy_attachment" "bastion" {
#   role       = aws_iam_role.bastion.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }


# resource "aws_instance" "jump" {
#   ami           = data.aws_ami.bastion.id
#   instance_type = "t3a.nano"
#   subnet_id = var.subnet1_id
#   iam_instance_profile = aws_iam_instance_profile.jump.name
#   associate_public_ip_address = true
#   vpc_security_group_ids = [ aws_security_group.intra-sg-access.id ]

#   tags = {
#     Name = "jump"
#   }
# }

# resource "aws_iam_role" "jump" {
#   name                = "jump"
#   assume_role_policy  = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ssmcore2" {
#   role       = aws_iam_role.jump.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# }  

# resource "aws_iam_policy" "jump" {
#   name        = "jump"
#   description = "Allows ssm access to ec2 instances"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ssm:StartSession",
#           "ssm:DescribeSessions",
#           "ssm:SendCommand",
#           "ssm:TerminateSession",
#           "ssm:DescribeInstanceProperties",
#         ],
#         Resource = "${aws_instance.bastion.arn}"
#         }
#     ]
#     })
# }

# resource "aws_iam_role_policy_attachment" "jump" {
#   role       = aws_iam_role.jump.name
#   policy_arn = aws_iam_policy.jump.arn
# }








# resource "aws_iam_instance_profile" "jump" {
#   name = "jump"
#   role = aws_iam_role.jump.name
# }


# // create a role that allows anyone in the account to assume it. call it ec2_creator_role

# resource "aws_iam_role" "ec2_creator_role" {
#   name = "ec2_creator_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // create a policy that allows this role to create ec2 instances

# resource "aws_iam_policy" "ec2_creator_policy" {
#   name        = "ec2_creator_policy"
#   description = "Allows ec2 creation"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ec2:RunInstances",
#           "iam:PassRole"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# // create a role that is called the ec2_helpdesk rolel that allows ssm access to ec2 instances

# resource "aws_iam_role" "ec2_helpdesk_role" {
#   name = "ec2_helpdesk_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // create a policy that provides ssm access to ec2 instances

# resource "aws_iam_policy" "ec2_helpdesk_policy" {
#   name        = "ec2_helpdesk_policy"
#   description = "Allows ssm access to ec2 instances"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ssm:StartSession",
#           "ssm:DescribeSessions",
#           "ssm:SendCommand",
#           "ssm:TerminateSession",
#           "ssm:DescribeInstanceProperties",
#         ],
#         Resource = "*"
#         }
#     ]
#     })
# }

# // attach the policy to the role

# resource "aws_iam_role_policy_attachment" "ec2_helpdesk_policy" {
#   role       = aws_iam_role.ec2_helpdesk_role.name
#   policy_arn = aws_iam_policy.ec2_helpdesk_policy.arn
# }



# // create a role that allows anyone in the account to assume it. call it assumer_role

# resource "aws_iam_role" "jumper_role" {
#   name = "jumper_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }


# resource "aws_iam_policy" "jumper_policy" {
#   name        = "jumper_policy"
#   description = "Allows role assumption"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ssm:StartSession",
#           "ssm:DescribeSessions",
#           "ssm:SendCommand",
#           "ssm:TerminateSession",
#           "ssm:DescribeInstanceProperties",
#         ],
#         Resource = "${aws_instance.jump.arn}"     
#         }
#     ]
#   })
# }

# // attach the policy to the role

# resource "aws_iam_role_policy_attachment" "jumper_policy" {
#   role       = aws_iam_role.jumper_role.name
#   policy_arn = aws_iam_policy.jumper_policy.arn
# }


# // create a user called ctf that has the sts assume role permission

# resource "aws_iam_user" "ctf" {
#   name = "ctf"
# }

# resource "aws_iam_user_policy" "ctf" {
#   name = "ctf"
#   user = aws_iam_user.ctf.name

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#             "ssm:StartSession",
#         ],  
#         Resource = "${aws_instance.jump.arn}"
#       },
#       {
#           Effect = "Allow",
#           Action = [
#               "sts:AssumeRole",
#           ],  
#           Resource = aws_iam_role.prod_simple_privesc_role.arn
#       }
#     ]
#   })
# }


# // create an access key for this user

# resource "aws_iam_access_key" "ctf" {
#   user = aws_iam_user.ctf.name
# }

# output "ctf_user_output_access_key_id" {
#   value     = aws_iam_access_key.ctf.id
# }

# output "ctf_user_output_secret_access_key" {
#   value     = aws_iam_access_key.ctf.secret
# }


# resource "aws_iam_user" "admin" {
#   name = "admin"
# }

# // attach the administratoraccess policy to admin user

# resource "aws_iam_user_policy_attachment" "admin" {
#   user       = aws_iam_user.admin.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }




# // create a role that trusts the EKS OIDC provider
# resource "aws_iam_role" "eks-prod" {
#   name = "eks-prod1"
#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Action": "sts:AssumeRoleWithWebIdentity",
#       "Principal": {
#         "Federated": "arn:aws:iam::${var.dev_account_id}:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E2E8B1B6B1AE8D"
#       },
#       "Condition": {
#         "StringEquals": {
#           "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E2E8B1B6B1AE8D:sub": "system:serviceaccount:default:default"
#         }
#       },
#       "Effect": "Allow",
#       "Sid": ""
#     }
#   ]
# }
# EOF
# }

# // create a policy to allow the EKS OIDC role to read the flag
# resource "aws_iam_policy" "eks-prod" {
#   name = "eks-prod"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid = "AllowAssumeRole",
#         Effect = "Allow",
#         Action = [
#           "sts:AssumeRole",
#           "ec2:*",
#           "lambda:*",
#           "cloudformation:*",
#           "ssm:*",
#         ],
#         Resource = [
#           "*"
#         ]
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks-prod" {
#   role = aws_iam_role.eks-prod.name
#   policy_arn = aws_iam_policy.eks-prod.arn
# }


# ##############################################
# # Users with direct AdministratorAccess policy
# ##############################################      


# resource "aws_iam_user" "Jim-Admin" {
#   name = "pl-Jim-Admin"
# }

# resource "aws_iam_user_policy_attachment" "AdministratorAccess-Jim" {
#   user       = aws_iam_user.Jim-Admin.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# resource "aws_iam_user" "Jack-Admin" {
#   name = "pl-Jack-Admin"
# }

# resource "aws_iam_user_policy_attachment" "AdministratorAccess-Jack" {
#   user       = aws_iam_user.Jack-Admin.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# resource "aws_iam_user" "John-Admin" {
#   name = "pl-John-Admin"
# }

# resource "aws_iam_user_policy_attachment" "AdministratorAccess-John" {
#   user       = aws_iam_user.John-Admin.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# ##############################################
# # Users with Devops group and AdministratorAccess policy
# ##############################################

# resource "aws_iam_user" "Diane-Devops" {
#   name = "pl-Diane-Devops"
# }

# resource "aws_iam_user" "Dana-Devops" {
#   name = "pl-Dana-Devops"
# }

# resource "aws_iam_user" "Dawn-Devops" {
#   name = "pl-Dawn-Devops"
# }

# resource "aws_iam_group" "Devops" {
#   name = "pl-Devops"
# }

# resource "aws_iam_group_membership" "Diane-Devops" {
#   name = "Diane-Devops"
#   users = [ aws_iam_user.Diane-Devops.name, aws_iam_user.Dana-Devops.name, aws_iam_user.Dawn-Devops.name ]
#   group = aws_iam_group.Devops.name
# }

# resource "aws_iam_group_policy_attachment" "Devops" {
#   group      = aws_iam_group.Devops.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# ##############################################
# # Roles with AdministratorAccess policy
# ##############################################


# resource "aws_iam_role" "EC2Admin" {
#   name = "pl-EC2Admin"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "EC2admin" {
#   role = aws_iam_role.EC2Admin.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# } 

# resource "aws_iam_instance_profile" "EC2Admin" {
#   name = "pl-EC2Admin"
#   role = aws_iam_role.EC2Admin.name
# }



# # Deployment role - only created when GitHub integration is enabled
# resource "aws_iam_role" "Deployement" {
#   count = var.github_repo != null ? 1 : 0
#   name = "pl-Deployement"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#          AWS = "arn:aws:iam::${var.operations_account_id}:role/pl-ops-infra-deployer"
#         },
#         Action = [ "sts:AssumeRole", "sts:TagSession" ]
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "Deployementadmin" {
#   count = var.github_repo != null ? 1 : 0
#   role = aws_iam_role.Deployement[0].name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }

# ##############################################
# # Roles with a custom administrator policy
# ##############################################


# ##############################################
# # Principals that have an inline policy that alllows administrator access
# ##############################################

# resource "aws_iam_user" "Bob" {
#   name = "pl-Bob"
# }

# resource "aws_iam_user_policy" "Bob" {
#   name = "pl-Bob"
#   user = aws_iam_user.Bob.name
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = "*",
#         Resource = "*"
#       }
#     ]
#   })
# }





# ##############################################
# # Principals that can privesc to admin
# ##############################################

# resource "aws_iam_role" "EC2-automation" {
#   name = "pl-EC2-automation"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# } 

# resource "aws_iam_policy" "EC2-ssm-access" {
#   name = "pl-EC2-ssm-access"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ssm:StartSession",
#           "ssm:DescribeSessions",
#           "ssm:SendCommand",
#           "ssm:TerminateSession",
#           "ssm:DescribeInstanceProperties",
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource aws_iam_user "lambda-publisher" {
#   name = "pl-lambda-publisher"  
# }

# resource aws_iam_user_policy_attachment "lambda-publisher" {
#   user = aws_iam_user.lambda-publisher.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
# }



# resource aws_iam_user "Pam-Helpdesk" {
#   name = "pl-Pam-Helpdesk"  
# }

# resource aws_iam_policy "helpdesk-createaccesskeys" {
#   name = "pl-helpdesk-createaccesskeys"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = "iam:CreateAccessKey", 
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource aws_iam_user_policy_attachment "Pam-Helpdesk" {
#   user = aws_iam_user.Pam-Helpdesk.name
#   policy_arn = aws_iam_policy.helpdesk-createaccesskeys.arn
# }

# ##############################################
# # Non admin user with multiple policies attached
# ##############################################

# resource "aws_iam_user" "Sam" {
#   name = "pl-Sam-Auditor"
# }

# resource "aws_iam_user_policy_attachment" "Sam" {
#   user       = aws_iam_user.Sam.name
#   policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
# }

# resource "aws_iam_user_policy_attachment" "Sam2" {
#   user       = aws_iam_user.Sam.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSCloudTrail_ReadOnlyAccess"
# }

# resource "aws_iam_user_policy_attachment" "Sam3" {
#   user       = aws_iam_user.Sam.name
#   policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
# }


# ##############################################
# # Role in prod that allows anyone in the account to assume it
# ##############################################

# resource "aws_iam_role" "breakglass-prod-admin" {
#   name = "pl-breakglass-prod-admin"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.prod_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_policy" "breakglass-prod" {
#   name = "pl-breakglass-prod-admin"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = "*",
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "breakglass-prod" {
#   role = aws_iam_role.breakglass-prod-admin.name
#   policy_arn = aws_iam_policy.breakglass-prod.arn
# }

# # User that can assume the breakglass role

# resource "aws_iam_user" "Ryan" {
#   name = "pl-Ryan"
# }

# # Policy that gives Ryan sts:* permissions

# resource "aws_iam_policy" "Ryan" {
#   name = "pl-Ryan"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = "sts:AssumeRole",
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource "aws_iam_user_policy_attachment" "Ryan" {
#   user = aws_iam_user.Ryan.name
#   policy_arn = aws_iam_policy.Ryan.arn
# }

##############################################
# Amazon linux Ec2 instance for teleport
##############################################

# data "aws_ami" "teleport" {
#   most_recent = true

#   filter {
#     name   = "name"
#     values = ["amzn2-ami-hvm-*-x86_64-ebs"]
#   }

#   owners = ["amazon"] 
# }


# resource "aws_security_group" "intra-sg-access" {
#   name        = "intra-sg-access"
#   description = "intra-sg-access"
#   vpc_id      = var.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 65535
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "intra-sg-access"
#   }
# }



# resource "aws_instance" "teleport" {
#   ami           = data.aws_ami.teleport.id
#   instance_type = "t3a.micro"
#   subnet_id = var.subnet1_id
#   iam_instance_profile = aws_iam_instance_profile.EC2Admin.name
#   associate_public_ip_address = true
#   vpc_security_group_ids = [ aws_security_group.intra-sg-access.id ]

#   tags = {
#     Name = "teleport"
#   }
# }

# ##############################################
# # Create role that has two seperate external ID contitions that it trusts
# ##############################################

# resource "aws_iam_role" "externalID" {
#   name = "pl-externalID"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole",
#         Condition = {
#           StringEquals = {
#             "sts:ExternalId" : ["external-id-1", "external-id-2"]
#           }
#         }
#       },
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole",
#         Condition = {
#           StringEquals = {
#             "sts:ExternalId" = "987654321"
#           }
#         }
#       }
#     ]
#   })
# }
