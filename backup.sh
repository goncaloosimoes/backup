#!/bin/bash

# Função de ajuda de uso
usage() {
    echo "Usage: $0 [-c] [-b tfile] [-r regexpr] <dir_trabalho> <dir_backup>"
    exit 1
}

# Variáveis para o modo de CHECKING (-c), ficheiro de ignorados (-b) e expressão regular (-r)
CHECKING=false
IGNORE_FILE=""
REGEX=""

export LC_ALL=C

# Função que carrega a lista de arquivos a serem ignorados
load_ignore_paths() {
    if [ -f "$IGNORE_FILE" ]; then
        mapfile -t ignore_paths < "$IGNORE_FILE"
    fi
}

# Função para verificar se um item deve ser ignorado
should_ignore() {
    local path="$1"
    for ignore in "${ignore_paths[@]}"; do
        if [[ "$path" == "$ignore" ]]; then
            return 0  # Ignorar
        fi
    done
    return 1  # Não ignorar
}

# Função para verificar se um diretório existe e é válido
check_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 1  # Diretório não existe
    fi
    return 0  # Diretório existe
}

# Processamento das opções -c, -b e -r
while getopts ":cb:r:" opt; do
    case $opt in
        c) CHECKING=true;;
        b) IGNORE_FILE="$OPTARG"
            # Carrega a lista de arquivos a serem ignorados
            load_ignore_paths;;
        r) REGEX="$OPTARG"
            # Validação da expressão regular
            if [[ -z "$REGEX" ]]; then
                echo "ERROR: Regex is not defined"
                exit 1
            fi;;

        ?) usage;;
    esac
done

# Remove as opções processadas
shift $((OPTIND - 1))

# Valida se o número de argumentos é adequado
if [ "$#" -lt 2 ]; then
    echo "ERROR: need at least 2 arguments: working directory and backup directory"
    usage
fi

# Normalização e atribuição dos diretórios dir_trabalho e dir_backup
args=("$@")
dir_trabalho="${args[0]}"
dir_backup="${args[1]}"

# Verifica se dir_backup está dentro de dir_trabalho
if [[ "$dir_backup" == "$dir_trabalho"* ]]; then
    echo "ERROR: The backup directory ($dir_backup) cannot be inside the working directory ($dir_trabalho)."
    ((errors++))
    exit 1
fi

# Verificação do diretório de trabalho
check_directory "$dir_trabalho"
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_trabalho' does not exist or it is not a directory"
    exit 1
fi

# Verificação do diretório de backup
check_directory "$dir_backup"
if [[ $? -eq 1 ]]; then
    # Se o diretório não existe, criamos
    echo "mkdir -p $dir_backup"
    if [ "$CHECKING" = false ]; then
        # Se o checking for false executamos o comando
        if ! mkdir -p "$dir_backup"; then
            echo "ERROR: $dir_backup could not be created."
            exit 1
        fi
    fi
fi

copy_item() {   
    local src_item="$1"                 # Caminho do arquivo de origem
    local dest_item="$2"                # Caminho do arquivo de destino

    echo "cp -a \"$src_item\" \"$dest_item\""   # Exibe o comando de cópia no terminal, para monitoramento

    # Verifica se o item deve ser ignorado ou se não corresponde ao filtro de regex
    if should_ignore "$src_item" || [[! -n "$REGEX" && ! "$(basename "$src_item")" =~ $REGEX ]]; then
        echo "Ignoring $src_item due to regex or ignore file"
        return
    fi

    # Verifica se o item de origem é um diretório
    if [ -d "$src_item" ]; then
        # Verifica se o diretório backup correspondente não existe
        if [ ! -d "$dest_item" ]; then
            echo "mkdir -p $dest_item"
            # Se não estiver no modo CHECKING, cria o diretório de destino
            if [ "$CHECKING" = false ]; then
                mkdir -p "$dest_item"
            fi
        fi
    else    # Se for um ficheiro, verifica se o item de destino já existe
        if [ ! -e "$dest_item" ]; then
            # Caso o arquivo de destino não exista, considera como um novo arquivo copiado
            if [ "$CHECKING" = false ]; then
                if cp -a "$src_item" "$dest_item"; then
                    # Anotamos o tamanho do ficheiro antes de apagá-lo (-c%s para linux e %f%z para macOS)
                    item_size=$(stat -c%s "$dest_item" 2>/dev/null || stat -f%z "$dest_item")
                else
                    # Se ocorrer um erro na cópia
                    echo "ERROR: failed to copy $src_item to $dest_item" >&2
                fi
            else
                # Anotamos o tamanho do ficheiro antes de apagá-lo (-c%s para linux e %f%z para macOS)
                item_size=$(stat -c%s "$dest_item" 2>/dev/null || stat -f%z "$dest_item")
            fi
        elif [ "$src_item" -nt "$dest_item" ]; then
            # Caso o arquivo de destino exista, mas o arquivo de origem seja mais recente, considera como atualizado
            if [ "$CHECKING" = false ]; then
                if cp -a "$src_item" "$dest_item"; then
                    # Anotamos o tamanho do ficheiro antes de apagá-lo (-c%s para linux e %f%z para macOS)
                    item_size=$(stat -c%s "$dest_item" 2>/dev/null || stat -f%z "$dest_item")
                else
                    echo "ERROR: failed to update $src_item to $dest_item" >&2
                fi
            else
                # Simula a atualização e calcula o tamanho do arquivo
                # Anotamos o tamanho do ficheiro antes de apagá-lo (-c%s para linux e %f%z para macOS)
                item_size=$(stat -c%s "$dest_item" 2>/dev/null || stat -f%z "$dest_item")
            fi
        fi
    fi
}

