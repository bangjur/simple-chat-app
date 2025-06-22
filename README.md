# Simple Real-time Chat Application

This is a simple real-time chat application built with Python Flask and WebSockets (Socket.IO).

## Features

- Real-time messaging across multiple browser tabs
- Username registration
- Message history displayed in the chat window
- Notifications when users join or leave
- Different styling for your own messages vs others' messages

## Security Improvements

The application implements several security best practices:

- **Environment-based Secret Key**: The Flask `SECRET_KEY` is loaded from environment variables, not hardcoded.
- **CORS Restriction**: (Optional) You can restrict allowed origins for Socket.IO using the `ALLOWED_ORIGINS` environment variable.
- **Security Headers**: HTTP security headers are set for every response, including:
  - `Content-Security-Policy`
  - `X-Frame-Options`
  - `X-Content-Type-Options`
  - `Referrer-Policy`
- **Username Validation**: Usernames are validated for length, allowed characters, and reserved words.
- **Message Validation & Sanitization**: Messages are validated for length and sanitized (HTML-escaped) to prevent XSS.
- **Rate Limiting**: Each user is limited to a configurable number of messages per time window to prevent spam/DoS.
- **Session Timeout**: Inactive users are automatically removed after a configurable timeout.
- **User Limit**: The number of concurrent users is limited to prevent resource exhaustion.
- **Error Handling**: Custom error handlers for 404 and 500 responses.
- **Health Check Endpoint**: `/health` endpoint for AWS App Runner monitoring.

**Note:**
- There is currently **no session management or database**. All user and message data is stored in memory only.
- **When the app restarts, all users must reconnect and all chat history is lost.**
- **No chat history is available** after a restart or refresh.

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

You can run the application in development or production mode:

**Development:**
```bash
python3 app.py
```

**Production (recommended):**
```bash
gunicorn -k eventlet -w 1 --threads 100 -b 0.0.0.0:5000 app:app
```

- `-k eventlet`: Use eventlet worker for WebSocket support
- `-w 1`: Number of worker processes (increase as needed)
- `--threads 100`: Number of threads per worker (tune as needed)
- `-b 0.0.0.0:5000`: Bind to all interfaces on port 5000
- `app:app`: Module and Flask app object

> **Info:**
> Konfigurasi production ini telah dicoba di AWS App Runner dan berhasil berjalan dengan baik.

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
- Implementing persistent storage for chat history (currently not persistent)

## Testing and CI/CD

This project includes basic automated UI testing using **Selenium** to simulate real user interactions like logging in and sending messages.

Tests cover:
- App accessibility
- Login flow
- Chat interface load
- Sending and verifying messages

### CI/CD with GitHub Actions

The test workflow is fully automated using GitHub Actions.  
Each push runs the following steps:

1. Set up Python and Chrome
2. Install dependencies
3. Launch the Flask server
4. Run Selenium tests
5. Output results and handle cleanup

You can find the GitHub Actions workflow under `.github/workflows/selenium-test.yml`

✅ [View it on GitHub](https://github.com/bangjur/simple-chat-app)
