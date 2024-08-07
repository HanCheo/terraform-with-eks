# terrform-with-eks

## 설정변경

`infrastructure/main.tf` 파일에 vpc 설정과 node instance의 사이즈를 조절할수 있습니다

```hcl
provider "aws" {
	region = "ap-northeast-2"
}
module vpc {
	source = "./modules/vpc"
	// 원하는 cidr블록으로 변경해주세요
	//서브넷은 자동으로 public [10.20.10.0/24, 10.20.20.0/24]
	//서브넷은 자동으로 private [10.20.30.0/24, 10.20.30.0/24]
	//형태로 만들어집니다.
	cidr = "10.20.0.0/16"

	//콘솔에서 보여질 vpc name
	name = "sandbox_vpc"
}
module eks {
	source = "./modules/eks"
	// 만든 클러스터의 이름
	cluster_name = "sandbox-eks"
	vpc = {
		id = module.vpc.id
		subnet_ids = module.vpc.private_subnet_ids
	}

	default_node_group_instance = {
		//노드그룹 스펙 조절
		ami_type = "AL2_x86_64"
		disk_size = 10
		instance_types = ["t3.large"]
```

aws에 접속이 안된다면 aws 액세스키를 로컬에 잘 설정했는지 확인해보세요
`aws configure`

### 테스트 앱 실행방법

이 레포지토리의 코드는
terroform으로 eks를 만들고 istio를 적용시킵니다.

istio가 적용된 todo-list app을 외부에서 접근해보는 것입니다

```zsh
brew install terraform
brew install helm

// install istioctl
curl -L https://istio.io/downloadIstio | sh -
// 아래는 일회성  코드이고 .zshrc에 path 추가하는게 정신건강에 좋습니다
export PATH=$PWD/bin:$PATH

terraform plan
terraform apply

// eks cluster config를 가져옵니다
aws eks update-kubeconfig --region ap-northeast-2 --name YOUR_CLUSTER_NAME

// CLUSTER_NAME으로 안되면 arn:aws:eks:ap-northeast-2:xxxxxxxx:cluster/YOUR_CLUSTER_NAME 이런 형태입니다
kubectl config use-context YOUR_CLUSTER_NAME

istioctl install -f ./k8s/istio-operator/istio-operator.yaml
// namespace 에러 발생시
kubectl create namespace istio-system
// 사이드카 자동 생성을 위해 pod가 연결된 namespace에 labels 추가
kubectl label namespace default istio-injection=enabled

//datadog api-key, secret-key 입력 없으면 넘어가도됩니다
kubectl install -f ./datadog-operator

// 테스트용 todo 앱 연결
kubectl install -f ./k8s/todo-list

// 아래 명령어를 치고 나오는 url 접속
kubectl get svc -n istio-system istio-ingressgateway
```

### 확인이 완료되면

`terraform destroy` 명령어로 생성한 리소스 제거
