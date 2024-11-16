#!/bin/bash

dir_trabalho=$1
dir_backup=$2

# Função para verificar se um diretório existe e é válido
check_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 1  # Diretório não existe
    fi
    return 0  # Diretório existe
}

check_directory $dir_trabalho
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_trabalho' does not exist or it is not a directory"
    exit 1
fi

check_directory $dir_backup
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_backup' does not exist or it is not a directory"
    exit 1
fi

# Função para calcular o MD5 de um arquivo
get_md5() {
    md5sum "$1" | cut -d' ' -f1
}

for src_file in "$dir_trabalho"/*; do
    if [ -f "$src_file" ]; then
        filename=$(basename "$src_file")
        bak_file="$dir_backup/$filename"

        # Verifica se o arquivo correspondente existe no diretório backup
        if [ -f "bak_file" ]; then
            src_md5=$(get_md5 "$src_file")
            bak_md5=$(get_md5 "$bak_file")

            # Compara os hashes MD5
            if [ "$src_md5" != "$bak_md5" ]; then
                echo "$src_file $bak_file differ."
            fi
        fi
    fi
done
