# ---------------------------------------------------------------------------
# Senhas geradas pelo Terraform e guardadas no Secret Manager.
#
# O ganho nao e criptografico - e operacional: nenhuma pessoa digita, copia ou
# cola essas senhas, e elas deixam de existir na tela de secrets do GitHub. O
# workflow as busca em tempo de deploy usando a propria credencial do CI.
#
# ATENCAO AO STATE: `random_password` grava o valor gerado no state do
# Terraform. Isso NAO some por usar o Secret Manager. Com state local, as
# senhas ficam em um arquivo na sua maquina; e por isso que o backend GCS
# (versions.tf) deixa de ser recomendacao e passa a ser requisito aqui.
# ---------------------------------------------------------------------------

# special = false: 32 caracteres alfanumericos ja dao entropia de sobra, e
# evitam problemas de escaping em URL JDBC, em shell e em manifest YAML.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.cluster_name}-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

# A service account do CI le apenas ESTE segredo - permissao por recurso, nao no
# projeto inteiro.
resource "google_secret_manager_secret_iam_member" "ci_db_password" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ci.email}"
}
