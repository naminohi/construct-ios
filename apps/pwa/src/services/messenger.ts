import init, * as wasm from 'construct-core';

// Define the types locally as they are not exported from WASM
export type Contact = {
    id: string;
    username: string;
    // Add other fields as necessary
};

export type Conversation = {
    contact_id: string;
    messages: StoredMessage[];
    // Add other fields as necessary
};

export type StoredMessage = {
    id: string;
    sender_id: string;
    receiver_id: string;
    timestamp: number;
    // etc.
};


class MessengerService {
  private stateId: string | null = null;
  private isInitialized = false;

  async initialize(): Promise<void> {
    if (this.isInitialized) {
      console.log('Messenger already initialized.');
      return;
    }
    try {
      // 1. Initialize the WASM module
      await init();
      
      // 2. Create a new application state instance
      // "construct-db" is an arbitrary name for the IndexedDB database
      this.stateId = await wasm.create_app_state("construct-db");

      this.isInitialized = true;
      console.log('Messenger initialized successfully with state ID:', this.stateId);
    } catch (error) {
      console.error('Failed to initialize WASM module:', error);
      throw new Error('Failed to initialize messenger core.');
    }
  }

  /**
   * Asserts that the messenger is initialized and returns the state ID.
   */
  private getStateId(): string {
    if (!this.stateId) {
      throw new Error('Messenger is not initialized. Call initialize() first.');
    }
    return this.stateId;
  }

  async registerUser(username: string, password: string): Promise<string> {
    const stateId = this.getStateId();
    await wasm.app_state_initialize_user(stateId, username, password);
    const userId = wasm.app_state_get_user_id(stateId);
    if (!userId) {
        throw new Error("Could not get user ID after initialization.");
    }
    // In a real app, you'd now make a server call to finalize registration
    // await wasm.app_state_register_on_server(stateId, password);
    return userId;
  }

  async loginUser(userId: string, password: string): Promise<void> {
    const stateId = this.getStateId();
    await wasm.app_state_load_user(stateId, userId, password);
  }

  getCurrentUser(): { userId?: string; username?: string } {
    const stateId = this.getStateId();
    const userId = wasm.app_state_get_user_id(stateId);
    const username = wasm.app_state_get_username(stateId);
    return { userId, username };
  }

  async addContact(contactId: string, username: string): Promise<void> {
    const stateId = this.getStateId();
    await wasm.app_state_add_contact(stateId, contactId, username);
  }

  getContacts(): Contact[] {
    const stateId = this.getStateId();
    // serde-wasm-bindgen automatically converts the JsValue to a JS object/array
    return wasm.app_state_get_contacts(stateId) as Contact[];
  }

  async sendMessage(toContactId: string, sessionId: string, text: string): Promise<string> {
    const stateId = this.getStateId();
    return wasm.app_state_send_message(stateId, toContactId, sessionId, text);
  }

  async loadConversation(contactId: string): Promise<Conversation> {
    const stateId = this.getStateId();
    // serde-wasm-bindgen automatically converts the JsValue to a JS object/array
    return await wasm.app_state_load_conversation(stateId, contactId) as Conversation;
  }

  async connect(serverUrl: string): Promise<void> {
    const stateId = this.getStateId();
    wasm.app_state_connect(stateId, serverUrl);
  }

  async disconnect(): Promise<void> {
    const stateId = this.getStateId();
    wasm.app_state_disconnect(stateId);
  }

  destroy(): void {
    if (this.stateId) {
      wasm.destroy_app_state(this.stateId);
      this.stateId = null;
    }
    this.isInitialized = false;
    console.log('Messenger destroyed.');
  }
}

// Export a singleton instance of the service
export const messenger = new MessengerService();