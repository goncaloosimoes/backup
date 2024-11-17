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

usage() {
    echo "Usage: $0 [-c] [-b tfile] [-r regexpr] <dir_trabalho> <dir_backup>"
    exit 1
}

# Variáveis para o modo de CHECKING (-c), ficheiro de ignorados (-b) e expressão regular (-r)
CHECKING=false
IGNORE_FILE=""
REGEX=""

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
                ((errors++))
                exit 1
            fi
            echo "" | grep -E "$REGEX" >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo "ERROR:'$REGEX' is not a valid regex"
                ((errors++))
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
    ((errors++))
    exit 1
fi

# Normalização e atribuição dos diretórios dir_trabalho e dir_backup
args=("$@")
dir_trabalho="${args[0]}"
dir_backup="${args[1]}"

# Verificação do diretório de trabalho
check_directory "$dir_trabalho"
if [[ $? -eq 1 ]]; then
    echo "ERROR: '$dir_trabalho' does not exist or it is not a directory"
    ((errors++))
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
            ((errors++))
            exit 1
        fi
    fi
fi

copy_item() {
    local src_item="$1"                 # Caminho do arquivo de origem
    local dest_item="$2"                # Caminho do arquivo de destino

    echo "cp -a \"$src_item\" \"$dest_item\""   # Exibe o comando de cópia no terminal, para monitoramento

    # Verifica se o item deve ser ignorado ou se não corresponde ao filtro de regex
    if should_ignore "$src_item" || [[ -n "$REGEX" && ! "$(basename "$src_item")" =~ $REGEX ]]; then
        echo "Ignoring $src_item due to regex or ignore file"
        return
    fi

    # Verifica se o item de origem é um diretório
    if [ -d "$src_item" ]; then
        # Cria o diretório de destino, se necessário
        echo "mkdir -p $dest_item"
        if [ "$CHECKING" = false ]; then
            mkdir -p "$dest_item"
        fi
    else    # Se for um ficheiro, verifica se o item de destino já existe
        item_size=$(stat -c%s "$src_item" 2>/dev/null || stat -f%z "$src_item")
        
        if [ ! -e "$dest_item" ]; then
            # Caso o arquivo de destino não exista, considera como um novo arquivo copiado
            if [ "$CHECKING" = false ]; then
                if cp -a "$src_item" "$dest_item"; then
                    ((copied++))  # Incrementa contador de arquivos copiados
                    ((total_bytes_copied+=item_size))
                else
                    # Se ocorrer um erro na cópia
                    echo "ERROR: failed to copy $src_item to $dest_item" >&2
                    ((errors++))  # Incrementa o contador de erros
                fi
            else
                ((copied++)) # Incrementa contador de arquivos copiados no modo checking
                ((total_bytes_copied+=item_size))
            fi
        elif [ "$src_item" -nt "$dest_item" ]; then
            # Caso o arquivo de destino exista, mas o arquivo de origem seja mais recente, considera como atualizado
            if [ "$CHECKING" = false ]; then
                if cp -a "$src_item" "$dest_item"; then
                    ((updated++))  # Incrementa contador de arquivos atualizados
                    ((total_bytes_copied+=item_size))
                else
                    echo "ERROR: failed to update $src_item to $dest_item" >&2
                    ((errors++))  # Incrementa contador de erros
                fi
            else
                ((updated++))  # Incrementa contador de arquivos atualizados
                ((total_bytes_copied+=item_size)) # Simula a atualização e calcula o tamanho do arquivo
            fi
        fi
    fi
}


delete_item() {
    local dest="$1"
    local item_size=0

    if [ -e "$dest" ]; then
        if [ -f "$dest" ]; then
            # Se for um arquivo, soma o tamanho e apaga
            item_size=$(stat -c %s "$dest" 2>/dev/null || stat -f %z "$dest")
            rm_command="rm \"$dest\""
            ((total_bytes_deleted+=item_size))
            ((deleted++))  # Incrementa o número de itens apagados
        elif [ -d "$dest" ]; then
            # Se for um diretório, iterar sobre todos os itens dentro dele
            for file in "$dest"/*; do
                if [ -f "$file" ]; then
                    # Soma o tamanho e conta cada arquivo
                    file_size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file")
                    ((total_bytes_deleted+=file_size))
                    ((deleted++))  # Incrementa o contador de itens apagados
                elif [ -d "$file" ]; then
                    # Conta o diretório como item (se necessário)
                    ((deleted++))
                fi
            done
            
            # Finalmente, apaga o diretório
            rm_command="rm -r \"$dest\""
        else
            echo "WARNING: '$dest' is not a file or a directory?"
            ((warnings++))
            return
        fi

        # Executa o comando de remoção
        echo "$rm_command"
        if [ "$CHECKING" = false ]; then
            if ! eval $rm_command; then
                echo "ERROR: Failed to delete $dest" >&2
                ((errors++))
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
            echo "mkdir -p $backup_item"
            if [ "$CHECKING" = false ]; then
                mkdir -p "$backup_item"
            fi
        fi
    elif [ -f "$item" ]; then
        # Se o item é um arquivo
        if [ -f "$backup_item" ]; then
            # Atualiza apenas se o arquivo de origem for mais recente
            if [ "$item" -nt "$backup_item" ]; then
                copy_item "$item" "$backup_item"
            else
                echo "WARNING: backup entry $backup_item is newer than $item; Should not happen"
                ((warnings++))  # Incrementa o contador de avisos
            fi
        else
            # Se o arquivo não existe no backup, é copiado
            copy_item "$item" "$backup_item"
        fi
    fi
done < <(find "$dir_trabalho" -mindepth 1)

if [ -d "$dir_backup" ]; then
    # Loop recursivo para verificar arquivos presentes no backup, se o diretório backup existir
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
fi

# Exibe o resumo final
echo "While backing up $dir_trabalho: $errors Errors; $warnings Warnings; $updated Updated; $copied Copied ($total_bytes_copied B); $deleted deleted ($total_bytes_deleted B)"
