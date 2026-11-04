# ---------------------------------------------------------------------------
# API Gateway na frente da aplicacao do cluster.
#
# Mesmo desenho do tech-challenge-auth: ESPv2 gerenciado pelo Google, spec em
# OpenAPI 2.0 e backend por HTTP. O que muda e o backend -- la e a URL de um
# Cloud Run, aqui e o Service LoadBalancer do GKE, que o gateway so alcanca por
# endereco publico: o API Gateway nao roteia para IP da VPC.
#
# CUSTO. De 0 a 2 milhoes de chamadas/mes o API Gateway e gratuito e nao ha
# cobranca por hora nem por gateway parado. O IP reservado abaixo tambem nao e
# cobrado enquanto estiver preso a forwarding rule do Service (um IP reservado
# e OCIOSO custaria ~US$ 7/mes). Nao ha load balancer novo: o Service
# LoadBalancer que a aplicacao ja usava continua sendo o unico.
#
# FRONTEIRA. O gateway e o IP vivem aqui porque duram; a spec descreve rotas
# que mudam com o codigo da aplicacao. Enquanto o contrato /api/v2 estiver
# estavel, os dois ritmos convivem -- se passarem a divergir, o caminho e
# mover a spec para o repo da aplicacao e deixar o CD publicar a api-config.
# ---------------------------------------------------------------------------

# IP do Service LoadBalancer da aplicacao, consumido via loadBalancerIP no
# k8s/app/deployment.yaml do repo Tech-Challenge. Precisa ser reservado: com IP
# efemero, recriar o Service troca o endereco e a api-config do gateway passa a
# apontar para o vazio -- sem erro nenhum no apply, so 502 em producao.
resource "google_compute_address" "app_lb" {
  name         = "${var.cluster_name}-app-lb"
  region       = var.region
  address_type = "EXTERNAL"

  depends_on = [google_project_service.compute]
}

# O ESPv2 resolve o backend por DNS; um IP cru no address nao serve. O sslip.io
# devolve o IP embutido no proprio hostname (34-1-2-3.sslip.io -> 34.1.2.3),
# entao nao ha dominio para registrar nem zona de DNS para manter.
locals {
  app_lb_host = "${replace(google_compute_address.app_lb.address, ".", "-")}.sslip.io"
}

resource "google_api_gateway_api" "app" {
  provider     = google-beta
  api_id       = "oficina-api"
  display_name = "Oficina - API"

  depends_on = [google_project_service.apigateway]
}

resource "google_api_gateway_api_config" "app" {
  provider             = google-beta
  api                  = google_api_gateway_api.app.api_id
  api_config_id_prefix = "app-"

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tftpl", {
        app_lb_host     = local.app_lb_host
        auth_issuer_uri = data.terraform_remote_state.auth.outputs.issuer
        auth_audience   = var.auth_audience
      }))
    }
  }

  # Uma api-config e imutavel: qualquer mudanca na spec cria outra. Com o
  # prefix, cada apply gera um id novo; com o create_before_destroy, a nova
  # existe antes de o gateway deixar de apontar para a antiga, e o apply nao
  # passa por um intervalo sem configuracao servida.
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "app" {
  provider   = google-beta
  region     = var.region
  gateway_id = "oficina-api-gw"
  api_config = google_api_gateway_api_config.app.id
}

# Habilitar o managed service exige que ele ja tenha rollout de configuracao, e
# quem faz o rollout e a criacao do gateway. Sem o depends_on o Terraform
# dispara este recurso em paralelo com o gateway e o Service Usage recusa com
# SERVICE_CONFIG_NOT_FOUND_OR_PERMISSION_DENIED -- o apply de um ambiente novo
# nunca passaria de primeira.
resource "google_project_service" "api_managed_service" {
  service            = google_api_gateway_api.app.managed_service
  disable_on_destroy = false

  depends_on = [google_api_gateway_gateway.app]
}
