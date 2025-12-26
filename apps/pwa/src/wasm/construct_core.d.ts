/* tslint:disable */
/* eslint-disable */

export class MessengerAPI {
  private constructor();
  free(): void;
  [Symbol.dispose](): void;
}

/**
 * Добавить контакт
 */
export function app_state_add_contact(state_id: string, contact_id: string, username: string): Promise<void>;

/**
 * Подключиться к WebSocket серверу с полной интеграцией callbacks
 */
export function app_state_connect(state_id: string, server_url: string): Promise<void>;

/**
 * Получить состояние подключения
 */
export function app_state_connection_state(state_id: string): string;

/**
 * Отключиться от WebSocket сервера
 */
export function app_state_disconnect(state_id: string): Promise<void>;

/**
 * Завершить регистрацию после получения UUID от сервера
 */
export function app_state_finalize_registration(state_id: string, server_user_id: string, session_token: string, password: string): Promise<void>;

/**
 * Получить список всех контактов (JSON)
 */
export function app_state_get_contacts(state_id: string): string;

/**
 * Получить user_id текущего пользователя
 */
export function app_state_get_user_id(state_id: string): string | undefined;

/**
 * Получить username текущего пользователя
 */
export function app_state_get_username(state_id: string): string | undefined;

/**
 * Инициализировать нового пользователя (только создать ключи, не сохранять)
 */
export function app_state_initialize_user(state_id: string, username: string, password: string): Promise<void>;

/**
 * Загрузить беседу с контактом (JSON)
 */
export function app_state_load_conversation(state_id: string, contact_id: string): Promise<string>;

/**
 * Загрузить существующего пользователя
 */
export function app_state_load_user(state_id: string, user_id: string, password: string): Promise<void>;

/**
 * Получить количество попыток переподключения
 */
export function app_state_reconnect_attempts(state_id: string): number;

/**
 * Зарегистрировать пользователя на сервере
 * Отправляет сообщение Register с username, password и registration bundle
 */
export function app_state_register_on_server(state_id: string, password: string): void;

/**
 * Сбросить счётчик попыток переподключения
 */
export function app_state_reset_reconnect(state_id: string): void;

/**
 * Отправить сообщение
 */
export function app_state_send_message(state_id: string, to: string, session_id: string, text: string): Promise<string>;

/**
 * Включить/выключить автоматическое переподключение
 */
export function app_state_set_auto_reconnect(state_id: string, enabled: boolean): void;

/**
 * Конвертировать base64 в байты
 */
export function base64_to_bytes(base64_str: string): Uint8Array;

/**
 * Конвертировать байты в base64
 */
export function bytes_to_base64(bytes: Uint8Array): string;

/**
 * Добавить контакт
 */
export function contact_manager_add_contact(manager_id: string, contact_id: string, username: string): void;

/**
 * Получить все контакты (JSON array)
 */
export function contact_manager_get_all_contacts(manager_id: string): string;

/**
 * Получить контакт по ID (JSON)
 */
export function contact_manager_get_contact(manager_id: string, contact_id: string): string;

/**
 * Удалить контакт
 */
export function contact_manager_remove_contact(manager_id: string, contact_id: string): void;

/**
 * Поиск контактов по username
 */
export function contact_manager_search_contacts(manager_id: string, query: string): string;

/**
 * Создать новый AppState
 */
export function create_app_state(_db_name: string): Promise<string>;

/**
 * Создать новый ContactManager
 */
export function create_contact_manager(): string;

/**
 * Создать нового криптографического клиента
 */
export function create_crypto_client(): string;

/**
 * Создать новый CryptoManager
 */
export function create_crypto_manager(): string;

/**
 * Экспортировать registration bundle в JSON
 */
export function crypto_manager_get_registration_bundle(manager_id: string): string;

/**
 * Экспортировать registration bundle в base64 формате
 */
export function crypto_manager_get_registration_bundle_b64(manager_id: string): string;

