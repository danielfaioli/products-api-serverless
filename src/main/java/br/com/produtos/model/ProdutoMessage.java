package br.com.produtos.model;

import java.math.BigDecimal;

/**
 * DTO para mensagens publicadas no Azure Service Bus pelo front end.
 * O campo action determina a operação: CREATE | UPDATE | DELETE
 */
public class ProdutoMessage {

    /** Operação desejada: "CREATE", "UPDATE" ou "DELETE" */
    public String action;

    /** Obrigatório para UPDATE e DELETE */
    public Long id;

    public String nome;
    public BigDecimal preco;
    public String categoria;
}
