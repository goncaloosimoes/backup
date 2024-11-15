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

# Variáveis para o modo de CHECKING (-c), arquivo de ignorados (-b) e expressão regular (-r)
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

#
copy_item() {
    # Caminho do arquivo de origem
    local src_item="$1"  
    # Caminho do arquivo de destino
    local dest_item="$2" 

    # Exibe o comando de cópia no terminal, para monitoramento
    echo "cp -a \"$src_item\" \"$dest_item\""

    # Verifica se o item deve ser ignorado ou se não corresponde ao filtro de regex
    if should_ignore "$src_item" || [[ -n "$REGEX" && ! "$(basename "$src_item")" =~ $REGEX ]]; then
        echo "Ingoring $src_item"
        return
    fi

    # Verifica se o item de origem é um diretório
    if [ -d "$src_item" ]; then
        echo "mkdir -p $dest_item"
        # Se não estiver no modo CHECKING, cria o diretório de destino
        if [ "$CHECKING" = false ]; then
            mkdir -p "$dest_item"
        fi

        # Loop para processar todos os itens dentro do diretório
        for item in "$src_item"/*; do
            # Verifica se o item não está vazio e faz a cópia recursiva
            if [ -e "$item" ]; then
                # Chama recursivamente a função para copiar os itens do diretório
                copy_item "$item" "$dest_item/$(basename "$item")"
            fi
        done
    else
        # Se for um ficheiro, verifica se o item de destino já existe
        if [ ! -e "$dest_item" ] || [ "$src_item" -nt "$dest_item" ]; then
            # Se o arquivo de destino não existir ou se o arquivo de origem for mais recente
            if [ "$CHECKING" = false ]; then
                # Realiza a cópia do arquivo
                echo entrei
                if cp -a "$src_item" "$dest_item"; then
                    echo "Arquivo copiado: $src_item para $dest_item"
                    ((copied++))  # Incrementa contador de arquivos copiados
                    # Obtém o tamanho do arquivo e adiciona ao total de bytes copiados
                    file_size=$(stat -c%s "$src_item")
                    ((total_bytes_copied+=file_size))
                else
                    echo "Erro ao copiar $src_item para $dest_item" >&2
                    ((errors++))  # Incrementa contador de erros
                fi
            else
                # Apenas simula a cópia e calcula o tamanho do arquivo (sem realizar a cópia real)
                file_size=$(stat -c%s "$src_item")
                ((total_bytes_copied+=file_size))
                echo "Simulando cópia do arquivo: $src_item (Modo CHECKING)"
            fi
        else
            echo "O arquivo de destino $dest_item já existe e está atualizado. Nenhuma cópia necessária."
        fi
    fi
}

delete_item() {
    # Caminho para o ficheiro ou diretoria de destino que desejamos apagar
    local dest="$1"
    echo "rm -r \"$dest\""

    # Se CHECKING for false, corremos os comandos
    if [ "$CHECKING" = false ]; then
        if [ -e "$dest" ]; then  # Apenas apaga se o caminho existir
            # Anotamos o tamanho do ficheiro ou diretoria antes de apagá-lo
            if [ -f "$dest" ]; then
                file_size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest")
            elif [ -d "$dest" ]; then
                # Para diretórios, usamos o comando du para calcular o tamanho
                file_size=$(du -sb "$dest" | cut -f1)
            fi

            # Apagar o ficheiro ou diretoria
            if rm -r "$dest"; then
                ((deleted++))  # Incrementa o número de ficheiros ou diretórios apagados
                ((total_bytes_deleted+=file_size))  # Soma ao total de bytes apagados
            else
                echo "ERROR: failed to delete $dest" >&2
                ((errors++))
            fi
        fi
    else
        # Caso o checking seja verdadeiro fazemos o mesmo procedimento, sem executar os comandos
        if [ -e "$dest" ]; then
            if [ -f "$dest" ]; then
                # Calcula o tamanho do ficheiro
                file_size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest")
            elif [ -d "$dest" ]; then
                # Calcula o tamanho da diretoria
                file_size=$(du -sb "$dest" | cut -f1)
            fi
            # O contador de apagados ainda é incrementado no modo de verificação
            ((deleted++))
            ((total_bytes_deleted+=file_size))  # Soma ao total de bytes apagados na diretoria backup
        fi
    fi
}


# Apaga arquivos no backup que não existem mais no diretório de trabalho

# Iniciando o backup de fato ou simulação
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
                copy_item "$file" "$backup_file"
                ((updated++))  # Incrementa o contador de atualizações
            else
                echo "WARNING: backup entry $backup_file is newer than $file; Should not happen"
                ((warnings++))  # Incrementa o contador de avisos
            fi
        else
            # Se o ficheiro não existe no backup, é copiado para lá
            copy_item "$file" "$backup_file"
        fi
    fi
done


# Loop para verificar arquivos presentes no backup
for backup_item in "$dir_backup"/*; do
    # Verifica se o item no backup é um ficheiro
    if [ -f "$backup_item" ]; then
        itemname=$(basename "$backup_item")
        item="$dir_trabalho/$itemname"

        # Se o arquivo não existe mais no diretório de trabalho, eliminamos o ficheiro do backup
        if [ ! -e "$item" ]; then
            delete_file "$backup_item"
        fi
    fi

    # Verifica se o item no backup é um diretório
    if [ -d "$backup_item" ]; then
        itemname=$(basename "$backup_item")
        item="$dir_trabalho/$itemname"

        # Se o diretório não existe mais no diretório de trabalho, deletamos o diretório do backup
        if [ ! -e "$item" ]; then
            delete_directory "$backup_item"
        fi
    fi
done

# Mensagem de conclusão
echo "Processo concluído."
if [ "$CHECKING" = false ]; then
    echo "Backup concluído: $errors erros; $warnings avisos; $updated atualizados; $copied copiados ($total_bytes_copied bytes); $deleted excluídos ($total_bytes_deleted bytes)"
else
    echo "Simulação concluída: $errors erros; $warnings avisos; $updated atualizados; $copied copiados ($total_bytes_copied bytes); $deleted excluídos ($total_bytes_deleted bytes)"
fi
