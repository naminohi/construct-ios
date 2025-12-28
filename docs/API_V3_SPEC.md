# Спецификация API: Крипто-гибкость

**Версия:** 2.4
**Дата:** 2025-12-26

## 1. Введение

Цель этого API — внедрение **крипто-гибкости (crypto-agility)**. Это позволит клиентам поддерживать несколько криптографических алгоритмов одновременно и согласовывать наиболее безопасный из них. Это является ключевым шагом для поддержки постквантовых (PQ) гибридных схем в будущем.

**Примечание:** Префикс версии `/v3/` был удален из путей. Все эндпоинты доступны напрямую без префикса версии.

## 2. Основные концепции

### 2.1. Идентификатор набора шифров (`SuiteID`)

`SuiteID` — это целое число (`u16`), которое уникально идентифицирует набор криптографических примитивов (KEM, подпись, AEAD, хэш).

**Начальная таблица `SuiteID`:**

| ID  | KEM/DH | Signature | AEAD           | Hash    | Примечание                  |
|-----|--------|-----------|----------------|---------|-----------------------------|
| 1   | X25519 | Ed25519   | AES-256-GCM    | SHA-512 | **Базовый классический набор** |
| 2   | TBD    | TBD       | TBD            | TBD     | *Зарезервировано для PQ-гибрида* |

### 2.2. Подписанный пакет ключей (`SignedKeyBundle`)

Это центральный объект для установления доверия. Вместо того чтобы доверять серверу в том, что он отдает правильные ключи, клиент доверяет только пакету, который криптографически подписан долгосрочным **ключом идентификации** (`masterIdentityKey`) другого пользователя.

- **Процесс создания (на клиенте):**
  1. Клиент генерирует все необходимые публичные ключи для каждого набора шифров, который он поддерживает.
  2. Он упаковывает их в структуру `BundleData`.
  3. Эта структура канонически сериализуется (например, в JSON без пробелов) и подписывается `masterIdentityKey`.
- **Процесс проверки (на клиенте):**
  1. Клиент запрашивает пакет ключей другого пользователя.
  2. **Перед использованием** он проверяет подпись пакета с помощью `masterIdentityKey`. Если подпись неверна, пакет отбрасывается.

## 3. Структуры данных (JSON)

### 3.1. Объект регистрации (`RegisterData`)

Для регистрации нового пользователя клиент отправляет объект `RegisterData`. Поле `publicKey` этого объекта содержит информацию о криптографических ключах пользователя как **нативную структуру MessagePack**.

**⚠️ BREAKING CHANGE (v2.3):** Поле `publicKey` больше НЕ является Base64-кодированной JSON-строкой. Теперь это нативная структура `UploadableKeyBundle`, которая сериализуется в MessagePack вместе с остальным сообщением.

```json
{
  "username": "String",
  "password": "String",
  "publicKey": {
    "masterIdentityKey": "Base64<Bytes>",
    "bundleData": "Base64<Serialized_BundleData>",
    "signature": "Base64<Bytes>"
  }
}
```

- `username`: Имя пользователя.
- `password`: Пароль пользователя.
- `publicKey`: Нативная структура `UploadableKeyBundle` (см. раздел 3.2).

**Процесс формирования `publicKey` (клиентом):**

1.  **Создание `BundleData`**: Клиент генерирует все необходимые публичные ключи для каждого поддерживаемого набора шифров (например, X25519 identity key, signed prekey, one-time prekeys) и упаковывает их в структуру `BundleData` (см. раздел "3.3. `BundleData`"). На этом этапе поле `userId` в `BundleData` может быть пустым.
2.  **Сериализация `BundleData`**: `BundleData` сериализуется в каноническую JSON-строку.
3.  **Подпись `BundleData`**: Клиент генерирует долгосрочную мастер-идентифицирующую ключевую пару Ed25519. Полученная на предыдущем шаге JSON-строка `BundleData` подписывается **приватным** мастер-ключом Ed25519.
4.  **Создание `UploadableKeyBundle`**: Формируется объект `UploadableKeyBundle` (см. раздел "3.2. `UploadableKeyBundle`"), который включает в себя:
    *   Base64-кодированный **публичный** мастер-ключ Ed25519 (`masterIdentityKey`).
    *   Base64-кодированную JSON-строку `BundleData` (`bundleData`).
    *   Base64-кодированную криптографическую подпись (`signature`).
