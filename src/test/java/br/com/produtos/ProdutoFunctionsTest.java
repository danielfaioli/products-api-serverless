package br.com.produtos;

import br.com.produtos.model.Produto;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.transaction.Transactional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

/**
 * Testes de integração para a API de produtos.
 *
 * Usa H2 em memória (perfil test) para não depender de SQL Server.
 * As leituras são testadas via HTTP (REST Assured) contra o servidor Quarkus.
 * As escritas são feitas em transações comprometidas (QuarkusTransaction.requiringNew)
 * para que fiquem visíveis às chamadas HTTP subsequentes.
 */
@QuarkusTest
public class ProdutoFunctionsTest {

    @BeforeEach
    @Transactional
    public void limparDados() {
        Produto.deleteAll();
    }

    /**
     * Teste 1: Lista de produtos deve retornar array vazio quando não há dados.
     */
    @Test
    public void listarProdutos_deveRetornarListaVazia() {
        given()
            .when()
                .get("/api/produtos")
            .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("$", hasSize(0));
    }

    /**
     * Teste 2: Busca por ID inexistente deve retornar 404.
     */
    @Test
    public void buscarProduto_naoEncontrado_deveRetornar404() {
        given()
            .when()
                .get("/api/produtos/999")
            .then()
                .statusCode(404)
                .contentType(ContentType.JSON)
                .body("erro", not(emptyOrNullString()));
    }

    /**
     * Teste 3: Após criar produto (transação comprometida), GET deve retornar lista com um item.
     */
    @Test
    public void criarProduto_deveRetornarListaComUmItem() {
        QuarkusTransaction.requiringNew().run(() -> {
            Produto produto = new Produto();
            produto.nome      = "Notebook";
            produto.preco     = new BigDecimal("3500.00");
            produto.categoria = "eletronicos";
            produto.persist();
        });

        given()
            .when()
                .get("/api/produtos")
            .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("$", hasSize(1))
                .body("[0].nome", equalTo("Notebook"))
                .body("[0].preco", equalTo(3500.0f))
                .body("[0].categoria", equalTo("eletronicos"));
    }

    /**
     * Teste 4: Filtro por categoria deve retornar apenas produtos da categoria informada.
     */
    @Test
    public void listarProdutos_comFiltroCategoria_deveRetornarFiltrado() {
        QuarkusTransaction.requiringNew().run(() -> {
            Produto eletronico = new Produto();
            eletronico.nome      = "Notebook";
            eletronico.preco     = new BigDecimal("3500.00");
            eletronico.categoria = "eletronicos";
            eletronico.persist();

            Produto movel = new Produto();
            movel.nome      = "Cadeira";
            movel.preco     = new BigDecimal("500.00");
            movel.categoria = "moveis";
            movel.persist();
        });

        given()
            .queryParam("categoria", "eletronicos")
            .when()
                .get("/api/produtos")
            .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("$", hasSize(1))
                .body("[0].nome", equalTo("Notebook"))
                .body("[0].categoria", equalTo("eletronicos"));
    }

    /**
     * Teste 5: Busca por ID existente deve retornar o produto completo.
     */
    @Test
    public void buscarProduto_existente_deveRetornar200() {
        long[] idHolder = new long[1];
        QuarkusTransaction.requiringNew().run(() -> {
            Produto produto = new Produto();
            produto.nome      = "Mouse";
            produto.preco     = new BigDecimal("150.00");
            produto.categoria = "perifericos";
            produto.persist();
            idHolder[0] = produto.id;
        });

        given()
            .when()
                .get("/api/produtos/" + idHolder[0])
            .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("nome", equalTo("Mouse"))
                .body("categoria", equalTo("perifericos"));
    }
}
