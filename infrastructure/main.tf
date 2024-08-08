data "aws_caller_identity" "current" {}

provider "aws" {
	region = "ap-northeast-2"	
}
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
	config_path = "~/.kube/config"
}

module vpc {
	source = "./modules/vpc"
	cidr = "10.20.0.0/16"
	name = "sandbox"
}
module eks {
	source = "./modules/eks"
	cluster_name = "sandbox-eks"
	vpc = {
		id = module.vpc.id
		subnet_ids = module.vpc.private_subnet_ids
	}
	default_node_group_instance = {
		ami_type = "AL2_ARM_64"
		disk_size = 10
		instance_types = ["t4g.large"]
		node_group_arn = "arn:aws:iam::058264332540:role/OYG_ServiceRoleForAmazonEKSNodeGroup"
	}

	cluster_arn = "arn:aws:iam::058264332540:role/OYG_ServiceRoleForAmazonEKSCluster"
}