5.  **Отправка**: Клиент отправляет структуру `RegisterData` с нативным `UploadableKeyBundle` в поле `publicKey`. MessagePack автоматически сериализует всю структуру целиком.

### 3.2. `UploadableKeyBundle`
Структура, которую клиент загружает на сервер.

```json
{
  "masterIdentityKey": "Base64<Bytes>",
  "bundleData": "Base64<Serialized_BundleData>",
  "signature": "Base64<Bytes>"
}
```
- `masterIdentityKey`: Долгосрочный публичный ключ Ed25519, которым все подписано.
- `bundleData`: Сериализованная структура `BundleData`, закодированная в Base64.
- `signature`: Ed25519 подпись от `bundleData`.


### 3.3. `BundleData`
Структура, которая сериализуется и подписывается.

```json
{
  "userId": "String",
  "timestamp": "ISO8601_String",
  "supportedSuites": [
    {
      "suiteId": 1,
      "identityKey": "Base64<Bytes>",
      "signedPrekey": "Base64<Bytes>",
      "oneTimePrekeys": ["Base64<Bytes>", ...]
    }
    // ... здесь могут быть другие наборы
  ]
}
```
- `oneTimePrekeys`: Опциональный, но рекомендуемый список одноразовых ключей.


### 3.4. `EncryptedMessageV3`
Структура для отправки E2E-зашифрованного сообщения.

**Примечание:** Название структуры `EncryptedMessageV3` сохранено для обратной совместимости с кодовой базой.

```json
{
  "recipientId": "String",
  "suiteId": "u16",
  "ciphertext": "Base64<Bytes>"
}
```
- `suiteId`: ID набора, который был использован для шифрования.
- `ciphertext`: Зашифрованное сообщение, формат которого определяется соответствующим `suiteId`.

## 4. Эндпоинты API

### `POST /keys/upload`
Загружает или обновляет пакет ключей пользователя.

- **URL:** `POST /keys/upload`
- **Аутентификация:** Требуется (JWT токен в заголовке `Authorization: Bearer <token>`).
- **Request Body:** `UploadableKeyBundle` (JSON)
- **Действия сервера:**
  1. Проверить аутентификацию JWT. Пользователь может загружать ключи только для самого себя.
  2. **Не проверять `signature`**. Это ответственность клиентов (zero-trust архитектура).
  3. Провести базовую валидацию форматов (Base64) и "умную" валидацию длин ключей в `BundleData` на основе `suiteId`.
  4. Проверить, что `userId` в `BundleData` совпадает с аутентифицированным пользователем.
  5. Сохранить `UploadableKeyBundle` в БД (UPSERT - обновление существующих или создание новых).
  6. Инвалидировать кэш Redis для данного пользователя.
- **Response:**
  - `200 OK` - успешная загрузка
  - `400 Bad Request` - невалидные данные
  - `401 Unauthorized` - отсутствие или невалидный токен
  - `500 Internal Server Error` - ошибка сервера

**Пример успешного ответа:**
```json
{
  "status": "ok"
}
```

### `GET /keys/{userId}`
Получает пакет ключей для указанного пользователя.

- **URL:** `GET /keys/{userId}`
- **Аутентификация:** Требуется (JWT токен).
- **Path Parameter:** `{userId}` - UUID пользователя
- **Действия сервера:**
  1. Проверить аутентификацию.
  2. Найти в БД `UploadableKeyBundle` для указанного `userId`.
  3. Вернуть его в теле ответа.
