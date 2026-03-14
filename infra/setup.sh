#!/bin/bash
# ==============================================================================
# setup.sh — Provisionamento de infraestrutura Azure para Produtos API
# ==============================================================================
# Pré-requisitos:
#   - Azure CLI instalado e autenticado (az login)
#   - Permissão de Contributor na subscription Azure
#
# Uso: chmod +x infra/setup.sh && ./infra/setup.sh
# Outputs: .env.azure com as variáveis de ambiente necessárias
# ==============================================================================

set -euo pipefail

# ── Configurações base ─────────────────────────────────────────────────────────
RESOURCE_GROUP="produtos-rg"
LOCATION="brazilsouth"
SUFFIX=$RANDOM  # Sufixo único para evitar conflitos de nomes globais

SQL_SERVER_NAME="sql-produtos-${SUFFIX}"
SQL_DB_NAME="produtosdb"
SQL_ADMIN_USER="sqladmin"
SQL_ADMIN_PASS="ProdutosPass@${SUFFIX}!"

SB_NAMESPACE="sb-produtos-${SUFFIX}"
SB_TOPIC="produtos"

STORAGE_NAME="stprodutos${SUFFIX}"
FUNC_APP_NAME="func-produtos-${SUFFIX}"
APP_SERVICE_PLAN="${FUNC_APP_NAME}-plan"

echo "============================================================"
echo "  Provisionando infraestrutura Azure — Produtos API"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  Região         : $LOCATION"
echo "  Sufixo         : $SUFFIX"
echo "============================================================"

# ── 1. Resource Group ─────────────────────────────────────────────────────────
echo ""
echo "→ [1/7] Criando Resource Group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

# ── 2. Azure SQL Server + Database ────────────────────────────────────────────
echo ""
echo "→ [2/7] Criando Azure SQL Server e Database..."
az sql server create \
    --name "$SQL_SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --admin-user "$SQL_ADMIN_USER" \
    --admin-password "$SQL_ADMIN_PASS" \
    --output none

# Firewall: allow Azure services
az sql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "AllowAzureServices" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none

# Database serverless Gen5 2 vCores com auto-pause em 60 min
az sql db create \
    --name "$SQL_DB_NAME" \
    --server "$SQL_SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --edition GeneralPurpose \
    --family Gen5 \
    --capacity 2 \
    --compute-model Serverless \
    --auto-pause-delay 60 \
    --output none

AZURE_SQL_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;databaseName=${SQL_DB_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"

# ── 3. Service Bus Namespace + Topic + Subscriptions ──────────────────────────
echo ""
echo "→ [3/7] Criando Service Bus Namespace, Topic e Subscriptions..."
az servicebus namespace create \
    --name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard \
    --output none

az servicebus topic create \
    --name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --output none

# Subscription para CREATE com filtro SQL
az servicebus topic subscription create \
    --name "sub-criar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --max-delivery-count 3 \
    --dead-lettering-on-message-expiration true \
    --output none

az servicebus topic subscription rule create \
    --name "filter-criar" \
    --subscription-name "sub-criar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --filter-sql-expression "action = 'CREATE'" \
    --output none

# Subscription para UPDATE com filtro SQL
az servicebus topic subscription create \
    --name "sub-atualizar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --max-delivery-count 3 \
    --dead-lettering-on-message-expiration true \
    --output none

az servicebus topic subscription rule create \
    --name "filter-atualizar" \
    --subscription-name "sub-atualizar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --filter-sql-expression "action = 'UPDATE'" \
    --output none

# Subscription para DELETE com filtro SQL
az servicebus topic subscription create \
    --name "sub-deletar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --max-delivery-count 3 \
    --dead-lettering-on-message-expiration true \
    --output none

az servicebus topic subscription rule create \
    --name "filter-deletar" \
    --subscription-name "sub-deletar" \
    --topic-name "$SB_TOPIC" \
    --namespace-name "$SB_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --filter-sql-expression "action = 'DELETE'" \
    --output none

# Remover regra padrão "$Default" que aceita tudo
for sub in "sub-criar" "sub-atualizar" "sub-deletar"; do
    az servicebus topic subscription rule delete \
        --name "\$Default" \
        --subscription-name "$sub" \
        --topic-name "$SB_TOPIC" \
        --namespace-name "$SB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null || true
done

SERVICEBUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
    --resource-group "$RESOURCE_GROUP" \
    --namespace-name "$SB_NAMESPACE" \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    --output tsv)

# ── 4. Storage Account (necessário para Functions) ────────────────────────────
echo ""
echo "→ [4/7] Criando Storage Account..."
az storage account create \
    --name "$STORAGE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --output none

# ── 5. Function App (Linux, Java 21, Consumption) ─────────────────────────────
echo ""
echo "→ [5/7] Criando Function App..."
az functionapp create \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-account "$STORAGE_NAME" \
    --consumption-plan-location "$LOCATION" \
    --runtime java \
    --runtime-version 21 \
    --functions-version 4 \
    --os-type Linux \
    --output none

# ── 6. Configurar App Settings do Function App ────────────────────────────────
echo ""
echo "→ [6/7] Configurando App Settings..."
az functionapp config appsettings set \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        "SERVICEBUS_CONNECTION_STRING=$SERVICEBUS_CONNECTION_STRING" \
        "AZURE_SQL_URL=$AZURE_SQL_URL" \
        "AZURE_SQL_USER=$SQL_ADMIN_USER" \
        "AZURE_SQL_PASSWORD=$SQL_ADMIN_PASS" \
    --output none

# ── 7. Salvar outputs em .env.azure ───────────────────────────────────────────
echo ""
echo "→ [7/7] Salvando outputs em .env.azure..."
cat > .env.azure << EOF
# Gerado por infra/setup.sh em $(date)
FUNC_APP_NAME=$FUNC_APP_NAME
SERVICEBUS_CONNECTION_STRING="$SERVICEBUS_CONNECTION_STRING"
AZURE_SQL_URL="$AZURE_SQL_URL"
AZURE_SQL_USER=$SQL_ADMIN_USER
AZURE_SQL_PASSWORD=$SQL_ADMIN_PASS
RESOURCE_GROUP=$RESOURCE_GROUP
SQL_SERVER_NAME=$SQL_SERVER_NAME
SB_NAMESPACE=$SB_NAMESPACE
EOF

echo ""
echo "============================================================"
echo "  Provisionamento concluído com sucesso!"
echo "  Outputs salvos em .env.azure"
echo ""
echo "  Function App URL:"
echo "  https://${FUNC_APP_NAME}.azurewebsites.net/api"
echo ""
echo "  Próximos passos:"
echo "  1. source .env.azure"
echo "  2. Configurar secrets no GitHub (veja README.md)"
echo "  3. Push na branch main para disparar o CI/CD"
echo "============================================================"
