#!/bin/bash

# Contadores de ficheiros e ocorrências de erros/avisos
errors=0
warnings=0
updated=0
copied=0
deleted=0
# Contadores de memória
total_bytes_copied=0
total_bytes_deleted=0

# Função para exibir a mensagem de uso
usage() {
    echo "Uso: $0 [-c] [-b ignore_file] [-r regexpr] <dir_trabalho> <dir_backup>"
}

# Verifica se pelo menos dir_trabalho e dir_backup foram passados
if [ $# -lt 2 ]; then
    usage
    echo ""
    exit 1
fi

# Variáveis para modo de verificação (-c), arquivo de ignorados (-b), e expressão regular (-r)
CHECKING=false
IGNORE_FILE=""
REGEX=""

# Processa as opções da linha de comando
while getopts ":cb:r:" opt; do
    case $opt in
        c) CHECKING=true ;;
        b) IGNORE_FILE="$OPTARG" ;;
        r) REGEX="$OPTARG" ;;
        *) usage; exit 1 ;;
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
    echo "mkdir -p $dir_backup"
    if [ "$CHECKING" = false ]; then
        mkdir -p "$dir_backup"
    fi
fi

# Carrega os caminhos a serem ignorados
load_ignore_paths() {
    if [ -f "$IGNORE_FILE" ]; then
        mapfile -t ignore_paths < "$IGNORE_FILE"
    fi
}

# Função para verificar se um item deve ser ignorado
should_ignore() {
    local item=$1
    for ignore_path in "${ignore_paths[@]}"; do
        if [[ "$item" == "$ignore_path" ]]; then
            return 0
        fi
    done
    if [[ -n "$REGEX" ]] && [[ "$item" =~ $REGEX ]]; then
        return 0
    fi
    return 1
}

# Função para copiar arquivos e diretórios recursivamente
copy_item() {
    local src_item=$1
    local dest_item=$2

    # Verifica se o item deve ser ignorado
    if should_ignore "$src_item"; then
        echo "Ignoring $src_item"
        return
    fi

    # Verifica se é um diretório
    if [ -d "$src_item" ]; then
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
        if [ "$CHECKING" = false ]; then
            if cp -a "$src_item" "$dest_item"; then
                ((copied++))
                file_size=$(stat -c%s "$src_item" 2>/dev/null)
                ((total_bytes_copied+=file_size))
            else
                echo "ERROR: failed to copy $src_item to $dest_item" >&2
                ((errors++))
            fi
        else
            ((copied++))
            file_size=$(stat -c%s "$src_item" 2>/dev/null)
            ((total_bytes_copied+=file_size))
        fi
    fi
}

# Função para deletar arquivos do backup que não estão mais no diretório de trabalho
delete_item() {
    local dest_item=$1

    echo "rm -r \"$dest_item\""
    if [ "$CHECKING" = false ]; then
        if rm -r "$dest_item"; then
            ((deleted++))
            file_size=$(stat -c%s "$dest_item" 2>/dev/null)
            ((total_bytes_deleted+=file_size))
            echo "Deleted $dest_item ($file_size bytes)"
        else
            echo "ERROR: failed to delete $dest_item" >&2
            ((errors++))
        fi
    else
        ((deleted++))
        file_size=$(stat -c%s "$dest_item" 2>/dev/null)
        ((total_bytes_deleted+=file_size))
    fi
}

# Carrega os caminhos a serem ignorados
load_ignore_paths

# Inicia o processo de cópia
copy_item "$dir_trabalho" "$dir_backup"

# Loop para encontrar e deletar arquivos órfãos no backup
for backup_file in "$dir_backup"/*; do
    filename=$(basename "$backup_file")
    source_file="$dir_trabalho/$filename"

    # Se o arquivo não existe mais no diretório de trabalho, deleta do backup
    if [ ! -e "$source_file" ]; then
        delete_item "$backup_file"
    fi
done

# Mensagem final do backup
echo "While backing up $dir_trabalho: $errors Errors; $warnings Warnings; $updated Updated; $copied Copied ($total_bytes_copied bytes); $deleted Deleted ($total_bytes_deleted bytes)"