- **Response:**
  - `200 OK` с телом `UploadableKeyBundle` (JSON)
  - `401 Unauthorized` - отсутствие или невалидный токен
  - `404 Not Found` - пакет ключей не найден
  - `500 Internal Server Error` - ошибка БД

**Пример успешного ответа:**
```json
{
  "masterIdentityKey": "Base64String...",
  "bundleData": "Base64String...",
  "signature": "Base64String..."
}
```

### `POST /messages/send`
Отправляет E2E-зашифрованное сообщение.

- **URL:** `POST /messages/send`
- **Аутентификация:** Требуется (JWT токен).
- **Request Body:** `EncryptedMessageV3` (JSON)
- **Действия сервера:**
  1. Проверить аутентификацию JWT и извлечь `senderId`.
  2. Провести базовую валидацию полей (непустой `recipientId`, поддерживаемый `suiteId`).
  3. Валидировать минимальную длину `ciphertext` в зависимости от `suiteId`:
     - Suite 1 (CLASSIC_X25519): минимум 48 байт (32 ephemeral + 16 AEAD tag)
  4. Проверить, что отправитель не отправляет сообщение самому себе.
  5. Сериализовать сообщение в JSON.
  6. Поместить сообщение в оффлайн-очередь получателя в Redis (с TTL).
  7. Залогировать операцию с хешированием ID (если включена приватность).
- **Response:**
  - `202 Accepted` - сообщение принято в очередь
  - `400 Bad Request` - невалидные данные или отправка самому себе
  - `401 Unauthorized` - отсутствие или невалидный токен
  - `500 Internal Server Error` - ошибка очереди

**Пример успешного ответа:**
```json
{
  "status": "accepted"
}
```


## 5. WebSocket API

Помимо HTTP-эндпоинтов для работы с ключами и сообщениями, сервер предоставляет WebSocket API для аутентификации, управления сессиями, обмена сообщениями и изменения учетных данных.

### 5.1. Формат сообщений

Все сообщения передаются в формате **MessagePack** с internally-tagged enum формате:

```json
{
  "type": "messageType",
  "payload": { /* данные сообщения */ }
}
```

**Важно:**
- Все поля используют **camelCase** нотацию
- Бинарные данные передаются в **Base64** кодировке (кроме `ephemeralPublicKey` в `ChatMessage`, который передается как MessagePack bin)
- UUID передаются как **строки**
- Timestamps в формате **Unix timestamp (секунды)** или **ISO8601**

---

## 5.2. Клиентские сообщения (Client → Server)

### 5.2.1. Register (Регистрация)

Создает новый аккаунт пользователя.

**⚠️ BREAKING CHANGE (v2.3):** Поле `publicKey` теперь нативная структура `UploadableKeyBundle`, а не Base64-кодированная строка.

**Структура:**
```json
{
  "type": "register",
  "payload": {
    "username": "String",
    "password": "String",
    "publicKey": {
      "masterIdentityKey": "Base64<Bytes>",
      "bundleData": "Base64<Serialized_BundleData>",
      "signature": "Base64<Bytes>"
    }
  }
}
```

**Поля:**
- `username` (String) - имя пользователя (уникальное)
- `password` (String) - пароль (требования: минимум 10 символов, uppercase, lowercase, digit)
- `publicKey` (UploadableKeyBundle) - нативная структура с криптографическими ключами (см. раздел 3.2)

**Ответы:**
- `RegisterSuccess` - успешная регистрация
- `Error` с кодом `WEAK_PASSWORD`, `REGISTRATION_FAILED`, `INVALID_KEY_BUNDLE`

---

### 5.2.2. Login (Вход)

Аутентифицирует пользователя и создает сессию.

**Структура:**
```json
{
  "type": "login",
  "payload": {
    "username": "String",
    "password": "String"
  }
}
```

**Поля:**
- `username` (String) - имя пользователя
- `password` (String) - пароль

**Rate Limiting:**
- Максимум 5 неудачных попыток за 15 минут
- После 5-й неудачной попытки - блокировка на 15 минут

