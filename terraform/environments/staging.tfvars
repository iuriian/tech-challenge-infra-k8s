project_id     = "tech-challenge-507123"
zone           = "us-central1-a"
cluster_name   = "tech-challenge-staging"
machine_type   = "e2-medium"
disk_size_gb   = 30
min_node_count = 1
max_node_count = 3
use_spot_vms   = true

# State do tech-challenge-auth aplicado em homologacao: de onde sai o issuer
# que o API Gateway usa para validar os tokens.
auth_state_bucket = "tech-challenge-507123-tfstate"
auth_state_prefix = "tech-challenge/auth/staging"

# SA que o terraform-cd.yml usa (secret GCP_SA_KEY). Recebe por Terraform o
# servicemanagement.serviceConsumer que o managed service do gateway exige.
infra_service_account_email = "github-actions-infra@tech-challenge-507123.iam.gserviceaccount.com"
