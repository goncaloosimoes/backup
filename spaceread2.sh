#!/bin/bash

# Verifica se há mais de dois argumentos
if [ "$#" -gt 2 ]; then
    
    args1=("$@")       # Array com todos os argumentos passados
    concat=""          # Variável para armazenar a concatenação dos argumentos
    dir_backup=""      # Variável para armazenar o segundo diretório
    echo "-----------------------------------------------------------------"
    
    # Remove espaços à esquerda do primeiro argumento
    first_arg="${args1[0]##[[:space:]]*}"
    echo "Primeiro argumento sem espaços à esquerda: '$first_arg'"

    # Começa a concatenação com o primeiro argumento limpo
    concat="$first_arg"
    echo "Argumentos recebidos: ${args1[@]}"

    # Variáveis para controlar o primeiro diretório encontrado
    dir_trabalho=""
    j=1  # Inicializa o índice para o segundo diretório, caso o primeiro seja encontrado imediatamente

    # Verifica se o primeiro argumento é um diretório
    if [ -d "$concat" ]; then
        dir_trabalho="$concat"
        dir_backup="${args1[@]:1}"
        echo "Primeiro diretório encontrado: $dir_trabalho"
        echo "Argumentos restantes atribuídos a dir_backup: '$dir_backup'"
    fi
        # Caso o primeiro argumento não seja um diretório, continua a concatenar
        for ((i = 1; i < ${#args1[@]}; i++)); do

            current_arg="${args1[i]}"  # Argumento atual
            echo "Argumento atual: \"$current_arg\" ponto" 
            
            # Adiciona o argumento atual ao `concat`, preservando espaços com aspas
            new_concat="$concat $current_arg"
            echo "Concatenação atual: \"$new_concat\" ponto"
            concat="$new_concat"
            
            # Verifica se `new_concat` é um diretório válido
            if [ -d "$new_concat" ]; then
                dir_trabalho="$new_concat"  # Atualiza o primeiro diretório válido
                echo "Diretório de trabalho válido encontrado: $new_concat"
                j=$((i + 1))  # Define o índice do próximo elemento
                break
            fi
        done
    

    # Caso não encontre um diretório válido para o primeiro diretório
    if [ -z "$dir_trabalho" ]; then
        echo "Erro: Nenhum diretório válido encontrado para o primeiro diretório."
        exit 1
    fi

    # Forma o segundo diretório com os argumentos restantes a partir de `j`
    dir_backup="${args1[@]:$j}"
    echo "Segundo diretório formado com os argumentos restantes: '$dir_backup'"

    # Exibe os diretórios finais
    echo "Diretório de trabalho: $dir_trabalho"
    echo "Segundo diretório: $dir_backup"

else
    echo "Erro: É necessário fornecer pelo menos três argumentos."
    exit 1
fi