**Ответы:**
- `LoginSuccess` - успешный вход
- `Error` с кодом `INVALID_CREDENTIALS`, `RATE_LIMIT_EXCEEDED`

---

### 5.2.3. Connect (Переподключение с токеном)

Восстанавливает сессию используя существующий JWT токен.

**Структура:**
```json
{
  "type": "connect",
  "payload": {
    "sessionToken": "String"
  }
}
```

**Поля:**
- `sessionToken` (String) - JWT токен из предыдущей сессии

**Ответы:**
- `ConnectSuccess` - успешное переподключение
- `SessionExpired` - сессия истекла
- `Error` с кодом `INVALID_TOKEN`

---

### 5.2.4. SearchUsers (Поиск пользователей)

Ищет пользователей по имени (для добавления в контакты).

**Структура:**
```json
{
  "type": "searchUsers",
  "payload": {
    "query": "String"
  }
}
```

**Поля:**
- `query` (String) - поисковый запрос (минимум 1 символ)

**Требования:**
- Пользователь должен быть аутентифицирован

**Ответы:**
- `SearchResults` - список найденных пользователей
- `Error` с кодом `UNAUTHORIZED`

---

### 5.2.5. GetPublicKey (Получение публичных ключей)

Запрашивает публичный key bundle другого пользователя для установления E2E шифрования.

**Структура:**
```json
{
  "type": "getPublicKey",
  "payload": {
    "userId": "UUID_String"
  }
}
```

**Поля:**
- `userId` (String) - UUID пользователя, чьи ключи запрашиваются

**Требования:**
- Пользователь должен быть аутентифицирован

**Ответы:**
- `PublicKeyBundle` - ключи пользователя
- `Error` с кодом `USER_NOT_FOUND`, `KEY_BUNDLE_NOT_FOUND`

---

### 5.2.6. SendMessage (Отправка E2E-зашифрованного сообщения)

Отправляет E2E-зашифрованное сообщение другому пользователю.

**Структура:**
```json
{
  "type": "sendMessage",
  "payload": {
    "id": "UUID_String",
    "from": "UUID_String",
    "to": "UUID_String",
    "ephemeralPublicKey": [Binary 32 bytes],
    "messageNumber": 0,
    "content": "Base64_String",
    "timestamp": 1234567890
  }
}
```

**Поля:**
- `id` (String) - UUID сообщения (**генерируется клиентом** для offline-first и idempotency)
- `from` (String) - UUID отправителя
- `to` (String) - UUID получателя
- `ephemeralPublicKey` (Binary) - 32 байта эфемерного публичного ключа для Double Ratchet
- `messageNumber` (u32) - номер сообщения в цепочке для out-of-order обработки
- `content` (String) - Base64-кодированный зашифрованный контент (ChaCha20-Poly1305)
- `timestamp` (u64) - Unix timestamp в секундах

**Требования:**
- Пользователь должен быть аутентифицирован
- `from` должен совпадать с ID аутентифицированного пользователя
- Нельзя отправлять сообщения самому себе

**Rate Limiting:** 1000 сообщений/час

**Ответы:**
- `Ack` - подтверждение доставки
- `Error` с кодом `RECIPIENT_NOT_FOUND`, `RATE_LIMIT_EXCEEDED`

---

### 5.2.7. RotatePrekey (Ротация ключей)

Обновляет key bundle пользователя (для forward secrecy).

**⚠️ BREAKING CHANGE (v2.3):** Поле `update` теперь нативная структура `UploadableKeyBundle`, а не Base64-кодированная строка.

**Структура:**
```json
{
  "type": "rotatePrekey",
  "payload": {
    "userId": "UUID_String",
    "update": {
      "masterIdentityKey": "Base64<Bytes>",
      "bundleData": "Base64<Serialized_BundleData>",
      "signature": "Base64<Bytes>"
    }
  }
}
```

