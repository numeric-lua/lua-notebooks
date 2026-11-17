export class Gateway {
  constructor({ onStatus, onMessage, onOpen, onClose }) {
    this.onStatus = onStatus || (() => {});
    this.onMessage = onMessage || (() => {});
    this.onOpen = onOpen || (() => {});
    this.onClose = onClose || (() => {});
    this.socket = null;
    this.url = null;
    this.nextInt = 1;
    this.closedByUser = false;
  }

  connect(url) {
    this.close(true);
    this.url = url;
    this.closedByUser = false;
    this.onStatus("connecting", url);
    let socket;
    try {
      socket = new WebSocket(url);
    } catch (error) {
      this.onStatus("error", String(error));
      this.onClose("error");
      return;
    }
    this.socket = socket;
    socket.addEventListener("open", () => {
      if (this.socket !== socket) return;
      this.onOpen();
    });
    socket.addEventListener("message", (event) => {
      if (this.socket !== socket) return;
      let message;
      try {
        message = JSON.parse(String(event.data));
      } catch {
        this.onMessage({ type: "error", message: "invalid JSON from gateway" });
        return;
      }
      this.onMessage(message);
    });
    socket.addEventListener("close", () => {
      if (this.socket !== socket) return;
      const intentional = this.closedByUser;
      this.socket = null;
      this.onStatus(intentional ? "offline" : "closed", this.url);
      this.onClose(intentional ? "closed" : "lost");
    });
    socket.addEventListener("error", () => {
      if (this.socket === socket) this.onStatus("error", "WebSocket error");
    });
  }

  close(intentional = true) {
    this.closedByUser = intentional;
    if (this.socket) {
      const socket = this.socket;
      this.socket = null;
      try { socket.close(); } catch { /* ignore */ }
    }
  }

  get isOpen() {
    return this.socket?.readyState === WebSocket.OPEN;
  }

  send(message) {
    if (!this.isOpen) return false;
    try {
      this.socket.send(JSON.stringify(message));
      return true;
    } catch {
      return false;
    }
  }

  nextRequestId() {
    const id = this.nextInt;
    this.nextInt += 1;
    return id;
  }
}
