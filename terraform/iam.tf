# ---------------------------------------------------------------------------
# Service account do GitHub Actions (job deploy-staging do cd-staging.yml).
#
# A CHAVE NAO E CRIADA AQUI de proposito: `google_service_account_key` grava a
# chave privada no state em texto puro. Gere com gcloud (ver README) e guarde
# apenas no secret GCP_SA_KEY do Environment 'staging'.
# ---------------------------------------------------------------------------
resource "google_service_account" "ci" {
  account_id   = var.ci_service_account_id
  display_name = "GitHub Actions - deploy de staging"
  description  = "Autentica o workflow cd-staging.yml no cluster GKE"

  depends_on = [google_project_service.iam]
}

# container.developer permite obter credenciais do cluster e gerenciar recursos
# dentro dele - exatamente o que o k8s/deploy.sh faz. Nao permite criar nem
# destruir clusters, entao um vazamento dessa chave nao derruba a infra.
resource "google_project_iam_member" "ci_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}