**Поля:**
- `userId` (String) - UUID пользователя (должен совпадать с аутентифицированным)
- `update` (UploadableKeyBundle) - нативная структура с новым key bundle

**Требования:**
- Пользователь должен быть аутентифицирован
- `userId` в bundle должен совпадать с аутентифицированным пользователем

**Rate Limiting:** 10 ротаций/день

**Ответы:**
- `KeyRotationSuccess` - успешная ротация
- `Error` с кодом `RATE_LIMIT_EXCEEDED`, `INVALID_KEY_BUNDLE`, `FORBIDDEN`

---

### 5.2.8. ChangePassword (Смена пароля)

Позволяет аутентифицированному пользователю изменить свой пароль.

**Структура запроса:**
```json
{
  "type": "changePassword",
  "payload": {
    "sessionToken": "String",
    "oldPassword": "String",
    "newPassword": "String",
    "newPasswordConfirm": "String"
  }
}
```

**Поля:**
- `sessionToken` - JWT токен текущей сессии (обязательно)
- `oldPassword` - Текущий пароль пользователя (обязательно)
- `newPassword` - Новый пароль (обязательно, минимум 8 символов)
- `newPasswordConfirm` - Подтверждение нового пароля (обязательно, должно совпадать с `newPassword`)

**Действия сервера:**
1. Проверить валидность JWT токена и извлечь `userId`
2. Проверить существование пользователя в БД
3. Проверить корректность старого пароля через bcrypt
4. Проверить, что `newPassword` совпадает с `newPasswordConfirm`
5. Проверить, что новый пароль отличается от старого
6. Проверить минимальную длину нового пароля (≥ 8 символов)
7. Обновить хеш пароля в БД (bcrypt с DEFAULT_COST)
8. Залогировать успешную смену пароля

**Успешный ответ:**
```json
{
  "type": "changePasswordSuccess"
}
```

**Коды ошибок:**

| Код ошибки | Описание |
|------------|----------|
| `INVALID_TOKEN` | JWT токен невалиден или просрочен |
| `INVALID_USER_ID` | Некорректный user_id в токене |
| `USER_NOT_FOUND` | Пользователь не найден в БД |
| `INVALID_PASSWORD` | Неправильный старый пароль |
| `PASSWORD_MISMATCH` | Новые пароли не совпадают |
| `SAME_PASSWORD` | Новый пароль совпадает со старым |
| `WEAK_PASSWORD` | Пароль короче 8 символов |
| `SERVER_ERROR` | Ошибка БД или сервера |

**Пример ошибки:**
```json
{
  "type": "error",
  "payload": {
    "code": "INVALID_PASSWORD",
    "message": "Old password is incorrect"
  }
}
```

**Рекомендации по безопасности для клиента:**
- ✅ Валидировать совпадение паролей на клиентской стороне перед отправкой
- ✅ Показывать индикатор силы пароля (длина, символы, цифры)
- ✅ Рекомендовать пароли длиной минимум 12 символов
- ✅ Использовать type="password" для полей ввода
- ✅ Очищать поля пароля после успешной смены
- ⚠️ НЕ хранить пароли в plaintext или localStorage
- ⚠️ НЕ передавать пароли через query parameters

**Примечания:**
- Операция требует валидный JWT токен текущей сессии
- После смены пароля текущая сессия остается активной
- Другие активные сессии пользователя НЕ аннулируются автоматически
- Сервер логирует операцию с учетом настройки приватности (`LOG_USER_IDENTIFIERS`)

---

### 5.2.9. Logout (Выход)

Завершает текущую сессию и отзывает JWT токен.

**Структура:**
```json
{
  "type": "logout",
  "payload": {
    "sessionToken": "String"
  }
}
```

**Поля:**
- `sessionToken` (String) - JWT токен текущей сессии

**Ответы:**
- `LogoutSuccess` - успешный выход

---

## 5.3. Серверные сообщения (Server → Client)

### 5.3.1. RegisterSuccess

Подтверждение успешной регистрации. Содержит данные нового пользователя и JWT токен.

