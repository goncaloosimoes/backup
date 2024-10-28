#!/bin/bash

# Verifica se dir_trabalho e dir_backup foram passadas (tem de existir 2 argumentos no mínimo)
if [ $# -lt 2 ]; then
    echo "Usage: $0 [-c] <dir_trabalho> <dir_backup>"
    exit 1
fi

# Variável para o modo de CHECKING
CHECKING=false

# Verifica se '-c' é o primeiro argumento
if [ $1 == "-c" ]; then
    CHECKING=true
    shift # Remove '-c' da lista de argumentos
fi

# Diretórios passados nos argumentos
dir_trabalho=$1
dir_backup=$2

# Se a diretoria de trabalho não existir o programa acaba
if [ ! -d "$dir_trabalho" ]; then
    echo "ERROR: $dir_trabalho does not exist"
    exit 1
fi

# Verificamos se a diretoria de backup não existe
if [ ! -d "$dir_backup" ]; then
    # Escrevemos o comando no terminal independentemente do valor de CHECKING
    echo "mkdir $dir_backup"
    # Se CHECKING for false executamos o comando
    if [ "$CHECKING" = false ]; then
        mkdir "$dir_backup"
    fi
fi

# Contadores
errors=0
warnings=0
updated=0
copied=0
deleted=0
total_bytes=0

# Função para copiar cada ficheiro de uma diretoria de origem para uma diretoria de destino
copy_file() {
    # Caminho do ficheiro de origem
    local src_file=$1
    # Caminho para o ficheiro de destino
    local dest_file=$2

    # Exibe sempre o comando no terminal
    echo "cp -a $src_file $dest_file"
    
    # Executa apenas se CHECKING for false
    if [ "$CHECKING" = false ]; then
        # Usamos a opção -a para preservar os atributos do ficheiro original
        if cp -a "$src_file" "$dest_file"; then
            # Se a cópia for bem-sucedida, incrementa o contador de copiados
            ((copied++))
            file_size=$(stat -c%s "$src_file")  # Obtém o tamanho do arquivo
            ((total_bytes+=file_size))  # Soma ao total de bytes copiados
        else
            # Se ocorrer um erro na cópia
            echo "ERROR: failed to copy $src_file to $dest_file" >&2
            ((errors++))  # Incrementa o contador de erros
        fi
    else
        # O contador de copiados ainda é incrementado para o modo de verificação
        ((copied++))
        file_size=$(stat -c%s "$src_file")  # Obtém o tamanho do arquivo
        ((total_bytes+=file_size))  # Soma ao total de bytes copiados
    fi
}


shopt -s nullglob  # Para que o loop não inicie se não houver arquivos no diretório de trabalho
# Loop pelos ficheiros no diretório de trabalho
for file in "$dir_trabalho"/*; do
    filename=$(basename "$file")
    backup_file="$dir_backup/$filename"

    # Verifica se o ficheiro já existe na diretória de backup
    if [ -f "$backup_file" ]; then
        # Atualiza apenas se o ficheiro de origem for mais recente
        if [ "$file" -nt "$backup_file" ]; then
            copy_file "$file" "$backup_file"
            ((updated++))  # Incrementa o contador de atualizações
        else
            echo "WARNING: backup entry $backup_file is newer than $file; Should not happen"
            ((warnings++))  # Incrementa o contador de avisos
        fi
    else
        # Se o ficheiro não existe no backup, é copiado para lá
        copy_file "$file" "$backup_file"
    fi
done

# Mensagem do final do backup
echo "While backing up $dir_trabalho: $errors Errors; $warnings Warnings; $updated Updated; $copied Copied ($total_bytes B); $deleted deleted (0 B)"