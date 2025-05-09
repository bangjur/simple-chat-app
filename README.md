# Simple Real-time Chat Application

This is a simple real-time chat application built with Python Flask and WebSockets (Socket.IO).

## Features

- Real-time messaging across multiple browser tabs
- Username registration
- Message history displayed in the chat window
- Notifications when users join or leave
- Different styling for your own messages vs others' messages

## Requirements

- Python 3.7+
- Flask
- Flask-SocketIO
- Eventlet (for production-ready WebSocket support)

## Installation

1. Clone this repository or download the files
2. Create a virtual environment (optional but recommended)
3. Install the dependencies:

```bash
pip install -r requirements.txt
```

## Running the Application

1. Start the server:

```bash
python app.py
```

2. Open your browser and go to `http://localhost:5000`

3. Open multiple tabs with the same URL to test the real-time chat functionality

## How It Works

The application uses WebSockets through Socket.IO to establish persistent, bidirectional connections between the server and each client (browser tab). When a user sends a message, it's transmitted to the server through the WebSocket connection, and then the server broadcasts it to all connected clients.

Socket.IO handles all the complex parts of real-time communication, including:
- Automatic reconnection
- Fallback to long-polling if WebSockets aren't available
- Packet buffering
- Acknowledgments

## Customization

You can customize the application by:
- Changing the styles in the CSS section of index.html
- Adding more features like private messaging, user avatars, or message timestamps
- Implementing persistent storage for chat history