**Структура:**
```json
{
  "type": "registerSuccess",
  "payload": {
    "userId": "UUID_String",
    "username": "String",
    "sessionToken": "JWT_String",
    "expires": 1234567890
  }
}
```

**Поля:**
- `userId` (String) - UUID созданного пользователя
- `username` (String) - имя пользователя
- `sessionToken` (String) - JWT токен для последующих запросов
- `expires` (i64) - Unix timestamp когда токен истечет

**Действия клиента:**
1. Сохранить `sessionToken` для последующих запросов
2. Сохранить `userId` для идентификации
3. Переключиться на главный экран приложения

**Пример:**
```json
{
  "type": "registerSuccess",
  "payload": {
    "userId": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "sessionToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI1NTBlODQwMC1lMjliLTQxZDQtYTcxNi00NDY2NTU0NDAwMDAiLCJqdGkiOiJhYmMxMjMiLCJleHAiOjE3MzU2ODk2MDB9.signature",
    "expires": 1735689600
  }
}
```

---

### 5.3.2. LoginSuccess

Подтверждение успешного входа.

**Структура:**
```json
{
  "type": "loginSuccess",
  "payload": {
    "userId": "UUID_String",
    "username": "String",
    "sessionToken": "JWT_String",
    "expires": 1234567890
  }
}
```

**Поля:**
- `userId` (String) - UUID пользователя
- `username` (String) - имя пользователя
- `sessionToken` (String) - JWT токен для последующих запросов
- `expires` (i64) - Unix timestamp когда токен истечет

**Пример:**
```json
{
  "type": "loginSuccess",
  "payload": {
    "userId": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "sessionToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires": 1735689600
  }
}
```

---

### 5.3.3. ConnectSuccess

Подтверждение успешного переподключения с существующим токеном.

**Структура:**
```json
{
  "type": "connectSuccess",
  "payload": {
    "userId": "UUID_String",
    "username": "String"
  }
}
```

**Поля:**
- `userId` (String) - UUID пользователя
- `username` (String) - имя пользователя

**Примечание:** НЕ содержит новый токен - используется существующий

**Пример:**
```json
{
  "type": "connectSuccess",
  "payload": {
    "userId": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice"
  }
}
```

---

### 5.3.4. SessionExpired

Сообщает, что сессия истекла и требуется повторный вход.

**Структура:**
```json
{
  "type": "sessionExpired"
}
```

**Без payload** (unit variant)

**Действия клиента:**
1. Очистить сохраненный `sessionToken`
2. Перенаправить пользователя на экран входа

**Пример:**
```json
{
  "type": "sessionExpired"
}
```

---

### 5.3.5. SearchResults

Результаты поиска пользователей.

**Структура:**
```json
{
  "type": "searchResults",
  "payload": {
    "users": [
      {
        "id": "UUID_String",
        "username": "String"
      }
    ]
  }
}
```

**Поля:**
- `users` (Array) - массив найденных пользователей
  - `id` (String) - UUID пользователя
  - `username` (String) - имя пользователя

**Пример:**
```json
{
  "type": "searchResults",
  "payload": {
    "users": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "username": "alice"
      },
      {
        "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        "username": "alice_smith"
      }
    ]
  }
}
```

---

### 5.3.6. PublicKeyBundle

Публичный key bundle запрошенного пользователя для установления E2E шифрования.

**Структура:**
```json
{
  "type": "publicKeyBundle",
  "payload": {
    "userId": "UUID_String",
    "username": "String",
    "identityPublic": "Base64_String",
    "signedPrekeyPublic": "Base64_String",
    "signature": "Base64_String",
    "verifyingKey": "Base64_String"
  }
}
```