/**
 * Проверить наличие сессии
 */
export function crypto_manager_has_session(manager_id: string, contact_id: string): boolean;

/**
 * Ротация prekey
 */
export function crypto_manager_rotate_prekey(manager_id: string): void;

/**
 * Получить текущий timestamp в секундах
 */
export function current_timestamp(): bigint;

/**
 * Расшифровать сообщение
 * encrypted_json - JSON строка с зашифрованным сообщением
 * Возвращает расшифрованный текст
 */
export function decrypt_message(client_id: string, session_id: string, encrypted_json: string): string;

/**
 * Удалить AppState из памяти
 */
export function destroy_app_state(state_id: string): void;

/**
 * Удалить клиента из памяти
 */
export function destroy_client(client_id: string): void;

/**
 * Удалить ContactManager
 */
export function destroy_contact_manager(manager_id: string): void;

/**
 * Удалить CryptoManager
 */
export function destroy_crypto_manager(manager_id: string): void;

/**
 * Зашифровать сообщение
 * Возвращает JSON с зашифрованным сообщением
 */
export function encrypt_message(client_id: string, session_id: string, plaintext: string): string;

/**
 * Генерировать случайные байты
 */
export function generate_random_bytes(len: number): Uint8Array;

/**
 * Генерировать UUID v4
 */
export function generate_uuid(): string;

/**
 * Получить публичные ключи клиента для регистрации (JSON)
 */
export function get_registration_bundle(client_id: string): string;

export function init(): void;

/**
 * Инициализировать сессию получателя при получении первого сообщения
 * first_message_json - JSON строка с первым зашифрованным сообщением от отправителя
 * Возвращает session_id
 */
export function init_receiving_session(client_id: string, contact_id: string, remote_bundle_json: string, first_message_json: string): string;

/**
 * Инициализировать сессию с контактом (отправитель)
 * remote_bundle_json - JSON строка с ключами удаленной стороны
 * Возвращает session_id
 */
export function init_session(client_id: string, contact_id: string, remote_bundle_json: string): string;

/**
 * Валидировать username
 */
export function validate_username(username: string): boolean;

/**
 * Валидировать UUID
 */
export function validate_uuid(uuid: string): boolean;

