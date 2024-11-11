#!/bin/bash

# Verifica se há mais de dois argumentos
if [ "$#" -gt 2 ]; then
    # Lida com argumentos e concatena quando necessário
    args=("$@")  # Cria um array com todos os argumentos passados

    # Itera sobre os argumentos, exceto o último
    for ((i = 0; i < ${#args[@]} - 1; i++)); do
        current_arg="${args[i]}"         # Pega o argumento atual
        next_arg="${args[i+1]}"           # Pega o próximo argumento

        # Se o próximo argumento não começa com '/', '.' ou '..', concatena com o atual
        if [[ ! "$next_arg" =~ ^/ ]] && [[ ! "$next_arg" =~ ^\. ]] && [[ ! "$next_arg" =~ ^\.\. ]]; then
            # Concatena os argumentos com um espaço e substitui o argumento atual
            args[i]="$current_arg $next_arg"

            # Remove o próximo argumento do array
            unset "args[i+1]"

            # Reindexa o array para ajustar o próximo índice corretamente
            args=("${args[@]}")
        fi
    done

    # Após o loop, os dois primeiros argumentos devem ser diretórios válidos
    dir_trabalho="${args[0]}"
    dir_backup="${args[1]}"



    # Exibe os diretórios finais
    echo "Diretório de trabalho: $dir_trabalho"
    echo "Diretório de backup: $dir_backup"
else
    echo "Erro: É necessário fornecer pelo menos três argumentos."
    exit 1
fi
