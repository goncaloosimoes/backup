#!/bin/bash

# Contadores
errors=0
warnings=0
updated=0
copied=0
deleted=0
total_bytes=0

# Função para exibir a mensagem de uso
usage() {
    echo "Uso: $0 [-c] [-b tfile] [-r regexpr] <dir_trabalho> <dir_backup>"
    exit 1
}

# Verifica se dir_trabalho e dir_backup foram passadas
if [ $# -lt 2 ]; then
    usage
fi

# Variáveis para o modo de CHECKING, arquivo de ignorados e expressão regular
CHECKING=false
IGNORE_FILE=""
REGEX=""

# Processa as opções da linha de comando
while getopts ":cb:r:" opt; do
    case $opt in
        c) CHECKING=true
        echo "sfaijfij"
            #variaveis = "$#"
            src_item="$1"
            dest_item="$2"
        ;;
        b) IGNORE_FILE="$OPTARG" # Lista de ficheiros a serem ignorados
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

            # Verifica se o item não corresponde ao REGEX
            if ! echo "$(basename "$src_item")" | grep -qE "$REGEX"; then
                echo "Skipping $src_item due to regex filter"
                return
            fi
            
            # Função para verificar se um caminho deve ser ignorado
            should_ignore() {
                local path="$1"
                for ignore in "${ignore_paths[@]}"; do
                    if [[ "$path" == $ignore ]]; then
                        return 0  # Ignorar
                    fi
                done
                return 1  # Não ignorar
            }
                file_Ignore=$1
                src_item=$2
                dest_item=$3
            ;;
        r) REGEX="$OPTARG" ;; # Expressão regular
        *) usage ;;
    esac
done

# Remove as opções processadas
shift $((OPTIND - 1))

# Diretórios passados nos argumentos
dir_trabalho=$1
dir_backup=$2

# Se a diretoria de trabalho não existir, o programa acaba
if [ ! -d "$dir_trabalho" ]; then
    echo "ERROR: $dir_trabalho does not exist"
    ((errors++))
    exit 1
fi

# Verifica se a diretoria de backup não existe
if [ ! -d "$dir_backup" ]; then
    echo "mkdir $dir_backup"
    if [ "$CHECKING" = false ]; then
        mkdir -p "$dir_backup"
    fi
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