delete_item() {
    # Caminho para o ficheiro ou diretório de destino que desejamos apagar
    local dest="$1"

    if [ -e "$dest" ]; then  # Apenas processa se o caminho existir
        # Determina o tamanho do arquivo/diretório antes de apagar
        if [ -f "$dest" ]; then
            item_size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest")  # Linux ou macOS
            rm_command="rm \"$dest\""
        elif [ -d "$dest" ]; then
            item_size=$(du -sb "$dest" 2>/dev/null | cut -f1 || du -sk "$dest" | cut -f1)
            rm_command="rm -r \"$dest\""
        else
            echo "WARNING: '$dest' is not a file or a directory?"
            return
        fi

        # Print do comando de remoção do item consoante a sua natureza (ficheiro/diretoria)
        echo "$rm_command"

        if [ "$CHECKING" = false ]; then
            # Apagar o arquivo ou diretório usando a string armazenada anteriormente
            if ! eval $rm_command; then
                echo "ERROR: Failed to delete $dest" >&2
            fi
        fi
    fi
}

# Para que o loop não inicie se não houver arquivos no diretório de trabalho
shopt -s nullglob
shopt -s dotglob  # Habilita o glob para trabalhar também com arquivos ocultos

# Loop recursivo pelos itens no diretório de trabalho
while read -r item; do
    # Caminho relativo no diretório de trabalho
    relative_path="${item#$dir_trabalho/}"
    backup_item="$dir_backup/$relative_path"  # Alterado de backup_file para backup_item

    if [ -d "$item" ]; then
        # Se o item é um diretório, cria o diretório correspondente no backup se ele ainda não existir
        if [ ! -d "$backup_item" ]; then
            mkdir -p "$backup_item"
            echo "mkdir -p $backup_item"
        fi
    elif [ -f "$item" ]; then
        # Se o item é um arquivo
        if [ -f "$backup_item" ]; then
            # Atualiza apenas se o arquivo de origem for mais recente
            if [ "$item" -nt "$backup_item" ]; then
                copy_item "$item" "$backup_item"
            else
                echo "WARNING: backup entry $backup_item is newer than $item; Should not happen"
            fi
        else
            # Se o arquivo não existe no backup, é copiado
            copy_item "$item" "$backup_item"
        fi
    fi
done < <(find "$dir_trabalho" -mindepth 1)

# Loop recursivo para verificar arquivos presentes no backup
while read -r backup_item; do
    # Obtém o caminho relativo ao backup para mapear ao diretório de trabalho
    relative_path="${backup_item#$dir_backup/}"
    item="$dir_trabalho/$relative_path"

    if [ -f "$backup_item" ]; then
        # Verifica se o arquivo correspondente no diretório de trabalho existe
        if [ ! -e "$item" ]; then
            delete_item "$backup_item"  # Apaga o arquivo se ele não existir no dir_trabalho
        fi
    elif [ -d "$backup_item" ]; then
        # Verifica se o diretório correspondente no diretório de trabalho existe
        if [ ! -d "$item" ]; then
            delete_item "$backup_item"  # Apaga o diretório se não existir no dir_trabalho
        fi
    fi
done < <(find "$dir_backup" -mindepth 1)