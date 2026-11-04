# ---------------------------------------------------------------------------
# VPC compartilhada pelo cluster GKE, pelo peering do Cloud SQL
# (tech-challenge-database) e pelo Direct VPC egress do Cloud Run
# (tech-challenge-auth). Os outros repositorios a leem por NOME, entao o nome
# "default" e o contrato entre eles.
#
# Subnet unica e manual: as faixas secundarias de pods e services sao criadas
# pelo GKE (ip_allocation_policy {} em main.tf), e a faixa do peering do Cloud
# SQL e reservada pelo tech-challenge-database fora deste intervalo.
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = var.network
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "main" {
  name                     = var.subnetwork
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.128.0.0/20"
  private_ip_google_access = true
}
