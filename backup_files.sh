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

export LC_ALL=C

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

# Verifica se dir_backup está dentro de dir_trabalho
if [[ "$dir_backup" == "$dir_trabalho"* ]]; then
    echo "ERROR: The backup directory ($dir_backup) cannot be inside the working directory ($dir_trabalho)."
    ((errors++))
    exit 1
fi

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

    # Exibe o comando que será executado
    echo "cp -a \"$src_file\" \"$dest_file\""

    # Verifica se o modo CHECKING está desativado
    if [ "$CHECKING" = false ]; then
        # Verifica se o arquivo de destino não existe ou se está desatualizado
        if [ ! -e "$dest_file" ]; then
            # Caso seja uma cópia de novo arquivo
            if cp -a "$src_file" "$dest_file"; then
                ((copied++))  # Incrementa contador de cópias
                
                # Calcula e adiciona o tamanho do arquivo copiado
                file_size=$(stat -c%s "$src_file" 2>/dev/null || stat -f%z "$src_file") # Compatível com diferentes SOs
                ((total_bytes_copied+=file_size))  # Soma ao total de bytes copiados
            else
                # Se ocorrer um erro na cópia
                echo "ERROR: failed to copy $src_file to $dest_file" >&2
                ((errors++))  # Incrementa contador de erros
            fi
        elif [ "$src_file" -nt "$dest_file" ]; then
            # Caso seja uma atualização
            if cp -a "$src_file" "$dest_file"; then
                ((updated++))  # Incrementa contador de atualizações
            else
                # Se ocorrer um erro na atualização
                echo "ERROR: failed to update $src_file to $dest_file" >&2
                ((errors++))  # Incrementa contador de erros
            fi
        fi
    else
        # Simulação no modo CHECKING
        if [ ! -e "$dest_file" ]; then
            ((copied++))  # Incrementa contador de cópias (modo CHECKING)
            # Calcula o tamanho do arquivo copiado
            file_size=$(stat -c%s "$src_file" 2>/dev/null || stat -f%z "$src_file")
            ((total_bytes_copied+=file_size))  # Soma ao total de bytes copiados
        elif [ "$src_file" -nt "$dest_file" ]; then
            ((updated++))  # Incrementa contador de atualizações (modo CHECKING)
        fi
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
            elif [ "$backup_file" -nt "$file" ]; then
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