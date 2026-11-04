# ---------------------------------------------------------------------------
# Terraform provisiona a INFRAESTRUTURA que os manifests de k8s/ precisam:
# o cluster GKE, o node pool e a service account que o GitHub Actions usa.
#
# Os workloads NAO ficam aqui. Deployments, Services e ConfigMaps vivem em
# k8s/ e sao aplicados pelo k8s/deploy.sh, chamado pelo cd-staging.yml. O
# criterio e a frequencia de mudanca: o cluster muda raramente, os workloads
# mudam a cada commit e carregam um digest de imagem que o pipeline calcula.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State remoto. NUNCA versione o arquivo de state: ele grava valores de
  # variaveis `sensitive` em texto puro.
  #
  # Crie o bucket antes do primeiro init:
  #   gcloud storage buckets create gs://SEU_PROJECT_ID-tfstate \
  #     --project SEU_PROJECT_ID --location us-central1
  #   gcloud storage buckets update gs://SEU_PROJECT_ID-tfstate --versioning
  #
  # Depois descomente e rode `terraform init -migrate-state`.
  #
  # backend nao aceita variaveis - o nome do bucket precisa ser literal.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}
