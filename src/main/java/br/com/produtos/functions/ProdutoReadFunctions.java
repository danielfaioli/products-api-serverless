package br.com.produtos.functions;

import br.com.produtos.model.Produto;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;
import java.util.Map;

/**
 * Funções de leitura expostas como endpoints HTTP.
 *
 * Com quarkus-azure-functions-http, esses endpoints JAX-RS são envolvidos em uma
 * única Azure Function HTTP trigger (QuarkusHttpFunction) na rota /* e roteados
 * para o runtime Quarkus. Em ambiente local e nos testes @QuarkusTest, os endpoints
 * são acessados diretamente via HTTP pelo servidor Quarkus.
 *
 * GET /api/produtos              → lista todos (filtro opcional ?categoria=)
 * GET /api/produtos/{id}         → busca por ID (404 se não encontrado)
 */
@Path("/api/produtos")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
public class ProdutoReadFunctions {

    /**
     * Lista todos os produtos. Suporta filtro opcional por categoria.
     * Nunca retorna 404 – retorna lista vazia se não houver produtos.
     */
    @GET
    public List<Produto> listar(@QueryParam("categoria") String categoria) {
        if (categoria != null && !categoria.isBlank()) {
            return Produto.findByCategoria(categoria);
        }
        return Produto.listAll();
    }

    /**
     * Busca um produto pelo ID.
     * Retorna 404 com JSON {"erro": "Produto não encontrado"} se não existir.
     */
    @GET
    @Path("/{id}")
    public Response buscar(@PathParam("id") Long id) {
        Produto produto = Produto.findById(id);
        if (produto == null) {
            return Response.status(Response.Status.NOT_FOUND)
                    .entity(Map.of("erro", "Produto não encontrado"))
                    .build();
        }
        return Response.ok(produto).build();
    }
}
