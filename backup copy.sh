#!/bin/bash

# Contadores
errors=0
warnings=0
updated=0
copied=0
deleted=0
total_bytes=0

usage() {
    echo "Utilizacao: $0 [-c] [-b tfile] [-r regexpr] <dir_trabalho> <dir_backup> "  
}

# Variáveis para o modo de CHECKING (-c), arquivo de ignorados(-b) e expressão regular(-r)
CHECKING=false
IGNORE_FILE=""
REGEX=""

while getopts ":cb:r:" opt; do #opt process
    case $opt in
        c) CHECKING=true;;

        b) IGNORE_FILE="$OPTARG" # Verificaçao e Preparaçao da Lista de ficheiros a serem ignorados
        #verificar se tem ficheiro , se este e valido e colocar nomes em array prontos a usar na main
        should_ignore() {
                local path="$1"
                for ignore in "${ignore_paths[@]}"; do
                    if [[ "$path" == $ignore ]]; then
                        return 0  # Ignorar
                    fi
                done
                return 1  # Não ignorar
            };;
        r) REGEX="$OPTARG" ;; # Expressão regular
                    # Verifica se a expressão regular foi definida e é válida
            if [[ -z "$REGEX" ]]; then
                echo "Invalid Regular Expression: REGEX is not set"
                ((errors++))
                return
            fi
            # Testa se o REGEX é válido usando o grep
            echo "" | grep -E "$REGEX" >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo "Invalid Regular Expression: '$REGEX' is not a valid regex"
                ((errors++))
                return
            fi
 
        ?) usage 
        exit 1;;
    esac
done
# Remove as opções processadas
shift $((OPTIND - 1))

#verficia se a diretoria é vialida
VerificaDir() {
    dir_trabalho="$1"
    if [ ! -d "$dir_trabalho" ]; then
        ((errors++))
        return 0
    fi
    return 1
}
#verifica se a diretoria de destino esta dentro a diretoria a de  funcao criar 


#verificaçao e normalizaçao dos restantes argumentos
#verifica se sao menos que dois 
if [$@ -lt 2 ];then
    echo "Erro: Diretórios 'dir_trabalho' e 'dir_backup' são obrigatórios."
    ((errors++))
    exit1
fi
#verifica se sao exatamente dois 
if [$@ -e 2 ];then
    dir_trabalho=$1
    dir_backup=$2

    VerificaDir "$dir_trabalho"
    ret=$?
    if [[ $ret == 0 ]] 
        echo "O diretório $? não existe ou não é válido1"

    VerificaDir "$dir_backup"
    ret=$?
# Verificamos se a diretoria de backup não existe
    if [ $ret == 0]; then
        # Escrevemos o comando no terminal independentemente do valor de CHECKING
        echo "mkdir $dir_backup"
        # Se CHECKING for false executamos o comando
        if [ "$CHECKING" = false ]; then
            mkdir "$dir_backup"
        fi
    fi
else 
do nothing 
fi

#verifica se sao mais dois (espaços)
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
            if [ -n "$concat" ]; then
                args[$j]="$concat"
                ((j++))
                concat=""
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

    # Exibe os diretórios finais
    echo "Diretório de trabalho: $dir_trabalho"
    echo "Diretório de backup: $dir_backup"
fi

    #verifica diretoria 
#caso backuop nao existe cria 
    
# neste ponto é suposto termos acesso a:
#- dir_trabalho valida 
#- dir_backup  valida criada caso nao exista 
#- array com nomes de ficheiros a ignorar(caso opt)
#- expressao regex valida (caso opt) 
#- checking variable 








            # Verifica se o item não corresponde ao REGEX
            if ! echo "$(basename "$src_item")" | grep -qE "$REGEX"; then
                echo "Skipping $src_item due to regex filter"
                return
            fi
            





# Função para carregar os caminhos a serem ignorados
load_ignore_paths() {
    if [ -f "$IGNORE_FILE" ]; then
        mapfile -t ignore_paths < "$IGNORE_FILE"
    fi
}

# Função para copiar arquivos e diretórios recursivamente
copy_item() {


    # Verifica se o item deve ser ignorado
    if should_ignore "$src_item"; then
        echo "Ignoring $src_item"
        return
    fi

    # Verifica se é um diretório
    if [ -d "$src_item" ]; then
        # Cria o diretório de destino, se não existir
        if [ "$CHECKING" = false ]; then
            mkdir -p "$dest_item"
        fi

        # Loop para copiar todos os itens dentro do diretório
        for item in "$src_item"/*; do
            copy_item "$item" "$dest_item/$(basename "$item")"
        done
    else
        # Trata arquivos
        echo "cp -a \"$src_item\" \"$dest_item\""
        # Executa a cópia se CHECKING for false
        if [ "$CHECKING" = false ]; then
            if cp -a "$src_item" "$dest_item"; then
                ((copied++))
                file_size=$(stat -c%s "$src_item" 2>/dev/null)
                ((total_bytes+=file_size))
                echo "Copied $src_item ($file_size bytes)"
            else
                echo "ERROR: failed to copy $src_item to $dest_item" >&2
                ((errors++))
            fi
        else
            # Incrementa o contador no modo de verificação
            ((copied++))
            file_size=$(stat -c%s "$src_item" 2>/dev/null)
            ((total_bytes+=file_size))
            echo "Checked $src_item ($file_size bytes)"
        fi
    fi
}

# Carrega os caminhos a serem ignorados
load_ignore_paths

# Inicia o processo de cópia
copy_item "$dir_trabalho" "$dir_backup"

# Mensagem do final do backup
echo "While backing up $dir_trabalho: $errors Errors; $warnings Warnings; $updated Updated; $copied Copied ($total_bytes bytes); $deleted Deleted (0 bytes)"
