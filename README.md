# products-api-serverless

Quickstart de aprendizado: API de produtos com Java 21, Quarkus 3.8, Azure Functions e Azure Service Bus.

## Arquitetura

```
┌────────────────────────────────────────────────────────────────────┐
│                        WRITES (async)                              │
│                                                                    │
│  Cliente  ──POST──▶  Azure Service Bus Topic "produtos"            │
│                              │                                     │
│              ┌───────────────┼───────────────┐                    │
│              ▼               ▼               ▼                    │
│         sub-criar       sub-atualizar   sub-deletar               │
│         (CREATE)          (UPDATE)       (DELETE)                  │
│              │               │               │                    │
│              └───────────────┼───────────────┘                    │
│                              ▼                                     │
│                   Azure Function Triggers                          │
│                   (ProdutoWriteFunctions)                           │
│                              │                                     │
│                              ▼                                     │
│                    Azure SQL Database                              │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│                        READS (sync)                                │
│                                                                    │
│  Cliente  ──GET──▶  Azure Function HTTP Trigger                    │
│                     (ProdutoReadFunctions / JAX-RS)                │
│                              │                                     │
│                              ▼                                     │
│                    Azure SQL Database                              │
└────────────────────────────────────────────────────────────────────┘
```

## Pré-requisitos