export function version(): string;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
  readonly memory: WebAssembly.Memory;
  readonly __wbg_messengerapi_free: (a: number, b: number) => void;
  readonly create_crypto_client: () => [number, number, number, number];
  readonly get_registration_bundle: (a: number, b: number) => [number, number, number, number];
  readonly init_session: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
  readonly init_receiving_session: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => [number, number, number, number];
  readonly encrypt_message: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
  readonly decrypt_message: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
  readonly destroy_client: (a: number, b: number) => [number, number];
  readonly create_crypto_manager: () => [number, number, number, number];
  readonly crypto_manager_get_registration_bundle: (a: number, b: number) => [number, number, number, number];
  readonly crypto_manager_get_registration_bundle_b64: (a: number, b: number) => [number, number, number, number];
  readonly crypto_manager_rotate_prekey: (a: number, b: number) => [number, number];
  readonly crypto_manager_has_session: (a: number, b: number, c: number, d: number) => [number, number, number];
  readonly destroy_crypto_manager: (a: number, b: number) => [number, number];
  readonly create_contact_manager: () => [number, number];
  readonly contact_manager_add_contact: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
  readonly contact_manager_get_contact: (a: number, b: number, c: number, d: number) => [number, number, number, number];
  readonly contact_manager_get_all_contacts: (a: number, b: number) => [number, number, number, number];
  readonly contact_manager_search_contacts: (a: number, b: number, c: number, d: number) => [number, number, number, number];
  readonly contact_manager_remove_contact: (a: number, b: number, c: number, d: number) => [number, number];
  readonly destroy_contact_manager: (a: number, b: number) => [number, number];
  readonly validate_username: (a: number, b: number) => [number, number, number];
  readonly validate_uuid: (a: number, b: number) => [number, number, number];
  readonly bytes_to_base64: (a: number, b: number) => [number, number];
  readonly base64_to_bytes: (a: number, b: number) => [number, number, number, number];
  readonly generate_random_bytes: (a: number) => [number, number];
  readonly generate_uuid: () => [number, number];
  readonly current_timestamp: () => bigint;
  readonly create_app_state: (a: number, b: number) => any;
  readonly app_state_initialize_user: (a: number, b: number, c: number, d: number, e: number, f: number) => any;
  readonly app_state_finalize_registration: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => any;
  readonly app_state_load_user: (a: number, b: number, c: number, d: number, e: number, f: number) => any;
  readonly app_state_get_user_id: (a: number, b: number) => [number, number, number, number];
  readonly app_state_get_username: (a: number, b: number) => [number, number, number, number];
  readonly app_state_add_contact: (a: number, b: number, c: number, d: number, e: number, f: number) => any;
  readonly app_state_get_contacts: (a: number, b: number) => [number, number, number, number];
  readonly app_state_send_message: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => any;
  readonly app_state_load_conversation: (a: number, b: number, c: number, d: number) => any;
  readonly app_state_connect: (a: number, b: number, c: number, d: number) => any;
  readonly app_state_disconnect: (a: number, b: number) => any;
  readonly app_state_connection_state: (a: number, b: number) => [number, number, number, number];
  readonly app_state_set_auto_reconnect: (a: number, b: number, c: number) => [number, number];
  readonly app_state_reconnect_attempts: (a: number, b: number) => [number, number, number];
  readonly app_state_reset_reconnect: (a: number, b: number) => [number, number];
  readonly app_state_register_on_server: (a: number, b: number, c: number, d: number) => [number, number];
  readonly destroy_app_state: (a: number, b: number) => [number, number];
  readonly init: () => void;
  readonly version: () => [number, number];
  readonly wasm_bindgen__convert__closures_____invoke__h7caf0064f14e42c5: (a: number, b: number) => void;
  readonly wasm_bindgen__closure__destroy__h10a4f8d9a6fdd4a6: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__hac4bc9ef97c25b80: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__h413db9362e3b88cc: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__h8444dd14db23822c: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__ha0fa07e48f81c186: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__h87355ef2cabc0593: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__h16fba39b54b02f16: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__h2f3d247d3c885247: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__h3a6c14d2edce4a2b: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__h5cfbb7e361b25225: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__h6b700a22e080603d: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__hc49830fecaa978ba: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__hf27e220a97f220ba: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__hec57e52b4f03ff19: (a: number, b: number, c: any) => void;
  readonly wasm_bindgen__closure__destroy__h72b98f2ffa834ba8: (a: number, b: number) => void;
  readonly wasm_bindgen__convert__closures_____invoke__hafd713bedfb73285: (a: number, b: number) => number;
  readonly wasm_bindgen__convert__closures_____invoke__h2b5bfc77ea00e3c7: (a: number, b: number, c: any, d: any) => void;
  readonly __wbindgen_malloc: (a: number, b: number) => number;
  readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
  readonly __wbindgen_exn_store: (a: number) => void;
  readonly __externref_table_alloc: () => number;
  readonly __wbindgen_externrefs: WebAssembly.Table;
  readonly __wbindgen_free: (a: number, b: number, c: number) => void;
  readonly __externref_table_dealloc: (a: number) => void;
  readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
* Instantiates the given `module`, which can either be bytes or
* a precompiled `WebAssembly.Module`.
*
* @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
*
* @returns {InitOutput}
*/
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
* If `module_or_path` is {RequestInfo} or {URL}, makes a request and
* for everything else, calls `WebAssembly.instantiate` directly.
*
* @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
*
* @returns {Promise<InitOutput>}
*/
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
