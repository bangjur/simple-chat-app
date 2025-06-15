import os
from flask import Flask, render_template, request
from flask_socketio import SocketIO, emit, join_room, leave_room
from dotenv import load_dotenv
load_dotenv()


app = Flask(__name__)
# Use environment variable for secret key
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-fallback-key-change-in-production')

# Restrict CORS to specific origins in production
allowed_origins = os.environ.get('ALLOWED_ORIGINS', 'http://localhost:5000').split(',')
socketio = SocketIO(app, cors_allowed_origins=allowed_origins)

# Store active users
users = {}

# Security Headers Middleware
@app.after_request
def add_security_headers(response):
    # Content Security Policy - Allow specific sources only
    csp_policy = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "connect-src 'self' ws://localhost:* wss://localhost:* ws://" + request.host + " wss://" + request.host + "; "
        "img-src 'self' data:; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "object-src 'none'"
    )
    response.headers['Content-Security-Policy'] = csp_policy
    
    # Anti-clickjacking protection
    response.headers['X-Frame-Options'] = 'DENY'
    
    # Additional security headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
    
    return response

@app.route('/')
def index():
    return render_template('index.html')

@socketio.on('connect')
def handle_connect():
    print('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    user_id = request.sid
    username = None
    
    try:
        # Find user by session ID
        username = next((name for name, sid in users.items() if sid == user_id), None)
        
        if username:
            del users[username]
            # Notify all clients that a user has left
            emit('user_left', {'username': username}, broadcast=True)
            print(f'User {username} disconnected')
        else:
            print('Unknown client disconnected')
            
    except Exception as e:
        print(f'Error handling disconnect: {e}')

@socketio.on('register_user')
def handle_register(data):
    try:
        username = data.get('username', '').strip()
        user_id = request.sid
        
        # Enhanced username validation
        if not username or len(username) < 2:
            emit('registration_status', {'success': False, 'message': 'Username must be at least 2 characters'})
            return
            
        # Check for potentially malicious characters
        if not username.replace(' ', '').replace('-', '').replace('_', '').isalnum():
            emit('registration_status', {'success': False, 'message': 'Username contains invalid characters'})
            return
        
        # Check if username is already taken
        if username in users:
            emit('registration_status', {'success': False, 'message': 'Username already taken'})
            return
        
        # Store user
        users[username] = user_id
        emit('registration_status', {'success': True, 'message': 'Registration successful'})
        
        # Notify all clients that a user has joined
        emit('user_joined', {'username': username}, broadcast=True)
        print(f'User {username} registered')
        
    except Exception as e:
        print(f'Error registering user: {e}')
        emit('registration_status', {'success': False, 'message': 'Registration failed'})

@socketio.on('send_message')
def handle_message(data):
    try:
        username = data.get('username', '')
        message = data.get('message', '').strip()
        timestamp = data.get('timestamp', '')
        
        # Enhanced message validation
        if not message:
            emit('error', {'message': 'Empty message not allowed'})
            return
            
        # Limit message length
        if len(message) > 500:
            emit('error', {'message': 'Message too long (max 500 characters)'})
            return
            
        # Verify user exists and session matches
        if username not in users or users[username] != request.sid:
            emit('error', {'message': 'Authentication error'})
            return
        
        # Basic XSS prevention - escape HTML characters
        import html
        message = html.escape(message)
        
        # Broadcast message to all clients
        emit('receive_message', {
            'username': username,
            'message': message,
            'timestamp': timestamp
        }, broadcast=True)
        
        print(f'Message from {username}: {message}')
        
    except Exception as e:
        print(f'Error handling message: {e}')
        emit('error', {'message': 'Failed to send message'})

if __name__ == '__main__':
    # Get configuration from environment
    debug_mode = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    host = os.environ.get('FLASK_HOST', '0.0.0.0')
    port = int(os.environ.get('FLASK_PORT', 5000))
    
    socketio.run(app, debug=debug_mode, host=host, port=port, use_reloader=False)