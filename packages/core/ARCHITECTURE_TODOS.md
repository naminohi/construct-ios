# Architecture TODOs

Этот файл содержит список архитектурных проблем и технического долга в кодовой базе.

## 1. Generic Types Mismatch: KeyManager vs Client

**Приоритет:** HIGH
**Сложность:** MEDIUM
**Статус:** Требует рефакторинга

### Проблема

`KeyManager` и `Client` имеют несовместимые generic параметры, что приводит к невозможности корректно экспортировать registration bundle.

**Детали:**
- `KeyManager<P>` - generic только по `CryptoProvider`
- `Client<P, H, M>` - generic по `CryptoProvider`, `HandshakeProtocol`, и `MessagingProtocol`
- `KeyManager::export_registration_bundle()` возвращает конкретный тип `X3DHPublicKeyBundle`
- `Client::get_registration_bundle()` должен возвращать generic `H::RegistrationBundle`
- **Type mismatch** делает невозможным вызов метода KeyManager из Client

### Последствия

1. **Неправильное поведение API:**
   - `Client::get_registration_bundle()` генерирует **новые** ключи вместо экспорта существующих
   - Это критический баг - bundle не соответствует ключам клиента!

2. **Необходимость workaround:**
   - В `uniffi_bindings.rs` приходится напрямую вызывать `key_manager().export_registration_bundle()`
   - Обходим публичный API Client
   - Нарушает инкапсуляцию

3. **Потенциальные ошибки:**
   - Разработчики могут случайно использовать `client.get_registration_bundle()`
   - Получат bundle с неправильными ключами
   - Криптографический handshake будет невозможен

### Затронутые файлы

- `src/crypto/keys.rs:184-236` - KeyManager::export_registration_bundle()
- `src/crypto/client_api.rs:137-163` - Client::get_registration_bundle()
- `src/uniffi_bindings.rs:93-120` - Workaround в export_registration_bundle_json()

### Решения

#### Вариант 1: Сделать KeyManager generic по handshake protocol (РЕКОМЕНДУЕТСЯ)

**Плюсы:**
- ✅ Type-safe - компилятор проверит корректность типов
- ✅ Generic design - поддержка разных handshake протоколов (X3DH, PQ-X3DH)
- ✅ Client::get_registration_bundle() сможет корректно вызывать KeyManager
- ✅ Нет необходимости в workaround

**Минусы:**
- ❌ Требует обновить все использования KeyManager
- ❌ Увеличивает сложность generic параметров

**Код:**
```rust
// Было:
pub struct KeyManager<P: CryptoProvider> { ... }

// Стало:
pub struct KeyManager<P: CryptoProvider, H: KeyAgreement<P>> { ... }

impl<P, H> KeyManager<P, H> {
    pub fn export_registration_bundle(&self) -> Result<H::RegistrationBundle> {
        H::export_from_key_manager(self)
    }
}
```

**Что нужно сделать:**
1. Добавить в `trait KeyAgreement` метод:
   ```rust
   fn export_from_key_manager(km: &KeyManager<P>) -> Result<Self::RegistrationBundle>;
   ```
2. Обновить определение `KeyManager<P>` -> `KeyManager<P, H>`
3. Обновить `Client<P, H, M>` чтобы использовал `KeyManager<P, H>`
4. Найти и обновить все использования `KeyManager` в кодовой базе
5. Убрать workaround из `uniffi_bindings.rs`
6. Удалить предупреждающие комментарии из `Client::get_registration_bundle()`

#### Вариант 2: Добавить trait method без изменения KeyManager

**Плюсы:**
- ✅ Меньше изменений в коде
- ✅ KeyManager остаётся простым

**Минусы:**
- ❌ Менее type-safe
- ❌ Нужно передавать KeyManager в trait method
- ❌ Дублирование логики экспорта

**Код:**
```rust
trait KeyAgreement<P: CryptoProvider> {
    fn export_from_key_manager(
        identity: &P::KemPublicKey,
        signed_prekey: &P::KemPublicKey,
        signature: &[u8],
        verifying_key: &P::SignaturePublicKey,
        suite_id: u16
    ) -> Result<Self::RegistrationBundle>;
}

impl Client<P, H, M> {
    pub fn get_registration_bundle(&self) -> Result<H::RegistrationBundle> {
        let identity = self.key_manager.identity_public_key()?;
        let prekey = self.key_manager.current_signed_prekey()?;
        let verifying_key = self.key_manager.verifying_key()?;

        H::export_from_key_manager(
            identity,
            &prekey.key_pair.1,
            &prekey.signature,
            verifying_key,
            P::suite_id()
        )
    }
}
```

#### Вариант 3: Убрать generic из Client::get_registration_bundle()

**Плюсы:**
- ✅ Минимальные изменения

**Минусы:**
- ❌ Нарушает generic design
- ❌ Client становится hardcoded для X3DH
- ❌ Невозможно поддерживать другие handshake протоколы

**Не рекомендуется.**

### План миграции (Вариант 1)

1. **Фаза 1: Добавить метод в trait** (не ломает существующий код)
   ```rust
   trait KeyAgreement<P: CryptoProvider> {
       fn export_from_key_manager(km: &KeyManager<P>) -> Result<Self::RegistrationBundle>;
   }
   ```

2. **Фаза 2: Реализовать для X3DH** (тестируем новый подход)
   ```rust
   impl<P: CryptoProvider> KeyAgreement<P> for X3DHProtocol<P> {
       fn export_from_key_manager(km: &KeyManager<P>) -> Result<Self::RegistrationBundle> {
           km.export_registration_bundle()
       }
   }
   ```

3. **Фаза 3: Обновить KeyManager** (добавляем generic параметр)
   ```rust
   pub struct KeyManager<P: CryptoProvider, H: KeyAgreement<P>> { ... }
   ```

4. **Фаза 4: Найти и обновить все использования**
   ```bash
   git grep -n "KeyManager<" packages/core/src/
   ```

5. **Фаза 5: Обновить Client**
   ```rust
   pub struct Client<P, H, M> {
       key_manager: KeyManager<P, H>,
       ...
   }
   ```

6. **Фаза 6: Убрать workaround**
   - Удалить TODO комментарии
   - Вернуть использование `client.get_registration_bundle()` в uniffi_bindings.rs

7. **Фаза 7: Тестирование**
   - Убедиться что все unit tests проходят
   - Протестировать UniFFI bindings
   - Проверить Swift/iOS интеграцию

### Оценка времени

- Вариант 1: ~4-6 часов (включая тестирование)
- Вариант 2: ~2-3 часа
- Вариант 3: ~1 час (не рекомендуется)

### Риски

- **LOW**: Все изменения локальны в crypto модуле
- **MEDIUM**: Нужно обновить много мест использования KeyManager
- **LOW**: Существующие тесты покрывают основной функционал

---

## 2. Другие архитектурные TODOs

_(Добавляйте сюда новые архитектурные проблемы по мере обнаружения)_

---

## Как работать с этим документом

1. **При обнаружении архитектурной проблемы:**
   - Добавьте её в этот файл
   - Добавьте TODO комментарии в код со ссылкой на этот файл
   - Оцените приоритет и сложность

2. **При планировании рефакторинга:**
   - Выберите задачу по приоритету
   - Прочитайте описание проблемы и решения
   - Следуйте плану миграции

3. **После завершения рефакторинга:**
   - Отметьте задачу как DONE
   - Удалите TODO комментарии из кода
   - Опишите что было сделано

---

**Последнее обновление:** 2025-12-29
