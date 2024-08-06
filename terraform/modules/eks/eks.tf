data "aws_caller_identity" "current" {}

locals {
  default_node_name = "karpenter"
}


module "eks" {
	source = "terraform-aws-modules/eks/aws"
  version = "~> 20.20.0"

	cluster_name = var.cluster_name
	cluster_version = var.cluster_version

	cluster_endpoint_private_access = false
	cluster_endpoint_public_access = true

	include_oidc_root_ca_thumbprint = true
	enable_irsa = true

	vpc_id = var.vpc.id
	subnet_ids = var.vpc.subnet_ids
	
	iam_role_arn = var.cluster_arn
	create_iam_role = false

	enable_cluster_creator_admin_permissions = true

	cluster_addons = {
		kube-proxy = {
			more_recent = true
		}
    coredns                = {
			more_recent = true
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
		}
    eks-pod-identity-agent = {
			more_recent = true
		}
    vpc-cni                = {
			before_compute = true
			more_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI           = "true"
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
        init = {
          env = {
            DISABLE_TCP_EARLY_DEMUX = "true"
          }
        }
      })
		}
  }	

	eks_managed_node_group_defaults = var.default_node_group_instance

  node_security_group_additional_rules = {
    ingress_15017 = {
      description                   = "Cluster API - Istio Webhook namespace.sidecar-injector.istio.io"
      protocol                      = "TCP"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_15012 = {
      description                   = "Cluster API to nodes ports/protocols"
      protocol                      = "TCP"
      from_port                     = 15012
      to_port                       = 15012
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {
    ("${local.default_node_name}") = {
      min_size     = 1
      max_size     = 3
      desired_size = 1

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
        ondemand = true
      }
    }
  }

  tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${var.cluster_name}"
  }
}


output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ap-northeast-2 update-kubeconfig --name ${var.cluster_name}"
}


module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.20.0"

  cluster_name = module.eks.cluster_name

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = var.cluster_name

  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn

  create_iam_role      = true
  create_instance_profile = true
  create_node_iam_role = true

  enable_irsa = true
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

################################################################################
# Helm charts
################################################################################

resource "helm_release" "karpenter" {
  create_namespace = true
  namespace           = "karpenter"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = "0.37.0"
  wait                = false

  values = [
    <<-EOT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms: 
            - matchExpressions: 
              - key: karpenter.sh/nodepool
                operator: DoesNotExist
      podAntiAffinity: 
        requiredDuringSchedulingIgnoredDuringExecution:
          # - topologyKey: kubernetes.io/hostname
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
    EOT
  ]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
      labels:
        type: karpenter
    spec:
      amiFamily: AL2023
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            type: karpenter
        spec:
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1beta1
            kind: EC2NodeClass
            name: default
          requirements:
            - key: node.kubernetes.io/instance-type	
              operator: In
              values: ["t4g.medium", "t4g.large", "t4g.xlarge"]
            # - key: "karpenter.k8s.aws/instance-category"
            #   operator: In
            #   values: ["t"]
            # - key: "karpenter.k8s.aws/instance-memory"
            #   operator: In
            #   values: ["4", "8"]
            # - key: "karpenter.k8s.aws/instance-cpu"
            #   operator: In
            #   values: ["1", "2"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: Gt
              values: ["1"]
      limits:
        cpu: 1000
        memory: 1000Gi
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}
