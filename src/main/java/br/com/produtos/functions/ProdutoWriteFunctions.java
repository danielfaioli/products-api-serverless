package br.com.produtos.functions;

import br.com.produtos.model.Produto;
import br.com.produtos.model.ProdutoMessage;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.ServiceBusTopicTrigger;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

/**
 * Azure Functions com Service Bus Topic triggers para operações de escrita.
 *
 * Arquitetura CQRS simplificada:
 * - Front end publica mensagem no Topic "produtos" com propriedade action=CREATE|UPDATE|DELETE
 * - Subscriptions filtram por action e disparam a Function correspondente
 * - Cada Function persiste a operação no Azure SQL Database
 *
 * Transações gerenciadas com QuarkusTransaction.requiringNew() porque @Transactional
 * não funciona em triggers do Azure Functions.
 *
 * Em caso de exceção, a mensagem volta para retry automático do Service Bus (até 3x),
 * depois é movida para dead-letter queue.
 */
@ApplicationScoped
public class ProdutoWriteFunctions {

    @Inject
    ObjectMapper objectMapper;

    /**
     * Trigger disparada pela subscription sub-criar (filtro: action = 'CREATE').
     * Deserializa a mensagem, constrói um Produto e persiste no banco.
     */
    @FunctionName("CriarProduto")
    public void criar(
            @ServiceBusTopicTrigger(
                    name             = "msg",
                    topicName        = "produtos",
                    subscriptionName = "sub-criar",
                    connection       = "SERVICEBUS_CONNECTION_STRING"
            ) String msgJson,
            ExecutionContext ctx
    ) {
        ctx.getLogger().info("[CriarProduto] Recebendo mensagem: " + msgJson);
        try {
            ProdutoMessage msg = objectMapper.readValue(msgJson, ProdutoMessage.class);

            QuarkusTransaction.requiringNew().run(() -> {
                Produto produto = new Produto();
                produto.nome      = msg.nome;
                produto.preco     = msg.preco;
                produto.categoria = msg.categoria;
                produto.persist();
                ctx.getLogger().info("[CriarProduto] Produto criado com id: " + produto.id);
            });
        } catch (Exception e) {
            ctx.getLogger().severe("[CriarProduto] Erro ao processar mensagem: " + e.getMessage());
            throw new RuntimeException("Falha ao criar produto", e);
        }
    }

    /**
     * Trigger disparada pela subscription sub-atualizar (filtro: action = 'UPDATE').
     * Busca o produto pelo ID e atualiza os campos fornecidos.
     * Panache detecta a entidade como dirty e persiste as mudanças automaticamente.
     */
    @FunctionName("AtualizarProduto")
    public void atualizar(
            @ServiceBusTopicTrigger(
                    name             = "msg",
                    topicName        = "produtos",
                    subscriptionName = "sub-atualizar",
                    connection       = "SERVICEBUS_CONNECTION_STRING"
            ) String msgJson,
            ExecutionContext ctx
    ) {
        ctx.getLogger().info("[AtualizarProduto] Recebendo mensagem: " + msgJson);
        try {
            ProdutoMessage msg = objectMapper.readValue(msgJson, ProdutoMessage.class);

            if (msg.id == null) {
                throw new IllegalArgumentException("Campo 'id' é obrigatório para UPDATE");
            }

            QuarkusTransaction.requiringNew().run(() -> {
                Produto produto = Produto.findById(msg.id);
                if (produto == null) {
                    throw new RuntimeException("Produto não encontrado: " + msg.id);
                }
                if (msg.nome != null)      produto.nome      = msg.nome;
                if (msg.preco != null)     produto.preco     = msg.preco;
                if (msg.categoria != null) produto.categoria = msg.categoria;
                ctx.getLogger().info("[AtualizarProduto] Produto atualizado: " + msg.id);
            });
        } catch (Exception e) {
            ctx.getLogger().severe("[AtualizarProduto] Erro ao processar mensagem: " + e.getMessage());
            throw new RuntimeException("Falha ao atualizar produto", e);
        }
    }

    /**
     * Trigger disparada pela subscription sub-deletar (filtro: action = 'DELETE').
     * Remove o produto pelo ID.
     */
    @FunctionName("DeletarProduto")
    public void deletar(
            @ServiceBusTopicTrigger(
                    name             = "msg",
                    topicName        = "produtos",
                    subscriptionName = "sub-deletar",
                    connection       = "SERVICEBUS_CONNECTION_STRING"
            ) String msgJson,
            ExecutionContext ctx
    ) {
        ctx.getLogger().info("[DeletarProduto] Recebendo mensagem: " + msgJson);
        try {
            ProdutoMessage msg = objectMapper.readValue(msgJson, ProdutoMessage.class);

            if (msg.id == null) {
                throw new IllegalArgumentException("Campo 'id' é obrigatório para DELETE");
            }

            QuarkusTransaction.requiringNew().run(() -> {
                boolean deleted = Produto.deleteById(msg.id);
                if (!deleted) {
                    throw new RuntimeException("Produto não encontrado para deleção: " + msg.id);
                }
                ctx.getLogger().info("[DeletarProduto] Produto deletado: " + msg.id);
            });
        } catch (Exception e) {
            ctx.getLogger().severe("[DeletarProduto] Erro ao processar mensagem: " + e.getMessage());
            throw new RuntimeException("Falha ao deletar produto", e);
        }
    }
}
