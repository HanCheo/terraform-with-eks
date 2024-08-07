terraform {
	required_version = ">= 1.9.2"
	required_providers {
		aws = {
			source  = "hashicorp/aws"
			version = "~> 5.59.0"
		}
    kubectl = {
      source = "alekc/kubectl"
      version = ">= 2.0.4"
    }
		helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14.0"
    }
	}
}
