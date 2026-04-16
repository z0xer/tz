cat > vault-setup.sh << 'SCRIPT'
#!/bin/bash
# Vault setup: запуск, запись секрета, политика, тесты ограничений
set -e

# === 1. Запуск Vault в dev-режиме ===
docker rm -f vault-dev 2>/dev/null || true
docker run -d \
  --name vault-dev \
  --cap-add=IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=myroot \
  -e SKIP_SETCAP=true \
  -p 8200:8200 \
  hashicorp/vault:latest

sleep 3

# === 2. Health check ===
curl -s http://127.0.0.1:8200/v1/sys/health 

# у меня че то на убунту не установился vault-cli
# Функция-обёртка для вызова vault в контейнере
vault_exec() {
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="${VAULT_TOKEN:-myroot}" \
      vault-dev vault "$@"
}

# === 3. Запись секрета ===
vault_exec kv put secret/app/database password=supersecret123 username=appuser

# === 4. Чтение секрета ===
vault_exec kv get secret/app/database

# === 5. Применение политики ===
docker cp policy.hcl vault-dev:/tmp/policy.hcl
vault_exec policy write app-readonly /tmp/policy.hcl

# здесь я юзал claude
# === 6. Создание ограниченного токена ===
RESTRICTED_TOKEN=$(vault_exec token create -policy=app-readonly -ttl=1h -format=json \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['auth']['client_token'])")
echo "Restricted token: $RESTRICTED_TOKEN"

# === 7. Тесты ограничений ===
echo ""
echo "=== read test ==="
VAULT_TOKEN=$RESTRICTED_TOKEN vault_exec kv get secret/app/database \
  || echo ">> read access"

echo ""
echo "=== write test ==="
VAULT_TOKEN=$RESTRICTED_TOKEN vault_exec kv put secret/app/database password=hacked \
  || echo ">> write deny"

echo ""
echo "=== delete test ==="
VAULT_TOKEN=$RESTRICTED_TOKEN vault_exec kv delete secret/app/database \
  || echo ">> delete deny"

echo ""
echo "=== Done ==="
SCRIPT

chmod +x vault-setup.sh
