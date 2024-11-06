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
        c) CHECKING=true ;;
        b) IGNORE_FILE="$OPTARG" ;;
        r) REGEX="$OPTARG" ;;
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

# Função para copiar arquivos e diretórios recursivamente
copy_item() {
    local src_item="$1"
    local dest_item="$2"

    # Verifica se o item deve ser ignorado
    if should_ignore "$src_item"; then
        echo "Ignoring $src_item"
        return
    fi

    # Verifica se a expressão regular foi definida e se o item não corresponde
    if [[ -n "$REGEX" && ! "$(basename "$src_item")" =~ $REGEX ]]; then
        echo "Skipping $src_item due to regex filter"
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
            # Ignora arquivos ocultos
            if [[ "$item" != .* ]]; then
                copy_item "$item" "$dest_item/$(basename "$item")"
            fi
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
