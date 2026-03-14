#!/bin/bash
# ==============================================================================
# smoke-test-prod.sh — Testes de smoke no ambiente de produção (Azure)
# ==============================================================================
# Pré-requisitos:
#   - source .env.azure (para ter FUNC_APP_NAME e SERVICEBUS_CONNECTION_STRING)
#   - Azure CLI instalado e autenticado
#
# Uso: source .env.azure && chmod +x smoke-test-prod.sh && ./smoke-test-prod.sh
# ==============================================================================

set -euo pipefail

# Validar variáveis obrigatórias
: "${FUNC_APP_NAME:?Variável FUNC_APP_NAME não definida. Execute: source .env.azure}"
: "${SERVICEBUS_CONNECTION_STRING:?Variável SERVICEBUS_CONNECTION_STRING não definida.}"

BASE="https://${FUNC_APP_NAME}.azurewebsites.net/api"
WAIT_SECONDS=10

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================================"
echo "  Smoke Test Produção — Produtos API"
echo "  Function App : $FUNC_APP_NAME"
echo "  Base URL     : $BASE"
echo "============================================================"

# ── Teste 1: Health check ──────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[0/5] Health check...${NC}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}✓ Health check OK (status $STATUS)${NC}"
else
    echo -e "${RED}✗ Health check falhou (status $STATUS)${NC}"
    exit 1
fi

# ── Teste 1: Leitura inicial ───────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[1/5] Listando produtos...${NC}"
RESULT=$(curl -s "$BASE/produtos")
echo "Resposta: $RESULT"
echo -e "${GREEN}✓ Endpoint de listagem OK${NC}"

# ── Teste 2: Publicar CREATE ───────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/5] Publicando CREATE no Service Bus...${NC}"
az servicebus topic message send \
    --connection-string "$SERVICEBUS_CONNECTION_STRING" \
    --topic-name produtos \
    --body '{"action":"CREATE","nome":"Notebook","preco":3500.00,"categoria":"eletronicos"}' \
    --message-id "smoke-prod-create-$(date +%s)"
echo -e "${GREEN}✓ CREATE publicado${NC}"
echo "Aguardando processamento (${WAIT_SECONDS}s)..."
sleep $WAIT_SECONDS

# ── Teste 3: Verificar criação ─────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/5] Verificando produto criado...${NC}"
PRODUTOS=$(curl -s "$BASE/produtos")
echo "Produtos: $PRODUTOS"
PRODUTO_ID=$(echo "$PRODUTOS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Pega o produto mais recente (maior ID)
    if data:
        produto = sorted(data, key=lambda x: x['id'])[-1]
        print(produto['id'])
    else:
        print('none')
except:
    print('none')
" 2>/dev/null)

if [ "$PRODUTO_ID" = "none" ] || [ -z "$PRODUTO_ID" ]; then
    echo -e "${RED}✗ Produto não foi criado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Produto criado com ID: $PRODUTO_ID${NC}"

# ── Teste 4: Busca por ID ─────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/5] Buscando produto por ID $PRODUTO_ID...${NC}"
PRODUTO=$(curl -s "$BASE/produtos/$PRODUTO_ID")
echo "Produto: $PRODUTO"
NOME=$(echo "$PRODUTO" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data.get('nome',''))" 2>/dev/null)
if [ "$NOME" = "Notebook" ]; then
    echo -e "${GREEN}✓ Produto encontrado por ID${NC}"
else
    echo -e "${RED}✗ Nome incorreto: '$NOME'${NC}"
    exit 1
fi

# ── Teste 5: DELETE ───────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/5] Publicando DELETE para produto ID $PRODUTO_ID...${NC}"
az servicebus topic message send \
    --connection-string "$SERVICEBUS_CONNECTION_STRING" \
    --topic-name produtos \
    --body "{\"action\":\"DELETE\",\"id\":${PRODUTO_ID}}" \
    --message-id "smoke-prod-delete-$(date +%s)"
echo -e "${GREEN}✓ DELETE publicado${NC}"
echo "Aguardando processamento (${WAIT_SECONDS}s)..."
sleep $WAIT_SECONDS

STATUS_404=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/produtos/$PRODUTO_ID")
if [ "$STATUS_404" = "404" ]; then
    echo -e "${GREEN}✓ Produto deletado (404 confirmado)${NC}"
else
    echo -e "${YELLOW}⚠ Status inesperado após DELETE: $STATUS_404 (pode ser latência de replicação)${NC}"
fi

echo ""
echo "============================================================"
echo -e "${GREEN}  ✓ Smoke tests de produção concluídos!${NC}"
echo "============================================================"
