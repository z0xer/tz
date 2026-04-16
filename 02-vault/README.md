
## Что сделано

1. Запущен Vault в dev-режиме через Docker (порт 8200)
2. Записан секрет `secret/app/database` (username=appuser, password=supersecret123)
3. Прочитан секрет обратно — значения совпали
4. Создана политика `app-readonly` (только read на `secret/data/app/*`)
5. Создан токен с этой политикой, протестированы ограничения:
   - Чтение: работает
   - Запись: permission denied
   - Удаление: permission denied
6. (Бонус) Python-скрипт `fetch-secret.py` читает секрет через HTTP API без CLI

## Файлы

- `vault-setup.sh` — команды запуска Vault и работы с секретами
- `policy.hcl` — политика доступа (read-only на `secret/data/app/*`)
- `fetch-secret.py` — чтение секрета через HTTP API (бонус)

## Запуск

```bash
# 1. Запустить Vault
docker run -d \
  --name vault-dev \
  --cap-add=IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=myroot \
  -e SKIP_SETCAP=true \
  -p 8200:8200 \
  hashicorp/vault:latest

# 2. Прогнать скрипт
bash vault-setup.sh
```
<img width="1422" height="577" alt="изображение" src="https://github.com/user-attachments/assets/5db12ab2-5988-4123-90d5-3866eb68f57e" />
<img width="1084" height="347" alt="изображение" src="https://github.com/user-attachments/assets/7524a37b-9e86-4e57-b18b-1a655a441f5c" />
<img width="750" height="511" alt="изображение" src="https://github.com/user-attachments/assets/f25528cd-37ec-4549-8b33-ccdaa8af4ba0" />
<img width="1454" height="442" alt="изображение" src="https://github.com/user-attachments/assets/e4436440-d8a2-4c7b-90d7-b893e97dceee" />
<img width="1441" height="755" alt="изображение" src="https://github.com/user-attachments/assets/cae51285-c376-4c79-9a6c-d54b7d5119ad" />





---

### Зачем Vault если есть .env файл?

`.env` — это plaintext на диске. Ключевые проблемы:

| Аспект | .env | Vault |
|--------|------|-------|
| Хранение | открытый текст | зашифровано (AES-256) |
| Git | легко случайно закоммитить | секреты хранятся отдельно от кода |
| Аудит | нет логов кто читал | audit log: кто, когда, какой секрет |
| Ротация | руками на каждом сервере | централизованно одной командой |
| Доступ | всё или ничего | политики: кто какой секрет может читать |
| TTL | нет (живёт вечно) | dynamic secrets с коротким сроком жизни |
| Централизация | копия на каждом сервере | один источник |

**Реальный пример:** разработчик случайно коммитит `.env` с AWS-ключами в публичный репо. Боты Shodan/GitHub находят ключи за минуты и майнят крипту за твой счёт. Счёт $50k+. С Vault такого не случится — в коде только токен, а не сами секреты.

Дополнительно Vault умеет **динамические секреты**: генерирует временные креды для БД с TTL 1 час. Если утёк — он уже мёртв.

**Когда .env всё же ок:** локальная разработка, не-продакшен.

### Что произойдёт с секретами при перезапуске Vault в dev-режиме?

**Все секреты потеряются.** Dev-режим хранит всё **в оперативной памяти** (in-memory backend), никакого persistence нет. Перезапуск контейнера = пустое хранилище.

**Почему важно знать:**

1. **Dev-режим — только для обучения и локальной разработки.** В production категорически запрещён.
2. В production используется **persistent storage backend** (Integrated Raft, Consul, PostgreSQL) — данные сохраняются на диск в зашифрованном виде.
3. В dev — автоматический unseal, root-token предсказуемый (`myroot`). В production — Shamir's Secret Sharing: мастер-ключ разбит на N частей (например 5), нужно минимум K (например 3) чтобы разблокировать Vault. Защита от кражи диска и от одного злонамеренного админа.
4. Если случайно запустить dev-Vault в продакшене и положить туда реальные секреты — при рестарте всё пропадёт, приложения сломаются, downtime гарантирован.
EOF
