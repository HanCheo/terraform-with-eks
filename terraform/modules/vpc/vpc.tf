data "aws_availability_zones" "available" {
  state = "available"
}

locals {
	az = data.aws_availability_zones.available.names
	subnet = {
		"public" = [for i in [10, 20] : cidrsubnet(var.cidr, 8, i)]
		"private" = [for i in [30, 40, 50, 60, 70, 80] : cidrsubnet(var.cidr, 8, i)]
	}
}
resource "aws_vpc" "sandbox_vpc" {
	cidr_block = var.cidr

	enable_dns_hostnames = true
	enable_dns_support = true

	tags = {
		Name = "${var.name}_vpc"
	}
} 

resource "aws_subnet" "public_subnet" {
	vpc_id = aws_vpc.sandbox_vpc.id
	for_each = toset(local.subnet.public)

	cidr_block = each.value
	availability_zone = local.az[floor(index(local.subnet.public, each.value) / 2)]
	map_public_ip_on_launch = true

	tags = {
		 "kubernetes.io/role/elb" = 1
		Name = "${var.name}_vpc_public_subnet_${index(local.subnet.public, each.value)}"
	}
}

resource "aws_subnet" "private_subnet" {
	for_each = toset(local.subnet.private)
	vpc_id = aws_vpc.sandbox_vpc.id
	cidr_block = each.value
	availability_zone = local.az[floor(index(local.subnet.private, each.value) / 2)]
	map_public_ip_on_launch = false
	
	tags = {
		"kubernetes.io/role/internal-elb" = 1
		Name = "${var.name}_vpc_private_subnet_${index(local.subnet.private, each.value)}"
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = "sandbox-eks"
	}
}

resource "aws_internet_gateway" "igw" {
	vpc_id = aws_vpc.sandbox_vpc.id

	tags = {
		Name = "${var.name}_vpc_igw"
	}
}

resource "aws_eip" "nat" {
	domain = "vpc"
	lifecycle {
		create_before_destroy = true
	}
}

resource "aws_nat_gateway" "nat_gateway" {
	allocation_id = aws_eip.nat.id
	subnet_id = values(aws_subnet.public_subnet)[0].id

	tags = {
		Name = "${var.name}_nat_gtw"
	}

  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
	vpc_id = aws_vpc.sandbox_vpc.id
	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.igw.id
	}
	
	tags = {
		Name = "${var.name}_vpc_public_rt"
	}
}

resource "aws_route_table" "private" {
	vpc_id = aws_vpc.sandbox_vpc.id

	route {
		cidr_block = "0.0.0.0/0"
		nat_gateway_id = aws_nat_gateway.nat_gateway.id
	}

	tags = {
		Name = "${var.name}_vpc_private_rt"
	}
}

resource "aws_route_table_association" "route_table_association_public" {
	for_each =  aws_subnet.public_subnet
	subnet_id = each.value.id
	route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "route_table_association_private" {
	for_each =  aws_subnet.private_subnet
	subnet_id = each.value.id
	route_table_id = aws_route_table.private.id
}