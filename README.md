# Terraform — infraestrutura do staging

Provisiona o cluster GKE, o API Gateway que publica a API e a service account do
CI. Os workloads continuam em `k8s/`, aplicados pelo `k8s/deploy.sh`.

## Fronteira

| Terraform | Resto do repositório |
|---|---|
| APIs do GCP, cluster GKE, node pool | `k8s/*/*.yaml` — Deployments, Services, ConfigMaps |
| Service account do CI e IAM | `cd-staging.yml` — secrets do cluster |
| API Gateway, a spec que ele serve e o IP reservado do Service | `loadBalancerIP` do Service, substituído pelo `deploy.sh` |
| | `k8s/deploy.sh` — namespace e ordem de aplicação |

**Por que os workloads não estão aqui.** Eles mudam a cada commit e carregam um
digest de imagem que o pipeline calcula. Em HCL, cada deploy exigiria um
`terraform apply`, com o state disputando o cluster com o `kubectl`. Terraform
cuida do que dura; o pipeline, do que muda.

## Uso

```bash
gcloud auth application-default login

cd terraform
terraform init -reconfigure -backend-config=environments/staging.gcs.tfbackend
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars
```

Na prática o `apply` sai pelo pipeline (seção **Pipeline**); o caminho local
serve para inspeção.

O `apply` leva de 5 a 10 minutos (criar cluster no GKE é lento). Ao final:

```bash
terraform output
eval "$(terraform output -raw get_credentials_command)"
kubectl get nodes
```

### State remoto

O state vive no GCS, em `gs://tech-challenge-507123-tfstate` com versionamento,
sob o prefixo `tech-challenge/infra-k8s/staging`. O `backend "gcs"` em
`versions.tf` é parcial: bucket e prefixo vêm de
`environments/staging.gcs.tfbackend`, passado no `init -backend-config`.

**Nunca versione o `.tfstate`** — ele grava valores `sensitive` em texto puro.

## Pipeline

| Workflow | Quando | O que faz |
|---|---|---|
| `terraform-ci.yml` | PR que toca `terraform/**` | `fmt`, `validate` e `plan` no summary |
| `terraform-cd.yml` | push na `main`, ou **Run workflow** | `plan` + `apply` e `outputs` no summary |

O `workflow_dispatch` existe para o primeiro provisionamento: o push que *cria*
uma branch não carrega arquivos alterados, então o filtro de `paths` ignora o
evento.

**Aplique este repositório primeiro.** O `tech-challenge-database` lê a VPC pelo
nome (`data "google_compute_network"`) e falha com
`networks/default not found` enquanto ela não existir.

## As duas service accounts

Não confunda: são contas diferentes, com privilégios muito diferentes.

| Service account | Criada por | Usada por | Papéis |
|---|---|---|---|
| `github-actions-infra` | bootstrap manual (abaixo) | os workflows **deste** repositório | admin de rede, GKE, APIs, IAM e segredos |
| `github-actions-cd` | o Terraform daqui (`iam.tf`) | `cd-staging.yml` da app, para o `kubectl` | só `roles/container.developer` |

A segunda não consegue aplicar este Terraform — ela só fala com o cluster já
criado.

### Bootstrap da `github-actions-infra` (uma vez)

```bash
PROJECT=tech-challenge-507123
SA=github-actions-infra@${PROJECT}.iam.gserviceaccount.com

# O provider usa estas duas para gerenciar os google_project_service de
# apis.tf. Sem elas o plan falha no refresh, antes de avaliar qualquer
# mudanca, e o Terraform nao consegue se desbloquear sozinho.
gcloud services enable   cloudresourcemanager.googleapis.com   serviceusage.googleapis.com   --project "$PROJECT"

gcloud iam service-accounts create github-actions-infra \
  --project "$PROJECT" --display-name "GitHub Actions - tech-challenge-infra-k8s"

for ROLE in \
  roles/container.admin \
  roles/compute.networkAdmin \
  roles/serviceusage.serviceUsageAdmin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/apigateway.admin \
  roles/servicemanagement.serviceConsumer \
  roles/secretmanager.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member "serviceAccount:$SA" --role "$ROLE" --condition=None
done

# State: acesso so ao bucket, nao ao projeto inteiro
gcloud storage buckets add-iam-policy-binding gs://${PROJECT}-tfstate \
  --member "serviceAccount:$SA" --role roles/storage.objectAdmin
```

