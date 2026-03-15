#!/bin/bash
# ==============================================================================
# smoke-test-local.sh — Testes de smoke no ambiente local
# ==============================================================================
# Pré-requisitos:
#   - Azure Functions Core Tools v4 rodando: func start (em target/azure-functions/)
#   - SQL Server rodando via docker compose up -d
#   - Variável SERVICEBUS_CONNECTION_STRING configurada (namespace Azure real)
#   - Azure CLI instalado (az)
#
# Uso: chmod +x smoke-test-local.sh && ./smoke-test-local.sh
# ==============================================================================

set -euo pipefail

BASE="http://localhost:7071/api"
WAIT_SECONDS=5

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_env() {
    if [ -z "${SERVICEBUS_CONNECTION_STRING:-}" ]; then
        echo -e "${RED}ERRO: SERVICEBUS_CONNECTION_STRING não está definida.${NC}"
        echo "Configure com a connection string do seu namespace Service Bus."
        exit 1
    fi
}

wait_for_functions() {
    echo "Aguardando Functions Core Tools estar disponível..."
    for i in $(seq 1 30); do
        if curl -s --max-time 2 "$BASE/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Functions Core Tools disponível${NC}"
            return 0
        fi
        echo "  Tentativa $i/30 — aguardando..."
        sleep 2
    done
    echo -e "${RED}✗ Timeout aguardando Functions Core Tools${NC}"
    exit 1
}

echo "============================================================"
echo "  Smoke Test Local — Produtos API"
echo "  Base URL: $BASE"
echo "============================================================"

check_env
wait_for_functions

# ── Teste 1: Leitura inicial (deve retornar lista vazia) ───────────────────────
echo ""
echo -e "${YELLOW}[1/5] Listando produtos (deve estar vazio)...${NC}"
RESULT=$(curl -s "$BASE/produtos")
echo "Resposta: $RESULT"
if echo "$RESULT" | python3 -c "import sys,json; data=json.load(sys.stdin); exit(0 if isinstance(data,list) else 1)" 2>/dev/null; then
    echo -e "${GREEN}✓ Lista retornada com sucesso${NC}"
else
    echo -e "${RED}✗ Resposta inesperada${NC}"
    exit 1
fi

# ── Teste 2: Publicar CREATE no Service Bus ────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/5] Publicando CREATE no Service Bus...${NC}"
az servicebus topic message send \
    --connection-string "$SERVICEBUS_CONNECTION_STRING" \
    --topic-name produtos \
    --body '{"action":"CREATE","nome":"Notebook","preco":3500.00,"categoria":"eletronicos"}' \
    --message-id "smoke-test-create-$(date +%s)" 2>/dev/null || {
    echo -e "${RED}✗ Falha ao publicar mensagem CREATE${NC}"
    echo "Verifique se o topic 'produtos' existe no namespace Service Bus."
    exit 1
}
echo -e "${GREEN}✓ Mensagem CREATE publicada${NC}"
echo "Aguardando processamento (${WAIT_SECONDS}s)..."
sleep $WAIT_SECONDS

# ── Teste 3: Verificar produto criado ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/5] Verificando produto criado...${NC}"
PRODUTOS=$(curl -s "$BASE/produtos")
echo "Produtos: $PRODUTOS"
PRODUTO_ID=$(echo "$PRODUTOS" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['id'] if data else 'none')" 2>/dev/null)

if [ "$PRODUTO_ID" = "none" ] || [ -z "$PRODUTO_ID" ]; then
    echo -e "${RED}✗ Produto não foi criado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Produto criado com ID: $PRODUTO_ID${NC}"

# ── Teste 4: Publicar UPDATE no Service Bus ────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/5] Publicando UPDATE para produto ID $PRODUTO_ID...${NC}"
az servicebus topic message send \
    --connection-string "$SERVICEBUS_CONNECTION_STRING" \
    --topic-name produtos \
    --body "{\"action\":\"UPDATE\",\"id\":${PRODUTO_ID},\"nome\":\"Notebook Pro\",\"preco\":4200.00,\"categoria\":\"eletronicos\"}" \
    --message-id "smoke-test-update-$(date +%s)" 2>/dev/null
echo -e "${GREEN}✓ Mensagem UPDATE publicada${NC}"
echo "Aguardando processamento (${WAIT_SECONDS}s)..."
sleep $WAIT_SECONDS

PRODUTO_ATUALIZADO=$(curl -s "$BASE/produtos/$PRODUTO_ID")
echo "Produto atualizado: $PRODUTO_ATUALIZADO"
NOVO_NOME=$(echo "$PRODUTO_ATUALIZADO" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data.get('nome',''))" 2>/dev/null)
if [ "$NOVO_NOME" = "Notebook Pro" ]; then
    echo -e "${GREEN}✓ Produto atualizado com sucesso${NC}"
else
    echo -e "${RED}✗ Nome esperado: 'Notebook Pro', recebido: '${NOVO_NOME}'${NC}"
    exit 1
fi

# ── Teste 5: Publicar DELETE no Service Bus ────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/5] Publicando DELETE para produto ID $PRODUTO_ID...${NC}"
az servicebus topic message send \
    --connection-string "$SERVICEBUS_CONNECTION_STRING" \
    --topic-name produtos \
    --body "{\"action\":\"DELETE\",\"id\":${PRODUTO_ID}}" \
    --message-id "smoke-test-delete-$(date +%s)" 2>/dev/null
echo -e "${GREEN}✓ Mensagem DELETE publicada${NC}"
echo "Aguardando processamento (${WAIT_SECONDS}s)..."
sleep $WAIT_SECONDS

LISTA_FINAL=$(curl -s "$BASE/produtos")
TOTAL=$(echo "$LISTA_FINAL" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null)
if [ "$TOTAL" = "0" ]; then
    echo -e "${GREEN}✓ Produto deletado com sucesso${NC}"
else
    echo -e "${RED}✗ Produto ainda existe após DELETE (total: $TOTAL)${NC}"
    exit 1
fi

echo ""
echo "============================================================"
echo -e "${GREEN}  ✓ Todos os smoke tests locais passaram!${NC}"
echo "============================================================"
