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
    echo "Usage: $0 [-c] <dir_trabalho> <dir_backup>"
    exit 1
}

# Variável para o modo de CHECKING
CHECKING=false

# Verifica o parâmetro -c como opcional
if [ "$1" == "-c" ]; then
    CHECKING=true
    shift # Remove '-c' da lista de argumentos
fi

# Verifica se temos pelo menos dois argumentos após remover -c
if [ $# -lt 2 ]; then
    usage
fi

# Diretórios passados nos argumentos
dir_trabalho="$1"
dir_backup="$2"

# Se a diretoria de trabalho não existir o programa acaba
if [ ! -d "$dir_trabalho" ]; then
    echo "ERROR: $dir_trabalho does not exist or it is not a directory"
    ((errors++))
    exit 1
fi

# Verificamos se a diretoria de backup não existe, e caso não exista criamo-lo
if [ ! -d "$dir_backup" ]; then
    # Escrevemos o comando no terminal independentemente do valor de CHECKING
    echo "mkdir -p \"$dir_backup\""

    # Se CHECKING for false tentamos executar o comando
    if [ "$CHECKING" = false ]; then
        mkdir -p "$dir_backup"
        # Verificar se a criação do diretório foi bem sucedida
        if [ $? -ne 0 ]; then
            echo "ERROR: failed to create backup directory $dir_backup" >&2
            ((errors++))
            exit 1
        fi
    fi
fi

# Função para copiar cada ficheiro de uma diretoria de origem para uma diretoria de destino
copy_file() {
    # Caminho do ficheiro de origem
    local src_file="$1"
    # Caminho para o ficheiro de destino
    local dest_file="$2"

    # Exibe sempre o comando no terminal
    echo "cp -a \"$src_file\" \"$dest_file\""
    
    # Verifica se o arquivo não existe no backup ou se o arquivo de origem é mais recente
    if [ "$CHECKING" = false ]; then
        if cp -a "$src_file" "$dest_file"; then
            # Verifica se o arquivo foi realmente copiado ou atualizado
            if [ ! -f "$dest_file" ] || [ "$src_file" -nt "$dest_file" ]; then
                ((updated++))  # Contagem de atualizações
            else
                ((copied++))  # Contagem de cópias (novos arquivos)
            fi

            # Adiciona o tamanho do arquivo ao total de bytes copiados
            file_size=$(stat -c%s "$src_file" 2>/dev/null || stat -f%z "$src_file") # Compatibilidade para obter tamanho do ficheiro
            ((total_bytes_copied+=file_size))  # Soma ao total de bytes copiados
        else
            # Se ocorrer um erro na cópia
            echo "ERROR: failed to copy $src_file to $dest_file" >&2
            ((errors++))  # Incrementa o contador de erros
        fi
    else
        # No modo de verificação, apenas incrementa as contagens
        if [ ! -f "$dest_file" ]; then
            ((copied++))  # Contagem de cópias no modo de verificação
        else
            ((updated++))  # Contagem de atualizações no modo de verificação
        fi

        # Adiciona o tamanho do arquivo ao total de bytes copiados (mesmo no modo de verificação)
        file_size=$(stat -c%s "$src_file" 2>/dev/null || stat -f%z "$src_file") # Compatibilidade para obter tamanho
        ((total_bytes_copied+=file_size))  # Soma ao total de bytes copiados
    fi
}

# Função para apagar um ficheiro da diretoria backup se ele já não existir na diretoria de trabalho
delete_file() {
    # Caminho para o ficheiro de destino que desejamos apagar
    local dest_file="$1"
    echo "rm \"$dest_file\""

    # Se CHECKING for false, corremos os comandos
    if [ "$CHECKING" = false ]; then
        if [ -f "$dest_file" ]; then  # Apenas apaga se for ficheiro
            # Anotamos o tamanho do ficheiro antes de apagá-lo (-c%s para linux e %f%z para macOS)
            file_size=$(stat -c%s "$dest_file" 2>/dev/null || stat -f%z "$dest_file")
            if rm "$dest_file"; then
                ((deleted++)) # Incrementa o número de ficheiros apagados
                ((total_bytes_deleted+=file_size))
            else
                echo "ERROR: failed to delete $dest_file" >&2
                ((errors++))
            fi
        fi
    else
        # Caso o checking seja verdadeiro fazemos o mesmo procedimento caso seja um ficheiro, sem executar comandos
        if [ -f "$dest_file" ]; then
            file_size=$(stat -c%s "$dest_file" 2>/dev/null || stat -f%z "$dest_file") # Calcula o tamanho do ficheiro
            # O contador de apagados ainda é incrementado no modo de verificação
            ((deleted++))
            ((total_bytes_deleted+=file_size)) # Soma ao total de bytes apagados da diretoria backup
        fi
    fi
}

# Para que o loop não inicie se não houver arquivos no diretório de trabalho
shopt -s nullglob
shopt -s dotglob  # Habilita o glob para trabalhar também com arquivos ocultos

# Loop pelos ficheiros no diretório de trabalho
for file in "$dir_trabalho"/*; do
    # Verifica se o item é um ficheiro
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        backup_file="$dir_backup/$filename"

        # Verifica se o ficheiro já existe na diretoria de backup
        if [ -f "$backup_file" ]; then
            # Atualiza apenas se o ficheiro de origem for mais recente 
            if [ "$file" -nt "$backup_file" ] || [ ! -e "$backup_file" ]; then
                copy_file "$file" "$backup_file"
                ((updated++))  # Incrementa o contador de atualizações
            elif [ "$file" -nt "$backup_file" ]; then
                echo "WARNING: backup entry $backup_file is newer than $file; Should not happen"
                ((warnings++))  # Incrementa o contador de avisos
            fi
        else
            # Se o ficheiro não existe no backup, é copiado para lá
            copy_file "$file" "$backup_file"
        fi
    fi
done

# Verifica arquivos presentes no backup
for backup_file in "$dir_backup"/*; do
    # Verifica se o item no backup é um ficheiro
    if [ -f "$backup_file" ]; then
        filename=$(basename "$backup_file")
        file="$dir_trabalho/$filename"

        # Se o ficheiro não existe mais no diretório de trabalho, fazemos delete do ficheiro no backup
        if [ ! -e "$file" ]; then
            delete_file "$backup_file"
        fi
    fi
done

# Mensagem do final do backup
echo "While backing up $dir_trabalho: $errors Errors; $warnings Warnings; $updated Updated; $copied Copied ($total_bytes_copied B); $deleted deleted ($total_bytes_deleted B)"