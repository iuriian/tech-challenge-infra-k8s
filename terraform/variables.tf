variable "project_id" {
  description = "ID do projeto GCP. Deve casar com a variable GCP_PROJECT_ID do Environment 'staging'."
  type        = string
}

variable "region" {
  description = "Regiao padrao dos recursos"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona do cluster. Cluster zonal e mais barato que regional e suficiente para staging. Deve casar com a variable GKE_ZONE."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Nome do cluster. Deve casar com a variable GKE_CLUSTER."
  type        = string
  default     = "tech-challenge-staging"
}

# DIMENSIONAMENTO
#
# O cluster roda so a aplicacao: o banco e um Cloud SQL externo e o emissor de
# tokens e serverless. Requests em k8s/app/deployment.yaml: 100m/384Mi por
# replica, ou 300m/1,13Gi no teto do HPA (3 replicas).
#
# Um no de 4GB nao oferece 4GB: o GKE reserva ~1,3GB para o sistema e ainda
# roda kube-dns, fluentbit e metrics-agent, sobrando ~2,2Gi uteis e ~690m de
# CPU. Um unico e2-medium comporta o teto do HPA com folga nas duas dimensoes.
#
# O app/deployment.yaml usa maxSurge: 0, que nao exige capacidade de dois pods
# durante o rollout. Com os requests atuais o no comportaria o surge; a opcao
# segue valendo como margem, ao custo de uma breve indisponibilidade no deploy.
#
# e2-small (2GB) NAO funciona: sobram ~600Mi por no e a aplicacao nao chega a
# ser agendada.
variable "machine_type" {
  description = "Tipo de maquina dos nos"
  type        = string
  default     = "e2-medium"
}

# O HPA (k8s/app/hpa.yaml) escala a aplicacao ate 3 replicas. Sem autoscaling
# no node pool, essas replicas extras ficariam em Pending: um unico e2-medium
# nao tem CPU para elas. Os dois autoscalers sao complementares - o HPA cria
# pods, o cluster autoscaler cria nos.
variable "min_node_count" {
  description = "Minimo de nos no pool"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximo de nos que o cluster autoscaler pode criar"
  type        = number
  default     = 3
}

# Spot VMs custam 60-91% menos. A VM pode ser reivindicada pelo Google com 25s
# de aviso e os pods sao reagendados - risco aceitavel em um staging que ja e
# descartavel. Em GKE Standard, node pools spot recebem apenas labels, sem taint,
# entao os workloads sao agendados sem precisar de tolerations.
variable "use_spot_vms" {
  description = "Usar Spot VMs no node pool (muito mais barato, pode ser reivindicada)"
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Disco por no. O padrao do GKE e 100GB; 30GB basta para staging e reduz custo."
  type        = number
  default     = 30
}

# Nem todo projeto tem a VPC 'default' - varias organizacoes a removem por
# politica. Deixar explicito evita um erro obscuro na criacao do cluster.
variable "network" {
  description = "Nome da VPC onde o cluster sera criado"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Nome da subnet. Deve existir na regiao configurada."
  type        = string
  default     = "default"
}

variable "ci_service_account_id" {
  description = "ID da service account usada pelo GitHub Actions"
  type        = string
  default     = "github-actions-cd"
}

# ---------------------------------------------------------------------------
# API GATEWAY (gateway.tf)
# ---------------------------------------------------------------------------

# State do tech-challenge-auth, de onde sai o issuer dos tokens (auth.tf).
variable "auth_state_bucket" {
  description = "Bucket do state do tech-challenge-auth"
  type        = string
}

variable "auth_state_prefix" {
  description = "Prefixo do state do tech-challenge-auth no bucket"
  type        = string
}

# O servico de autenticacao emite o token com aud=oficina (cd-homolog.yml do
# tech-challenge-auth) e a aplicacao valida o mesmo valor em AUTH_AUDIENCE. Os
# tres precisam casar: um aud diferente aqui faz o gateway recusar todo token
# valido com 401.
variable "auth_audience" {
  description = "Audience exigida nos tokens pelo gateway. Deve casar com AUTH_AUDIENCE da aplicacao."
  type        = string
  default     = "oficina"
}

# A SA do pipeline precisa de roles/servicemanagement.editor para habilitar o
# managed service do gateway (gateway.tf) -- o gateway.tf explica por que e o
# editor, e nao o serviceConsumer que a documentacao sugere. O binding e
# declarado aqui, e nao concedido a mao no bootstrap, para que um projeto novo
# nao morra no ultimo recurso do apply -- foi o que aconteceu neste projeto.
#
# O email e explicito, e nao lido de data.google_client_openid_userinfo, de
# proposito: com a identidade detectada em tempo de execucao, um apply local
# feito por um humano trocaria o member do binding, e o apply seguinte do CI o
# trocaria de volta. Isso geraria um diff perpetuo alternando os dois.
#
# Vazio desliga o binding: use assim quando quem aplica e um humano com owner,
# que ja carrega servicemanagement.services.bind.
variable "infra_service_account_email" {
  description = "Email da SA que aplica este Terraform. Recebe servicemanagement.editor para habilitar o managed service do gateway. Vazio = nao gerencia o binding."
  type        = string
  default     = ""
}
