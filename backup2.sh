#!/bin/bash

# Contadores
errors=0
warnings=0
updated=0
copied=0
deleted=0
total_bytes=0

usage() {
    echo "Utilizacao: $0 [-c] [-b tfile] [-r regexpr] <dir_trabalho> <dir_backup>"
}

# Variáveis para o modo de CHECKING (-c), arquivo de ignorados (-b) e expressão regular (-r)
CHECKING=false
IGNORE_FILE=""
REGEX=""

# Melhor apresentação
echo -e "--------------------Backup-------------------------\n"

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
VerificaDir() {
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
        b) IGNORE_FILE="$OPTARG";;
        r) REGEX="$OPTARG"
            # Validação da expressão regular
            if [[ -z "$REGEX" ]]; then
                echo "Invalid Regular Expression: REGEX is not set"
                ((errors++))
                exit 1
            fi
            echo "" | grep -E "$REGEX" >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo "Invalid Regular Expression: '$REGEX' is not a valid regex"
                ((errors++))
                exit 1
            fi;;
        ?) usage
            exit 1;;
    esac
done
# Remove as opções processadas
shift $((OPTIND - 1))

# Valida se o número de argumentos é adequado
if [ "$#" -lt 2 ]; then
    echo "Erro: Diretórios 'dir_trabalho' e 'dir_backup' são obrigatórios."
    ((errors++))
    exit 1
fi

# Normalização e atribuição dos diretórios dir_trabalho e dir_backup
args=("$@")
dir_trabalho="${args[0]}"
dir_backup="${args[1]}"

# Verificação do diretório de trabalho
VerificaDir "$dir_trabalho"
if [[ $? -eq 1 ]]; then
    echo "Erro: O diretório de trabalho '$dir_trabalho' não existe ou não é válido."
    ((errors++))
else
    echo "Diretório de trabalho '$dir_trabalho' é válido."
fi

# Verificação do diretório de backup
VerificaDir "$dir_backup"
if [[ $? -eq 1 ]]; then
    # Se o diretório não existe, criamos
    if [ "$CHECKING" = false ]; then
        echo -e "O diretório de Backup não existe. \nCriando o diretório de backup '$dir_backup'"
        if ! mkdir -p "$dir_backup"; then
            echo "Erro: Não foi possível criar o diretório de backup '$dir_backup' devido a um caminho inválido ou permissão insuficiente."
            ((errors++))
            exit 1
        fi
    fi
else
    # Diretório de backup já existe
    if [ "$CHECKING" = false ]; then
        echo "O diretório de backup '$dir_backup' já existe. Iniciando o backup."
    else
        echo "Verificando: O diretório de backup '$dir_backup' já existe (não será criado no modo -c)."
    fi
fi

# Se houver erros, terminamos o script aqui
if [ "$errors" -gt 0 ]; then
    echo "Ocorreram $errors erros. O backup não será realizado."
    exit 1
fi

# Carrega a lista de arquivos a serem ignorados
load_ignore_paths

# Inicia o processo de cópia (mensagens diferentes dependendo do modo)
if [ "$CHECKING" = false ]; then
    echo -e "\nIniciando o processo de backup..."
else
    echo -e "\nO que aconteceria em caso de backup (modo de verificação)..."
fi

# Função para copiar arquivos e diretórios recursivamente
copy_item() {
    local src_item="$1"
    local dest_item="$2"

    # Verifica se o item deve ser ignorado
    if should_ignore "$src_item"; then
        echo "Ignoring $src_item"
        return
    fi

    # Aplica o filtro de REGEX, se definido
    if [[ -n "$REGEX" && ! "$(basename "$src_item")" =~ $REGEX ]]; then
        echo "Skipping $src_item due to regex filter"
        return
    fi

    # Verifica se é um diretório
    if [ -d "$src_item" ]; then
        # Se estiver no modo CHECKING, não cria o diretório de destino
        if [ "$CHECKING" = false ]; then
            mkdir -p "$dest_item"
        else
            # No modo de verificação, simula a criação do diretório
            echo "Simulating: mkdir -p \"$dest_item\""
        fi

        # Loop para copiar todos os itens dentro do diretório
        for item in "$src_item"/*; do
            copy_item "$item" "$dest_item/$(basename "$item")"
        done
    else
        # Verifica a data de modificação dos arquivos
        if [ -e "$dest_item" ]; then
            # Verifica se o arquivo no diretório de trabalho é mais recente que no backup
            if [ "$src_item" -nt "$dest_item" ]; then
                # Se a data do arquivo de origem for mais recente, copia
                if [ "$CHECKING" = false ]; then
                    echo "cp -a \"$src_item\" \"$dest_item\""
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
                    echo "Simulating: cp -a \"$src_item\" \"$dest_item\""
                    file_size=$(stat -c%s "$src_item" 2>/dev/null)
                    ((total_bytes+=file_size))
                    echo "Checked $src_item ($file_size bytes)"
                fi
            else
                # Caso a data no backup seja mais recente ou igual à do arquivo de trabalho
                echo "Situação anômala: Arquivo em dir_backup encontrado com data mais recente que em dir_trabalho"
                ((errors++))
            fi
        else
            # Caso o arquivo não exista no backup, ele é copiado
            if [ "$CHECKING" = false ]; then
                echo "cp -a \"$src_item\" \"$dest_item\""
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
                echo "Simulating: cp -a \"$src_item\" \"$dest_item\""
                file_size=$(stat -c%s "$src_item" 2>/dev/null)
                ((total_bytes+=file_size))
                echo "Checked $src_item ($file_size bytes)"
            fi
        fi
    fi
}

# Remover arquivos no diretório de backup que não estão no diretório de trabalho
delete_removed_files() {
    for backup_item in "$dir_backup"/*; do
        src_item="$dir_trabalho/$(basename "$backup_item")"
        if [ ! -e "$src_item" ]; then
            echo "Removendo $backup_item, não encontrado em $dir_trabalho"
            if [ "$CHECKING" = false ]; then
                rm -rf "$backup_item"
                ((deleted++))
            else
                echo "Simulating: rm -rf \"$backup_item\""
            fi
        fi
    done
}

# Apaga arquivos no backup que não existem mais no diretório de trabalho
delete_removed_files

# Iniciando o backup de fato ou simulação
copy_item "$dir_trabalho" "$dir_backup"

# Mensagem de conclusão
echo "Processo concluído."
if [ "$CHECKING" = false ]; then
    echo "Backup concluído: $errors erros; $warnings avisos; $updated atualizados; $copied copiados ($total_bytes bytes); $deleted excluídos (0 bytes)"
else
    echo "Simulação concluída: $errors erros; $warnings avisos; $updated atualizados; $copied copiados ($total_bytes bytes); $deleted excluídos (0 bytes)"
fi