**Поля:**
- `userId` (String) - UUID владельца ключей
- `username` (String) - имя пользователя для отображения (передается **только** при обмене ключами, **НЕ** в сообщениях - Signal-подобная приватность)
- `identityPublic` (String) - Base64-кодированный публичный identity key X25519 (32 байта)
- `signedPrekeyPublic` (String) - Base64-кодированный signed prekey X25519 (32 байта)
- `signature` (String) - Base64-кодированная Ed25519 подпись (64 байта)
- `verifyingKey` (String) - Base64-кодированный Ed25519 verifying key (32 байта)

**Примечание:** Это устаревший формат. Новые клиенты должны использовать `GET /keys/{userId}` HTTP endpoint для получения `UploadableKeyBundle` с поддержкой crypto-agility.

**Privacy Note:** Username передается только при первом обмене ключами (key exchange), а затем сохраняется локально на устройстве. В самих сообщениях username **НЕ** передается - только UUID. Это минимизирует метаданные и повышает приватность (аналогично Signal Protocol).

**Пример:**
```json
{
  "type": "publicKeyBundle",
  "payload": {
    "userId": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "identityPublic": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    "signedPrekeyPublic": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
    "signature": "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
    "verifyingKey": "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
  }
}
```

---

### 5.3.7. Message

Входящее E2E-зашифрованное сообщение от другого пользователя.

**Структура:**
```json
{
  "type": "message",
  "payload": {
    "id": "UUID_String",
    "from": "UUID_String",
    "to": "UUID_String",
    "ephemeralPublicKey": [Binary 32 bytes],
    "messageNumber": 0,
    "content": "Base64_String",
    "timestamp": 1234567890
  }
}
```

**Поля:** (идентичны `SendMessage`)
- `id` (String) - UUID сообщения
- `from` (String) - UUID отправителя
- `to` (String) - UUID получателя (должен быть текущий пользователь)
- `ephemeralPublicKey` (Binary) - 32 байта эфемерного ключа
- `messageNumber` (u32) - номер сообщения в цепочке
- `content` (String) - Base64-кодированный зашифрованный контент
- `timestamp` (u64) - Unix timestamp отправки

**Действия клиента:**
1. Расшифровать `content` используя Double Ratchet
2. Проверить `messageNumber` для out-of-order обработки
3. Отобразить сообщение пользователю

**Пример (в MessagePack `ephemeralPublicKey` - бинарные данные, здесь показано как массив байт):**
```json
{
  "type": "message",
  "payload": {
    "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
    "from": "550e8400-e29b-41d4-a716-446655440000",
    "to": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "ephemeralPublicKey": "<32 bytes binary>",
    "messageNumber": 42,
    "content": "aGVsbG8gd29ybGQhISE=",
    "timestamp": 1735689600
  }
}
```

---

### 5.3.8. Ack

Подтверждение доставки сообщения.

**Структура:**
```json
{
  "type": "ack",
  "payload": {
    "messageId": "UUID_String",
    "status": "String"
  }
}
```

**Поля:**
- `messageId` (String) - UUID сообщения, для которого отправляется подтверждение
- `status` (String) - статус доставки (например: "delivered", "queued")

**Пример:**
```json
{
  "type": "ack",
  "payload": {
    "messageId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
    "status": "delivered"
  }
}
```

---

### 5.3.9. KeyRotationSuccess

Подтверждение успешной ротации ключей.

**Структура:**
```json
{
  "type": "keyRotationSuccess"
}
```

**Без payload** (unit variant)

**Действия клиента:**
1. Обновить локальное состояние key bundle
2. Показать пользователю уведомление об успешной ротации (опционально)

**Пример:**
```json
{
  "type": "keyRotationSuccess"
}
```

---

### 5.3.10. ChangePasswordSuccess

Подтверждение успешной смены пароля.

**Структура:**
```json
{
  "type": "changePasswordSuccess"
}
```

**Без payload** (unit variant)

**Действия клиента:**
1. Очистить поля ввода паролей
2. Показать уведомление об успешной смене пароля
3. Обновить локальное хранилище если требуется

**Пример:**
```json
{
  "type": "changePasswordSuccess"
}
```

---

### 5.3.11. LogoutSuccess

