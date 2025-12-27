# 🧪 Testing Guide для Construct Messenger

**Дата:** 26 декабря 2025

---

## 📋 Оглавление

1. [Структура тестов](#структура-тестов)
2. [Настройка Test Target в Xcode](#настройка-test-target-в-xcode)
3. [Запуск тестов](#запуск-тестов)
4. [Типы тестов](#типы-тестов)
5. [Покрытие кода](#покрытие-кода)

---

## 🏗️ Структура тестов

```
construct-messenger/
├── ConstructMessengerTests/       # 📦 iOS Unit Tests
│   ├── CryptoManagerTests.swift  # Тесты криптографии
│   └── ViewModelTests.swift      # Тесты ViewModels
│
├── packages/core/tests/          # 🦀 Rust Unit Tests (TODO)
│   └── crypto_tests.rs
│
└── packages/server/tests/        # 🦀 Server Integration Tests (TODO)
    └── handlers_tests.rs
```

---

## 🛠️ Настройка Test Target в Xcode

### Шаг 1: Создать Test Target

1. Откройте `ConstructMessenger.xcodeproj` в Xcode
2. **File → New → Target...**
3. Выберите **iOS → Test → Unit Testing Bundle**
4. Настройки:
   - **Product Name:** `ConstructMessengerTests`
   - **Organization Identifier:** (ваш identifier)
   - **Team:** (ваша команда)
   - **Project:** `ConstructMessenger`
   - **Target to be Tested:** `ConstructMessenger`
5. Нажмите **Finish**

### Шаг 2: Добавить существующие тестовые файлы

1. В Project Navigator, **правый клик на ConstructMessengerTests** → **Add Files to "ConstructMessenger"...**
2. Выберите файлы:
   - `/ConstructMessengerTests/CryptoManagerTests.swift`
   - `/ConstructMessengerTests/ViewModelTests.swift`
3. **Options:**
   - ✅ **Copy items if needed** (НЕ отмечать - файлы уже на месте)
   - ✅ **Create groups**
   - ✅ **Add to targets:** `ConstructMessengerTests`
4. Нажмите **Add**

### Шаг 3: Настроить Build Settings

1. Выберите **ConstructMessenger** project
2. Выберите **ConstructMessengerTests** target
3. **Build Settings** → Search: "testability"
4. Найдите **Enable Testability** → установите **Yes**

### Шаг 4: Добавить зависимости

Убедитесь, что test target имеет доступ к:
- `libconstruct_core.a` (Rust библиотека)
- `construct_core.swift` (UniFFI bindings)
- Core Data model

**Build Phases → Link Binary With Libraries:**
- ✅ `libconstruct_core.a`
- ✅ CoreData.framework
- ✅ Combine.framework

---

## ▶️ Запуск тестов

### В Xcode

**Все тесты:**
```
⌘U (Command + U)
```

**Один тест:**
1. Откройте тестовый файл
2. Кликните на **ромбик** слева от имени теста
3. Или поместите курсор в функцию теста и нажмите **⌃⌥⌘U**

**Один класс тестов:**
- Кликните на ромбик слева от `class CryptoManagerTests`

### Через терминал (xcodebuild)

```bash
cd /Users/maximeliseyev/Code/construct-messenger

# Запустить все тесты
xcodebuild test \
  -project ConstructMessenger.xcodeproj \
  -scheme ConstructMessenger \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'

# Только unit tests
xcodebuild test \
  -project ConstructMessenger.xcodeproj \
  -scheme ConstructMessenger \
  -only-testing:ConstructMessengerTests
```

---

## 🧪 Типы тестов

### 1. Unit Tests (CryptoManagerTests.swift)

**Что тестируется:**
- ✅ Export registration bundle
- ✅ Session initialization
- ✅ Encryption/decryption roundtrip
- ✅ Error handling (no session, invalid data)
- ✅ Session management (hasSession)
- ✅ Performance (encryption, bundle generation)

**Запуск:**
```bash
# В Xcode
Product → Test (⌘U)

# Или конкретный тест
⌃⌥⌘U на функции testEncryptDecryptRoundtrip()
```

**Пример теста:**
```swift
func testExportRegistrationBundle() throws {
    let bundleJSON = try cryptoManager.exportRegistrationBundle()

    XCTAssertFalse(bundleJSON.isEmpty)
    XCTAssertTrue(bundleJSON.contains("identityPublic"))
    XCTAssertTrue(bundleJSON.contains("signature"))
}
```

---

### 2. ViewModel Tests (ViewModelTests.swift)

**Что тестируется:**
- ✅ ChatsViewModel: initialization, search, create/delete chats
- ✅ ChatViewModel: initialization, send message, load messages
- ✅ AuthViewModel: initialization, validation logic
- ✅ Performance: loading 100+ messages

**In-Memory Core Data:**
```swift
let container = NSPersistentContainer(name: "ConstructMessenger")
let description = NSPersistentStoreDescription()
description.type = NSInMemoryStoreType  // ✅ Не затрагивает реальные данные
```

**Пример теста:**
```swift
func testChatsViewModel_StartChat() {
    let user = PublicUserInfo(id: UUID().uuidString, username: "testuser")
    let chat = viewModel.startChat(with: user)

    XCTAssertNotNil(chat)
    XCTAssertEqual(chat?.otherUser?.username, "testuser")
}
```

---

### 3. Integration Tests (TODO)

**Что нужно тестировать:**
- ✅ Полный flow: регистрация → инициализация сессии → отправка → расшифровка
- ✅ WebSocket подключение и обмен сообщениями
- ✅ Rust ↔ Swift взаимодействие через UniFFI

**Пример будущего теста:**
```swift
func testFullMessageFlow() async throws {
    // Alice registers
    let alice = try await registerUser(username: "alice", password: "Alice123!")

    // Bob registers
    let bob = try await registerUser(username: "bob", password: "Bob123!")

    // Alice sends message to Bob
    let message = try await alice.sendMessage("Hello Bob!", to: bob.userId)

    // Bob receives and decrypts
    let decrypted = try await bob.receiveMessage(message)

    XCTAssertEqual(decrypted, "Hello Bob!")
}
```

---

### 4. Rust Tests (TODO)

**В packages/core:**
```bash
cd packages/core
cargo test --all-features

# С логами
cargo test -- --nocapture

# Конкретный модуль
cargo test crypto::double_ratchet::tests
```

**Нужно создать:**
```rust
// packages/core/src/crypto/double_ratchet.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ratchet_step() {
        let mut session = DoubleRatchetSession::<ClassicSuiteProvider>::new(...);

        let encrypted = session.encrypt(b"test message").unwrap();
        let decrypted = session.decrypt(&encrypted).unwrap();

        assert_eq!(decrypted, b"test message");
    }
}
```

---

## 📊 Покрытие кода (Code Coverage)

### Включить Code Coverage в Xcode

1. **Product → Scheme → Edit Scheme... (⌘<)**
2. **Test** (левая панель)
3. **Options** (верхняя вкладка)
4. ✅ **Code Coverage** → **Gather coverage for all targets**
5. **Close**

### Просмотр покрытия

1. Запустите тесты (**⌘U**)
2. **View → Navigators → Reports (⌘9)**
3. Кликните на последний test run
4. Вкладка **Coverage**

**Целевое покрытие:**
- CryptoManager: **≥ 80%**
- ViewModels: **≥ 70%**
- Rust core: **≥ 90%** (критичная криптография)

---

## 🎯 Приоритеты тестирования

### Критично (должно быть 100% покрыто)
- ✅ CryptoManager (encryption/decryption)
- ✅ Double Ratchet logic (Rust)
- ✅ X3DH key agreement (Rust)
- ✅ Session initialization

### Важно (≥ 80% покрытие)
- ⚠️ ViewModels (ChatsViewModel, ChatViewModel)
- ⚠️ Message parsing (MessagePack)
- ⚠️ Core Data operations

### Желательно (≥ 60% покрытие)
- 🟡 UI Components (SwiftUI Views)
- 🟡 WebSocket manager
- 🟡 SessionManager

---

## 🐛 Debugging тестов

### Breakpoints в тестах

1. Поставьте breakpoint в тестовом методе
2. **Product → Test** (⌘U)
3. Выполнение остановится на breakpoint
4. Используйте Debug Area для инспекции

### Логирование

```swift
func testSomething() {
    print("DEBUG: Starting test")

    let result = cryptoManager.doSomething()

    print("DEBUG: Result = \(result)")
    XCTAssertNotNil(result)
}
```

**В Xcode Console:**
```
Test Suite 'Selected tests' started at 2025-12-26 21:00:00.000
DEBUG: Starting test
DEBUG: Result = <value>
Test Case 'testSomething' passed (0.123 seconds)
```

---

## 📝 Best Practices

### 1. AAA Pattern (Arrange-Act-Assert)
```swift
func testExample() {
    // Arrange (setup)
    let user = createTestUser()

    // Act (execute)
    let result = viewModel.doAction(user)

    // Assert (verify)
    XCTAssertEqual(result, expectedValue)
}
```

### 2. Изоляция тестов
- ✅ Каждый тест независим
- ✅ `setUp()` создает чистое состояние
- ✅ `tearDown()` очищает ресурсы
- ❌ НЕ использовать shared state между тестами

### 3. Meaningful test names
```swift
// ✅ Good
func testEncryptDecryptRoundtrip_WithValidData_ReturnsOriginalPlaintext()

// ❌ Bad
func test1()
```

### 4. Test Doubles
```swift
// Mock для тестирования без реального WebSocket
class MockWebSocketManager: WebSocketManager {
    var messageSent: ChatMessage?

    override func send(_ message: ClientMessage) {
        if case .sendMessage(let chatMessage) = message {
            messageSent = chatMessage
        }
    }
}
```

---

## 🔗 Ссылки

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Rust Testing](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [ROADMAP.md](./ROADMAP.md) - План добавления тестов (Phase 1, Priority 3)

---

## 📅 TODO: Roadmap для тестирования

### Phase 1 (Январь 2026)
- [x] Создать CryptoManagerTests.swift
- [x] Создать ViewModelTests.swift
- [ ] Добавить test target в Xcode
- [ ] Добить coverage ≥ 60%

### Phase 2 (Февраль 2026)
- [ ] Rust unit tests для crypto modules
- [ ] Integration tests (WebSocket + E2E flow)
- [ ] Coverage ≥ 80%

### Phase 3 (Март 2026)
- [ ] UI Tests (XCUITest)
- [ ] Performance tests
- [ ] Stress testing (1000+ messages)

---

**Дата последнего обновления:** 26 декабря 2025
**Текущее покрытие:** 0% (тесты созданы, но не добавлены в Xcode проект)
**Целевое покрытие к Q1 2026:** 80%