| Papel | Para quê |
|---|---|
| `container.admin` | cluster e node pool |
| `compute.networkAdmin` | VPC e subnet |
| `serviceUsageAdmin` | habilitar APIs |
| `iam.serviceAccountAdmin` | criar a SA do CI da app |
| `iam.serviceAccountUser` | usar a SA padrão de compute nos nós do GKE |
| `projectIamAdmin` | conceder `container.developer` à SA do CI da app |
| `apigateway.admin` | API, api-config e gateway (`gateway.tf`) |
| `servicemanagement.serviceConsumer` | habilitar o managed service do gateway. Carrega uma única permissão, `servicemanagement.services.bind`, que **não** está em `serviceUsageAdmin` — sem ela o apply cria o gateway e falha no último recurso |
| `secretmanager.admin` | criar a senha do banco e dar acesso ao CI da app |

## Chave do `GCP_SA_KEY`

Não é criada pelo Terraform de propósito: `google_service_account_key` gravaria a
chave privada no state.

```bash
# Chave da SA deste pipeline: Environment "staging" DESTE repositorio
gcloud iam service-accounts keys create key.json \
  --iam-account github-actions-infra@tech-challenge-507123.iam.gserviceaccount.com

# Chave da SA do CI da app: Environment "staging" do repositorio da aplicacao
SA=$(terraform output -raw ci_service_account_email)
gcloud iam service-accounts keys create key-app.json --iam-account "$SA"
```

Cole o conteúdo em `Settings → Environments → staging → GCP_SA_KEY` do
repositório correspondente e **apague os arquivos de chave**.

> Próximo passo natural: Workload Identity Federation elimina a chave de longa
> duração — o Actions autentica por OIDC e não há segredo para rotacionar.

## API Gateway

A API é publicada por um API Gateway (`gateway.tf`), não pelo IP do Service. Mesmo
desenho do `tech-challenge-auth`: ESPv2 gerenciado pelo Google, spec em OpenAPI 2.0
(`openapi.yaml.tftpl`) e backend por HTTP.

| | |
|---|---|
| Entrada | `https://oficina-api-gw-*.uc.gateway.dev`, TLS com certificado do Google |
| Backend | `http://<ip-do-service>.sslip.io` → Service LoadBalancer do cluster |
| Faz | termina o TLS, valida assinatura/`iss`/`aud` do JWT, recusa rota não declarada |
| Não faz | papéis — isso é `@RolesAllowed` na aplicação |

**Por que `sslip.io`.** O API Gateway não roteia para IP da VPC e o ESPv2 resolve o
backend por DNS: um IP cru em `address` não serve. O `sslip.io` devolve o IP
embutido no próprio hostname (`34-1-2-3.sslip.io` → `34.1.2.3`), então não há
domínio para registrar nem zona de DNS para manter. O salto gateway → LB sai sem
TLS, mas não deixa a rede do Google (mesma região).

**Por que o IP é reservado.** O `google_compute_address.app_lb` existe para o
backend do gateway ter endereço fixo: com o IP efêmero que o GKE sorteia, recriar o
Service troca o endereço e o gateway passa a responder 502 sem que nada tenha
mudado aqui. Preso à forwarding rule do Service, esse IP não é cobrado.

**Por que OpenAPI 2.0 e não 3.x.** Só o 2.0 aceita o curinga duplo `{x=**}`, usado
nas rotas da Swagger UI e dos subpaths do springdoc.

**A spec é contrato de roteamento, não documentação.** O contrato de referência
continua sendo o OpenAPI 3 que o springdoc gera em `/v3/api-docs`. Aqui entram só
método, path e exigência de token — manter schema de corpo nos dois lugares
garantiria que um deles ficaria desatualizado.

### Depois do apply

```bash
terraform output -raw api_gateway_url           # URL pública da API
terraform output -raw app_lb_ip                 # IP do Service
terraform output -raw api_gateway_backend_host  # hostname sslip.io do backend
```

Os dois primeiros vão para o Environment `staging` do repositório da aplicação,
como variables `API_GATEWAY_URL` e `APP_LB_IP`. Sem a segunda, o `deploy.sh` avisa
e o Service sobe com IP efêmero — e o gateway segue apontando para o endereço
antigo.

**Ordem no primeiro provisionamento.** O `tech-challenge-auth` precisa estar
aplicado antes: o `auth.tf` lê o `issuer` do state dele para montar o `jwks_uri`
do gateway. Depois do apply daqui, rode o CD da aplicação para o Service assumir
o IP reservado.

### Mudar a spec

Uma api-config é imutável. Com `api_config_id_prefix` e `create_before_destroy`,
cada `apply` cria uma config nova, aponta o gateway para ela e só então descarta a
antiga — não há intervalo sem configuração servida. A propagação leva de um a dois
minutos depois do apply.

## Dimensionamento

Requests declarados em `k8s/`:

| | réplicas | CPU | memória |
|---|---|---|---|
| app | 1 (HPA até 3) | 100m | 384Mi |
| **total com 1 réplica** | | **100m** | **384Mi** |
| **total no teto do HPA** | | **300m** | **1,13Gi** |

