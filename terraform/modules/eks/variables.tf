variable "cluster_name" {
	type = string
	default = ""
	description = "eks cluster name"
}

variable "cluster_version" {
	type = string
	default = ""
	description = "eks cluster version"
}

variable "cluster_arn" {
	type = string
	default = ""
	description = "eks cluster arn"
}

variable "default_node_group_instance" {
	type = object({
		ami_type = string
		disk_size = number
		instance_types = list(string)
		node_group_arn = string
	})
	default = {
		ami_type = "AL2_ARM_64"
		disk_size = 10
		instance_types = ["t4g.medium"]
		node_group_arn = ""
	}
	description = <<EOT
		node_group_instance = {
			ami_type : "AL2_ARM_64"
			disk_size : 10
			instance_types : "t4g.medium"
			node_group_arn : "node group arn"
		}
	EOT
}

variable "vpc" {
	type = object({
		id = string
		subnet_ids = list(string)
	})
	default = {
		id = ""
		subnet_ids = []
	}
	description = <<EOT
    vpc = {
      id : "vpc_id"
      subnet_ids : "vpc subnet id list"
    }
  EOT
}
