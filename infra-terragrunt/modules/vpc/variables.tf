variable "name" {
  type        = string
  default     = ""
  description = "vpc name for tags"
}
variable "cidr" {
  type        = string
  default     = ""
  description = "vpc base cidr"
}

variable "eks_cluster_name" {
  type        = string
  default     = ""
  description = "eks cluster name"
}
