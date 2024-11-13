#!/bin/bash

# Verifica se há mais de dois argumentos # Lida com argumentos e concatena quando necessário
if [ "$#" -gt 2 ]; then
    
    args1=("$@")  # Array com todos os argumentos passados
    echo $args1
    args=("" "")  # Array com dois elementos :diretorios

    # Índice args
    j=0
    concat=""

    # Itera sobre os argumentos
    for ((i = 0; i < ${#args1[@]}; i++)); do
        current_arg="${args1[i]}"  # Pega o argumento atual
        echo $current_arg 
        # Verifica se o argumento começa com '/', '.' ou '..'
        if [[ "$current_arg" =~ ^/ ]] || [[ "$current_arg" =~ ^\.{1,2} ]]; then
            # Se houver conteúdo no `concat`, salva no array `args`
            if [ -n "$concat" ] && [ -d "$concat" ]; then

                    args[$j]="$concat"
                    ((j++))
                    concat=""
            
            else
                    concat="$concat $current_arg"
            fi
            # Armazena o argumento de diretório atual diretamente
            args[$j]="$current_arg"
            ((j++))
        else
            # Concatena o argumento atual à variável `concat` com espaço
            concat="$concat $current_arg"
            
            
        fi
    done

    # Adiciona qualquer conteúdo restante de `concat` ao array `args`, acumulando no último elemento válido
    if [ -n "$concat" ] && [ "${args[1]}" != "" ]; then
        args[$j-1]="${args[$j-1]} $concat"
    fi

    # Após o loop, os dois primeiros argumentos devem ser diretórios válidos
    dir_trabalho="${args[0]}"
    dir_backup="${args[1]}"
    echo "$args"
    # Exibe os diretórios finais
    echo "Diretório de trabalho: $dir_trabalho"
    echo "Diretório de backup: $dir_backup"


fi
