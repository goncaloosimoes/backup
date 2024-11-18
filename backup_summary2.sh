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
        mapfile -t ignore_paths < "$IGNORE_FILE"  # Carrega os caminhos em um array
        # echo "Ignore paths loaded: ${ignore_paths[*]}"
    else
        echo "WARNING: Ignore file not found: $IGNORE_FILE"
        ((warnings++))
        ignore_paths=()
    fi
}

# Função para verificar se um item deve ser ignorado
should_ignore() {
    local path="$1"
    local relative_path="${path#$dir_trabalho/}"  # Extrai o caminho relativo

    # Se uma regex for fornecida, verifica se o ficheiro corresponde à regex
    if [ -f "$path" ]; then # Apenas compara com o regex se for um ficheiro
        if [[ -n "$REGEX" && ! "$relative_path" =~ $REGEX ]]; then
            echo "Ignoring $relative_path due to regex mismatch"
            return 0  # Ignorar o item
        fi
    fi

    for ignore in "${ignore_paths[@]}"; do
        if [[ "$path" == "$ignore" || "$relative_path" == "$ignore" ]]; then
            echo "Ignoring $relative_path due to mention in $IGNORE_FILE"
            return 0 # Ignorar o item
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

    if [ ! -e "$dest_item" ]; then
        echo "cp -a \"$src_item\" \"$dest_item\""
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
                else
                    echo "ERROR: failed to update $src_item to $dest_item" >&2
                    ((errors++))  # Incrementa contador de erros
                fi
            else
                ((updated++))  # Incrementa contador de arquivos atualizados
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

# Função para processar o diretório e mostrar apenas o resumo do diretório atual
process_directory() {
    local dir="$1"
    
    # Habilita a expansão para arquivos ocultos (arquivos que começam com '.')
    shopt -s dotglob
    
    # Inicializa os contadores para o diretório atual
    local current_copied=0
    local current_updated=0
    local current_deleted=0
    local current_errors=0
    local current_warnings=0
    local current_bytes_copied=0
    local current_bytes_deleted=0

    # Itera sobre os itens dentro do diretório, agora incluindo arquivos ocultos
    for item in "$dir"/*; do
        if should_ignore "$item"; then
            continue
        fi
        
        relative_path="${item#$dir_trabalho/}"
        backup_item="$dir_backup/$relative_path"
        
        if [ -d "$item" ]; then
            process_directory "$item"  # Processa subdiretórios recursivamente
        else
            copy_item "$item" "$backup_item"  # Copia arquivos do diretório atual

            # Atualiza os contadores locais do diretório atual
            current_copied=$((current_copied + copied))
            current_updated=$((current_updated + updated))
            current_deleted=$((current_deleted + deleted))
            current_errors=$((current_errors + errors))
            current_warnings=$((current_warnings + warnings))
            current_bytes_copied=$((current_bytes_copied + total_bytes_copied))
            current_bytes_deleted=$((current_bytes_deleted + total_bytes_deleted))

            # Resetando os contadores globais para o próximo arquivo
            copied=0
            updated=0
            deleted=0
            errors=0
            warnings=0
            total_bytes_copied=0
            total_bytes_deleted=0
        fi
    done

    # Exibe o resumo para o diretório atual após processar todos os itens
    echo "While backuping $dir: $current_errors Errors; $current_warnings Warnings; $current_updated Updated; $current_copied Copied ($current_bytes_copied"B"); $current_deleted Deleted ($current_bytes_deleted"B")"
}

# Chama a função para processar o diretório de trabalho
process_directory "$dir_trabalho"