| Ferramenta | Versão | Instalação |
|---|---|---|
| Java (Temurin) | 21 | [adoptium.net](https://adoptium.net) |
| Docker + Compose | recente | [docker.com](https://docker.com) |
| Azure CLI | recente | [learn.microsoft.com/cli/azure](https://learn.microsoft.com/pt-br/cli/azure/install-azure-cli) |
| Azure Functions Core Tools | v4 | `npm i -g azure-functions-core-tools@4` |

## Configuração local

### 1. Subir SQL Server via Docker

```bash
docker compose up -d
```

### 2. Configurar Service Bus

O Azure Service Bus Topics não tem emulador local gratuito. Você precisa de um namespace real na Azure:

```bash
# Criar namespace e topic (ou use infra/setup.sh para tudo de uma vez)
az servicebus namespace create --name meu-sb --resource-group meu-rg --sku Standard
az servicebus topic create --name produtos --namespace-name meu-sb --resource-group meu-rg
```

Exporte a variável:
```bash
export SERVICEBUS_CONNECTION_STRING="Endpoint=sb://..."
```

### 3. Compilar e testar

```bash
# Testes unitários/integração com H2 em memória (sem Azure)
./mvnw test

# Build completo
./mvnw clean package
```

### 4. Executar localmente

```bash
# Em um terminal: iniciar a função
func start --prefix target/azure-functions/

# Em outro terminal: executar smoke tests
chmod +x smoke-test-local.sh && ./smoke-test-local.sh
```

## Deploy para Azure

### 1. Provisionar infraestrutura

```bash
az login
chmod +x infra/setup.sh && ./infra/setup.sh
```

O script cria e salva em `.env.azure`:
- Resource Group `produtos-rg` na região `brazilsouth`
- Azure SQL Database Serverless Gen5 2 vCores (auto-pause 60 min)
- Service Bus Standard com topic `produtos` e 3 subscriptions com filtros SQL
- Storage Account e Function App (Linux, Java 21, Consumption)

### 2. Configurar secrets no GitHub

Acesse **Settings → Secrets and variables → Actions** no repositório e crie:

| Secret | Como obter |
|---|---|
| `AZURE_CREDENTIALS` | `az ad sp create-for-rbac --sdk-auth` |
| `FUNC_APP_NAME` | Valor `FUNC_APP_NAME` do `.env.azure` |

### 3. Push para main

```bash
git push origin main
```

O CI/CD (`.github/workflows/deploy.yml`) executa automaticamente:
1. Testes com H2 em memória
2. Build `-DskipTests -Dquarkus.profile=prod`
3. Deploy via `./mvnw quarkus:deploy`
4. Smoke test do endpoint `/health`

## Endpoints HTTP

| Método | Path | Descrição |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/produtos` | Listar todos os produtos |
| `GET` | `/api/produtos?categoria=eletronicos` | Filtrar por categoria |
| `GET` | `/api/produtos/{id}` | Buscar produto por ID |

## Mensagens Service Bus (Writes)

Publique mensagens JSON no topic `produtos`. As subscriptions com filtros SQL roteiam automaticamente.

**CREATE:**
```json
{
  "action": "CREATE",
  "nome": "Notebook Pro",
  "preco": 4200.00,
  "categoria": "eletronicos"
}
```

**UPDATE:**
```json
{
  "action": "UPDATE",
  "id": 1,
  "nome": "Notebook Pro Max",
  "preco": 5000.00,
  "categoria": "eletronicos"
}
```

**DELETE:**
```json
{
  "action": "DELETE",
  "id": 1
}
```

### Publicar via Azure CLI

```bash
source .env.azure

# CREATE
az servicebus topic message send \
  --connection-string "$SERVICEBUS_CONNECTION_STRING" \
  --topic-name produtos \
  --body '{"action":"CREATE","nome":"Notebook","preco":3500.00,"categoria":"eletronicos"}'

# Verificar dead-letter (mensagens com erro após 3 tentativas)
az servicebus topic subscription message peek \
  --connection-string "$SERVICEBUS_CONNECTION_STRING" \
  --topic-name produtos \
  --subscription-name sub-criar \
  --count 10
```

## Estrutura do projeto

```
products-api-serverless/
├── src/
│   ├── main/
│   │   ├── java/br/com/produtos/
│   │   │   ├── model/
│   │   │   │   ├── Produto.java              # Entidade JPA (Panache)
│   │   │   │   └── ProdutoMessage.java       # DTO mensagem Service Bus
│   │   │   ├── functions/
│   │   │   │   ├── ProdutoReadFunctions.java  # HTTP trigger (JAX-RS)
│   │   │   │   └── ProdutoWriteFunctions.java # Service Bus triggers
│   │   │   └── exception/
│   │   │       └── NotFoundExceptionMapper.java
│   │   └── resources/
│   │       └── application.properties        # Configurações por perfil
│   └── test/
│       └── java/br/com/produtos/
│           └── ProdutoFunctionsTest.java      # Testes @QuarkusTest + H2
├── infra/
│   └── setup.sh                              # Provisionamento Azure
├── .github/
│   └── workflows/
│       └── deploy.yml                        # CI/CD GitHub Actions
├── docker-compose.yml                        # SQL Server local
├── smoke-test-local.sh                       # Smoke tests local
├── smoke-test-prod.sh                        # Smoke tests produção
└── pom.xml
```

## Variáveis de ambiente

| Variável | Descrição | Perfil |
|---|---|---|
| `SERVICEBUS_CONNECTION_STRING` | Connection string do namespace Service Bus | dev, prod |
| `AZURE_SQL_URL` | JDBC URL do Azure SQL | prod |
| `AZURE_SQL_USER` | Usuário do Azure SQL | prod |
| `AZURE_SQL_PASSWORD` | Senha do Azure SQL | prod |
| `FUNC_APP_NAME` | Nome do Function App | prod (deploy) |

## Stack

| Camada | Tecnologia |
|---|---|
| Runtime | Java 21 (Temurin) |
| Framework | Quarkus 3.8.4 |
| Functions | Azure Functions v4 (Consumption Plan) |
| Mensageria | Azure Service Bus Standard (Topics) |
| Banco de dados | Azure SQL Database Serverless Gen5 2 vCores |
| ORM | Hibernate ORM Panache (Active Record) |
| Testes | @QuarkusTest + H2 + REST Assured |
| CI/CD | GitHub Actions |
| Dev local | Docker Compose (SQL Server 2022) |
