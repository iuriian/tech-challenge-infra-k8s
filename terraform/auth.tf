# O emissor dos tokens e o output issuer do tech-challenge-auth. O gateway
# (gateway.tf) precisa dele para montar o jwks_uri e validar o iss de cada
# token. Ler do state, em vez de copiar o valor a mao para uma variable, deixa
# uma fonte unica: o hostname do gateway de autenticacao muda se aquele gateway
# for recriado, e um apply aqui passa a enxergar o valor novo sem intervencao.
#
# A leitura exige que a service account do CI tenha leitura no bucket do state
# (ela ja tem, por objectAdmin no bucket inteiro) e que o tech-challenge-auth
# tenha sido aplicado antes -- ele nao depende deste repo, so da VPC, que le
# por nome.
data "terraform_remote_state" "auth" {
  backend = "gcs"

  config = {
    bucket = var.auth_state_bucket
    prefix = var.auth_state_prefix
  }
}