Подтверждение успешного выхода.

**Структура:**
```json
{
  "type": "logoutSuccess"
}
```

**Без payload** (unit variant)

**Действия клиента:**
1. Очистить сохраненный `sessionToken`
2. Закрыть WebSocket соединение
3. Перенаправить на экран входа

**Пример:**
```json
{
  "type": "logoutSuccess"
}
```

---

### 5.3.12. Error

Сообщение об ошибке при обработке запроса.

**Структура:**
```json
{
  "type": "error",
  "payload": {
    "code": "String",
    "message": "String"
  }
}
```

**Поля:**
- `code` (String) - код ошибки для программной обработки
- `message` (String) - человекочитаемое описание ошибки

**Распространенные коды ошибок:**

| Код | Описание |
|-----|----------|
| `INVALID_CREDENTIALS` | Неверное имя пользователя или пароль |
| `INVALID_TOKEN` | JWT токен невалиден или просрочен |
| `INVALID_USER_ID` | Некорректный формат user ID |
| `USER_NOT_FOUND` | Пользователь не найден |
| `RECIPIENT_NOT_FOUND` | Получатель сообщения не найден |
| `SESSION_EXPIRED` | Сессия истекла |
| `REGISTRATION_FAILED` | Ошибка регистрации (username занят или невалидные данные) |
| `WEAK_PASSWORD` | Пароль не соответствует требованиям сложности |
| `INVALID_PASSWORD` | Неверный текущий пароль при смене |
| `PASSWORD_MISMATCH` | Новые пароли не совпадают |
| `SAME_PASSWORD` | Новый пароль совпадает со старым |
| `INVALID_KEY_BUNDLE` | Невалидный формат key bundle |
| `RATE_LIMIT_EXCEEDED` | Превышен лимит запросов |
| `FORBIDDEN` | Операция запрещена (например, попытка изменить чужие ключи) |
| `SERVER_ERROR` | Внутренняя ошибка сервера |
| `INVALID_FORMAT` | Невалидный формат сообщения |

**Примеры:**
```json
{
  "type": "error",
  "payload": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many failed login attempts. Try again in 15 minutes."
  }
}
```

```json
{
  "type": "error",
  "payload": {
    "code": "WEAK_PASSWORD",
    "message": "Password must be at least 10 characters long"
  }
}
```

---

## 6. Концепция "Пролога" (Prologue)

Это **обязанность клиента**, сервер не участвует в этом процессе.

- **Рекомендация:** Перед выполнением протокола обмена ключами (X3DH) клиенты должны сформировать строку для разделения доменов (domain separation), например:
  ```
  construct-key-agreement:sender_id->recipient_id
  ```
- Хэш этой строки должен быть использован как "ассоциированные данные" (AD) при AEAD-шифровании или включен в KDF (Key Derivation Function) для выработки сессионного ключа.
- Это защищает от атак подмены контекста (context confusion attacks).


## 7. Encrypted Client Hello (ECH)

Это **задача конфигурации TLS-терминатора**, а не API.

- **Требование:** Веб-сервер (nginx, caddy) или TLS-терминатор, используемый для развертывания, должен быть сконфигурирован для поддержки ECH (Encrypted Client Hello), как только эта технология станет общедоступной и стабильной в используемом ПО.
- ECH скрывает SNI (Server Name Indication) от наблюдателей сети, повышая приватность соединений.

---

## 8. Изменения версий

### Версия 2.4 (2025-12-26) - Актуализация

**Что изменилось:**
- ✅ **Message ID**: Уточнено, что `id` сообщений генерируется **клиентом** (не сервером) для offline-first и idempotency
- ✅ **PublicKeyBundle.username**: Добавлено поле `username` в ответ `PublicKeyBundle` для Signal-подобной приватности
  - Username передается **только** при обмене ключами (key exchange)
  - В самих сообщениях username **НЕ** передается - только UUID
  - Это минимизирует метаданные и повышает приватность
- ✅ Обновлены примеры сообщений
