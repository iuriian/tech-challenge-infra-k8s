# ---------------------------------------------------------------------------
# APIs necessarias, para que `terraform apply` nao exija habilitar cada uma na
# mao em um projeto novo.
#
# EXCECAO: cloudresourcemanager.googleapis.com NAO entra aqui. O provider a usa
# para ler e escrever `google_project_service`, entao desabilitada ela faz este
# proprio arquivo falhar no refresh - o Terraform nao pode habilitar a API da
# qual ele depende para habilitar APIs. Habilite uma vez no bootstrap (README).
#
# disable_on_destroy = false: desabilitar a API do GKE ao destruir o cluster
# afetaria qualquer outro recurso do projeto que dependa dela.
# ---------------------------------------------------------------------------
resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# A configuracao padrao do GKE envia logs e metricas para o Cloud Operations.
# Sem estas APIs, a criacao do cluster falha em um projeto novo.
resource "google_project_service" "logging" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# Necessaria para criar a service account do CI (iam.tf).
resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Guarda a senha do banco (secrets.tf).
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}
