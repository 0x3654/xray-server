#!/bin/bash
# Функция для генерации случайного порта (от 10000 до 65535)
generate_random_port() {
    echo $((RANDOM % 55535 + 10000))
}
# Функция для генерации случайного пути (8 символов)
generate_random_path() {
    openssl rand -base64 6 | tr -d '/+=' | head -c 8
}
# Функция для генерации Reality ключей
generate_reality_keys() {
    # Генерация приватного ключа
    private_key=$(openssl rand -base64 32)
    # Генерация публичного ключа
    public_key=$(echo -n "$private_key" | openssl dgst -sha256 -binary | openssl base64 -A)
    # Генерация ShortID (8 символов hex)
    short_id=$(openssl rand -hex 4)
    
    echo "$private_key|$public_key|$short_id"
}

# Функция для генерации пароля в формате xxxxx-xxxxx-xxxxx
generate_password() {
    # Генерируем 15 случайных символов (5-5-5)
    password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 15)
    # Добавляем дефисы после каждых 5 символов
    echo "${password:0:5}-${password:5:5}-${password:10:5}"
}

# Создаем резервную копию базы данных
echo "=== Создание резервной копии базы данных ==="
cp /xray-server/3x-ui/db/x-ui.db /xray-server/3x-ui/db/x-ui.db.backup

# Получаем внешний IP
EXTERNAL_IP=$(curl -s ifconfig.me)
echo "Получен внешний IP: $EXTERNAL_IP"


# Генерируем новые значения
WEB_PORT=$(generate_random_port)
BASE_PATH=$(generate_random_path)
REALITY_KEYS=$(generate_reality_keys)
PRIVATE_KEY=$(echo $REALITY_KEYS | cut -d'|' -f1)
PUBLIC_KEY=$(echo $REALITY_KEYS | cut -d'|' -f2)
SHORT_ID=$(echo $REALITY_KEYS | cut -d'|' -f3)

# Генерируем новый пароль
NEW_PASSWORD=$(generate_password)

# Сохраняем ID клиентов
CLIENT_IDS=$(sqlite3 /xray-server/3x-ui/db/x-ui.db "SELECT json_extract(value, '$.id') FROM inbounds, json_each(json_extract(inbounds.settings, '$.clients')) WHERE inbounds.id = 1;" | tr '\n' '|')

# Обновляем настройки в базе
echo "=== Обновление настроек в базе данных ==="
sqlite3 /xray-server/3x-ui/db/x-ui.db << EOF
UPDATE settings SET value = '$WEB_PORT' WHERE key = 'webPort';
UPDATE settings SET value = '$BASE_PATH' WHERE key = 'webBasePath';
EOF
check_sql_error

sqlite3 /xray-server/3x-ui/db/x-ui.db << EOF
UPDATE inbounds SET 
    listen = '$EXTERNAL_IP',
    settings = json_replace(
        settings,
        '$.clients[0].id', '$(echo $CLIENT_IDS | cut -d'|' -f1)',
        '$.clients[1].id', '$(echo $CLIENT_IDS | cut -d'|' -f2)',
        '$.clients[2].id', '$(echo $CLIENT_IDS | cut -d'|' -f3)',
        '$.clients[3].id', '$(echo $CLIENT_IDS | cut -d'|' -f4)',
        '$.clients[4].id', '$(echo $CLIENT_IDS | cut -d'|' -f5)'
    ),
    stream_settings = json_replace(
        stream_settings,
        '$.realitySettings.privateKey', '$PRIVATE_KEY',
        '$.realitySettings.publicKey', '$PUBLIC_KEY',
        '$.realitySettings.shortIds[0]', '$SHORT_ID'
    )
WHERE id = 1;
EOF
check_sql_error

# Обновляем учетные данные
echo "=== Обновление учетных данных ==="
sqlite3 /xray-server/3x-ui/db/x-ui.db "UPDATE users SET username = 'root', password = '$NEW_PASSWORD' WHERE id = 1;"
check_sql_error

# Запускаем контейнер
echo "=== Запуск контейнера ==="
docker-compose up -d

echo "=== Готово! ==="
echo "Панель будет доступна через несколько секунд по новому URL"
echo "URL панели: https://$EXTERNAL_IP:$WEB_PORT/$BASE_PATH"
echo "Логин: root"
echo "Пароль: $NEW_PASSWORD"