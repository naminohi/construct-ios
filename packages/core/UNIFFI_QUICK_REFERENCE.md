# UniFFI Quick Reference

## 🚀 Быстрый старт

### Проверить здоровье системы
```bash
./check_uniffi_health.sh
```

### Генерация Swift биндингов для iOS
```bash
uniffi-bindgen generate --language swift \
  src/construct_core.udl \
  --out-dir ../ios/ConstructCore/Generated
```

### Сборка и тесты
```bash
# Сборка Rust library
cargo build --lib

# Запуск тестов
cargo test --lib

# Очистка и пересборка (если проблемы)
cargo clean && cargo build --lib
```

## 📋 Текущая конфигурация

| Параметр | Значение |
|----------|----------|
| **UniFFI версия** | 0.28.3 |
| **Python uniffi-bindgen** | 0.28.3 |
| **Rust версия** | 1.92.0 |
| **Build patching** | ✅ Включен |

## ⚠️ Известные проблемы

### 1. Rust 1.82+ unsafe attributes

**Проблема:** UniFFI 0.28.x генерирует `#[no_mangle]`, а Rust 1.82+ требует `#[unsafe(no_mangle)]`

**Решение:** ✅ Автоматический патчинг в `build.rs`

```rust
// build.rs автоматически патчит:
#[no_mangle]           →  #[unsafe(no_mangle)]
#[export_name = "..."] →  #[unsafe(export_name = "...")]
```

### 2. Python uniffi-bindgen устарел

**Проблема:** Python пакет не обновляется с 2023 года (застрял на 0.28.3)

**Решение:**
- **Краткосрочно:** Используем текущую версию 0.28.3 (совместима)
- **Долгосрочно:** Миграция на UniFFI 0.30+ с Rust CLI (см. UNIFFI_VERSION_GUIDE.md)

## 🔧 Полезные команды

### Диагностика
```bash
# Проверить версию Rust uniffi
cargo tree -i uniffi | head -2

# Проверить версию Python uniffi-bindgen
uniffi-bindgen --version

# Проверить Rust версию
rustc --version
```

### Генерация биндингов
```bash
# Swift (iOS/macOS)
uniffi-bindgen generate --language swift src/construct_core.udl --out-dir /tmp/test

# Kotlin (Android - будущее)
uniffi-bindgen generate --language kotlin src/construct_core.udl --out-dir /tmp/test

# Python (для тестирования)
uniffi-bindgen generate --language python src/construct_core.udl --out-dir /tmp/test
```

### Troubleshooting
```bash
# Если сборка не работает:
cargo clean
cargo update
cargo build --lib

# Если Python uniffi-bindgen не найден:
pip3 install uniffi-bindgen==0.28.3

# Если патчинг не работает:
./patch_uniffi_unsafe.sh
```

## 📚 Дополнительная информация

- **Подробная документация:** [UNIFFI_VERSION_GUIDE.md](../../UNIFFI_VERSION_GUIDE.md)
- **Официальная документация:** https://mozilla.github.io/uniffi-rs/
- **GitHub:** https://github.com/mozilla/uniffi-rs

## 🎯 Что делать при обновлении

### Обновление Rust зависимостей
```bash
cargo update
./check_uniffi_health.sh  # Проверить после обновления
```

### Обновление .udl файла
```bash
# После изменения construct_core.udl:
cargo clean
cargo build --lib
uniffi-bindgen generate --language swift src/construct_core.udl --out-dir ../ios/
```

### Миграция на новую версию UniFFI
См. раздел "План миграции на UniFFI 0.30+" в [UNIFFI_VERSION_GUIDE.md](../../UNIFFI_VERSION_GUIDE.md)

---

**Последнее обновление:** 2026-01-10
**Статус:** ✅ Система работает стабильно