> O cluster roda só a aplicação. O banco é um Cloud SQL externo e o emissor de
> tokens é uma função serverless — nenhum dos dois consome recurso de nó.

Um nó de 4GB não entrega 4GB: o GKE reserva ~1,3GB e ainda roda kube-dns,
fluentbit e metrics-agent, sobrando ~2,2Gi de memória e ~690m de CPU. **Um**
`e2-medium` comporta os 300m/1,13Gi do teto do HPA, com folga nas duas dimensões.

Por isso o `app/deployment.yaml` usa `maxSurge: 0`: com um nó só não há CPU para
dois pods da aplicação simultâneos, e surgir travaria o rollout em `Pending`.
O custo é uma breve indisponibilidade a cada deploy.

`e2-small` (2GB) **não funciona**: sobram ~600Mi por nó e a aplicação fica em
`Pending` com `Insufficient memory`.

Se aumentar réplicas ou requests em `k8s/`, revise `node_count` aqui.

## Custo

Com os defaults (1 nó `e2-medium` spot):

| | por mês |
|---|---|
| 1× e2-medium **spot** | ~$8 |
| 2 LoadBalancers | ~$36 |
| Discos (30GB do nó + 10GB do PVC) | ~$4 |
| Taxa de gestão do cluster | **$0** — free tier de $74,40/mês cobre um cluster zonal |
| API Gateway | **$0** — até 2 milhões de chamadas/mês, sem cobrança por hora |
| IP externo reservado do Service | **$0** — IP preso a forwarding rule não é cobrado |
| **total** | **~$48** |

**Spot VMs** dão 60-91% de desconto. A VM pode ser reivindicada com 25s de aviso
e os pods são reagendados — risco aceitável num staging descartável. Em GKE
Standard elas recebem apenas labels, sem taint, então nada muda nos manifests.
Para desligar: `use_spot_vms = false`.

**A economia real vem de não deixar ligado.** Como a infraestrutura é código,
`terraform destroy` ao terminar e `terraform apply` (10 min) quando precisar leva
o custo para perto de zero — e exercita o Terraform a cada ciclo.

## Senhas: geradas aqui, guardadas no Secret Manager

`DB_PASSWORD` **não existe mais no GitHub**. O Terraform gera com
`random_password`, guarda no Secret Manager, e dá à service account do CI
permissão de leitura **apenas nesse segredo**. O CD o busca em tempo de deploy
com a própria credencial do GCP.

Ganho: nenhuma pessoa digita, copia ou cola essas senhas.

### O state passa a ser crítico

`random_password` grava o valor gerado **no state do Terraform** — usar o Secret
Manager não muda isso. Com state local, as senhas ficam num arquivo na sua
máquina. Por isso o backend GCS deixa de ser recomendação e vira requisito
prático aqui.

### Consultando as senhas

```bash
terraform output secret_names   # mostra o nome do segredo
gcloud secrets versions access latest --secret=tech-challenge-staging-db-password
```

### Rotação — leia antes de rodar

Recriar a senha do banco **não** basta:

```bash
terraform taint random_password.db && terraform apply   # NÃO faça isso sozinho
```

Gerar uma versão nova no Secret Manager não muda a senha do usuário no Cloud SQL:
a aplicação passaria a usar a nova enquanto o banco continua esperando a antiga.
Os três passos, nesta ordem:

```bash
# 1. nova senha no Secret Manager
terraform taint random_password.db && terraform apply

# 2. aplicar no Cloud SQL (instancia no repo tech-challenge-database)
gcloud sql users set-password oficina_app \
  --instance=tech-challenge-staging-pg \
  --password="$(gcloud secrets versions access latest \
                 --secret=tech-challenge-staging-db-password)"

# 3. novo deploy, para o pod receber o secret atualizado
```

O `deploy.sh` injeta o checksum do secret no pod template, então o passo 3
realmente substitui os pods em vez de virar um apply no-op.

## Alinhamento com o GitHub

Os workflows leem estes três como **secrets** do Environment:

| Terraform | Environments `staging` e `production` |
|---|---|
| `cluster_name` | secret `GKE_CLUSTER` |
| `zone` | secret `GKE_ZONE` |
| `project_id` | secret `GCP_PROJECT_ID` |

`terraform output github_environment_variables` mostra os três para conferência.
O workflow detecta ausência, não divergência de valor — se recriar o cluster com
outro nome, atualize o secret.

## Destruindo

Os `Service` do tipo LoadBalancer criam regras de forwarding fora do controle do
Terraform. Remova os workloads antes, senão sobram recursos órfãos cobrando:

```bash
kubectl delete svc app -n tech-challenge-staging
terraform destroy
```
