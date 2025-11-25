#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo $SCRIPT_DIR

# Загружаем .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env file not found in $SCRIPT_DIR"
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"

# Проверка обязательных переменных
: "${SERVER_IP:?SERVER_IP not set in .env}"
: "${REMOTE_USER:?REMOTE_USER not set in .env}"
: "${CONTEXT_NAME:?CONTEXT_NAME not set in .env}"

REMOTE_PATH="/etc/rancher/k3s/k3s.yaml"

KUBECONFIG_DIR="$HOME/.kube"
LOCAL_CONFIG="$KUBECONFIG_DIR/config"
BACKUP_CONFIG="$KUBECONFIG_DIR/config_prev"
TEMP_CONFIG="./temp_config.yaml"
MERGED_CONFIG="./merged_config.yaml"

mkdir -p "$KUBECONFIG_DIR"

echo ">>> SERVER_IP:     $SERVER_IP"
echo ">>> REMOTE_USER:   $REMOTE_USER"
echo ">>> CONTEXT_NAME:  $CONTEXT_NAME"
echo

echo ">>> Забираю kubeconfig с сервера $SERVER_IP ..."
scp "${REMOTE_USER}@${SERVER_IP}:${REMOTE_PATH}" "$TEMP_CONFIG"

echo ">>> Меняю серверный endpoint на внешний IP..."
if sed --version >/dev/null 2>&1; then
  # GNU sed (Linux)
  sed -i "s#https://.*:6443#https://${SERVER_IP}:6443#g" "$TEMP_CONFIG"
else
  # BSD sed (macOS)
  sed -i '' "s#https://.*:6443#https://${SERVER_IP}:6443#g" "$TEMP_CONFIG"
fi

echo ">>> Переименовываю cluster/context/user в $CONTEXT_NAME ..."
yq -i "
  .clusters[0].name = \"$CONTEXT_NAME\" |
  .contexts[0].name = \"$CONTEXT_NAME\" |
  .users[0].name = \"$CONTEXT_NAME\" |
  .contexts[0].context.cluster = \"$CONTEXT_NAME\" |
  .contexts[0].context.user = \"$CONTEXT_NAME\"
" "$TEMP_CONFIG"

echo ">>> Делаю бэкап существующего kubeconfig -> $BACKUP_CONFIG"
if [ -f "$LOCAL_CONFIG" ]; then
  cp "$LOCAL_CONFIG" "$BACKUP_CONFIG"
fi

echo ">>> Мерджу kubeconfig..."
if [ -f "$LOCAL_CONFIG" ]; then
  KUBECONFIG="$LOCAL_CONFIG:$TEMP_CONFIG" kubectl config view --merge --flatten > "$MERGED_CONFIG"
else
  cp "$TEMP_CONFIG" "$MERGED_CONFIG"
fi

echo ">>> Обновляю kubeconfig..."
mv "$MERGED_CONFIG" "$LOCAL_CONFIG"

echo ">>> Устанавливаю контекст $CONTEXT_NAME по умолчанию"
kubectl config use-context "$CONTEXT_NAME"

echo ">>> Готово."
