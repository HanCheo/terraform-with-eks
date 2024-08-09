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
  create_namespace    = true
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = "0.37.0"
  wait                = false

  values = [
    <<-EOT
    replicas: 1
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
		podAnnotations: |
			ad.datadoghq.com/controller.checks: |
				{
					"karpenter": {
						"init_config": {},
						"instances": [
							{
								"openmetrics_endpoint": "http://%%host%%:8000/metrics"
							}
						]
					}
				} 
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
              values: ["t4g.large", "t4g.xlarge"]
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
