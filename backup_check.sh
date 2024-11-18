#!/bin/bash

dir_trabalho=$1
dir_backup=$2

# Função de ajuda de uso
usage() {
    echo "Usage: $0 <dir_trabalho> <dir_backup>"
    exit 1
}

# Valida se o número de argumentos é adequado
if [ "$#" -lt 2 ]; then
    echo "ERROR: need at least 2 arguments: working directory and backup directory"
    ((errors++))
    usage
fi

# Função para verificar se um diretório existe e é válido
check_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 1  # Diretório não existe
    fi
    return 0  # Diretório existe
}

# Verifica se os diretórios existem
check_directory "$dir_trabalho"
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_trabalho' does not exist or it is not a directory"
    usage
fi

check_directory "$dir_backup"
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_backup' does not exist or it is not a directory"
    usage
fi

# Função para calcular o MD5 de um arquivo
get_md5() {
    md5sum "$1" | cut -d' ' -f1
}

# Verifica arquivos no diretório de trabalho
find "$dir_trabalho" -type f | while read -r src_file; do
    # Caminho relativo do arquivo
    relative_path="${src_file#$dir_trabalho/}"
    bak_file="$dir_backup/$relative_path"

    # Garante que o subdiretório correspondente exista no backup
    if [ ! -d "$(dirname "$bak_file")" ]; then
        mkdir -p "$(dirname "$bak_file")"
    fi

    # Verifica se o arquivo existe no backup
    if [ -f "$bak_file" ]; then
        src_md5=$(get_md5 "$src_file")
        bak_md5=$(get_md5 "$bak_file")

        # Compara os hashes MD5
        if [ "$src_md5" != "$bak_md5" ]; then
            echo "$src_file $bak_file differ."
        fi
    fi
done
