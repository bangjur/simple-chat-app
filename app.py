import os
import time
import html
import re
from collections import defaultdict
from flask import Flask, render_template, request
from flask_socketio import SocketIO, emit
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = Flask(__name__)

# Security configurations
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', os.urandom(24))

# FRONTEND AND BACKEND ARE DEPLOYED ON DIFFERENT ORIGINS
# CORS configuration - restrict to specific origins
# ALLOWED_ORIGINS = os.environ.get('ALLOWED_ORIGINS', 'http://localhost:3000').split(',')
# ALLOWED_ORIGINS = [origin.strip() for origin in ALLOWED_ORIGINS if origin.strip()]
# socketio = SocketIO(app, cors_allowed_origins=ALLOWED_ORIGINS)

# FRONTEND AND BACKEND ARE DEPLOYED ON THE SAME ORIGIN
socketio = SocketIO(app)  # Same origin, gak perlu CORS

# Configuration constants
MAX_MESSAGE_LENGTH = int(os.environ.get('MAX_MESSAGE_LENGTH', 1000))
RATE_LIMIT_MESSAGES = int(os.environ.get('RATE_LIMIT_MESSAGES', 100))
RATE_LIMIT_WINDOW = int(os.environ.get('RATE_LIMIT_WINDOW', 60))
SESSION_TIMEOUT = int(os.environ.get('SESSION_TIMEOUT', 3600))
MAX_USERS = int(os.environ.get('MAX_USERS', 100))

# Store active users and sessions
users = {}  # username -> sid
user_sessions = {}  # username -> {sid, last_activity, join_time}
user_message_times = defaultdict(list)  # username -> [timestamps]

def cleanup_inactive_sessions():
    """Remove inactive user sessions"""
    now = time.time()
    inactive_users = []
    
    for username, session in user_sessions.items():
        if now - session['last_activity'] > SESSION_TIMEOUT:
            inactive_users.append(username)
    
    for username in inactive_users:
        if username in user_sessions:
            del user_sessions[username]
        if username in users:
            del users[username]
        if username in user_message_times:
            del user_message_times[username]
        
        # Notify all clients that user left due to timeout
        emit('user_left', {
            'username': username, 
            'reason': 'timeout'
        }, broadcast=True)
        
        print(f'User {username} removed due to inactivity')

def validate_username(username):
    """Validate username format and availability"""
    if not username or not isinstance(username, str):
        return False, "Username is required"
    
    username = username.strip()
    
    if len(username) < 3 or len(username) > 20:
        return False, "Username must be 3-20 characters long"
    
    if not re.match(r'^[a-zA-Z0-9_-]+$', username):
        return False, "Username can only contain letters, numbers, underscore, and dash"
    
    if username.lower() in ['admin', 'moderator', 'system', 'bot']:
        return False, "Username is reserved"
    
    return True, "Valid username"

def check_rate_limit(username):
    """Check if user is rate limited"""
    now = time.time()
    
    # Clean old timestamps
    user_message_times[username] = [
        timestamp for timestamp in user_message_times[username]
        if now - timestamp < RATE_LIMIT_WINDOW
    ]
    
    # Check rate limit
    if len(user_message_times[username]) >= RATE_LIMIT_MESSAGES:
        return False
    
    return True

def sanitize_message(message):
    """Sanitize user message"""
    if not message or not isinstance(message, str):
        return ""
    
    # Escape HTML
    message = html.escape(message.strip())
    
    # Remove excessive whitespace
    message = re.sub(r'\s+', ' ', message)
    
    return message

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/health')
def health_check():
    """Health check endpoint for AWS App Runner"""
    return {'status': 'healthy', 'users_online': len(users)}, 200

@socketio.on('connect')
def handle_connect():
    print(f'Client connected: {request.sid}')
    cleanup_inactive_sessions()

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    user_id = request.sid
    username = None
    
    # Find username by session ID
    for name, sid in users.items():
        if sid == user_id:
            username = name
            break
    
    if username:
        # Remove user from all tracking
        if username in users:
            del users[username]
        if username in user_sessions:
            del user_sessions[username]
        if username in user_message_times:
            del user_message_times[username]
        
        # Notify all clients
        emit('user_left', {
            'username': username,
            'reason': 'disconnect'
        }, broadcast=True)
        
        print(f'User {username} disconnected')
    else:
        print(f'Unknown client disconnected: {user_id}')

@socketio.on('register_user')
def handle_register(data):
    """Handle user registration"""
    try:
        username = data.get('username', '').strip()
        user_id = request.sid
        
        # Validate username
        is_valid, message = validate_username(username)
        if not is_valid:
            emit('registration_status', {
                'success': False, 
                'message': message
            })
            return
        
        # Check if too many users
        if len(users) >= MAX_USERS:
            emit('registration_status', {
                'success': False, 
                'message': 'Server is full, please try again later'
            })
            return
        
        # Check if username is already taken
        if username in users:
            emit('registration_status', {
                'success': False, 
                'message': 'Username is already taken'
            })
            return
        
        # Register user
        users[username] = user_id
        user_sessions[username] = {
            'sid': user_id,
            'last_activity': time.time(),
            'join_time': time.time()
        }
        
        emit('registration_status', {
            'success': True, 
            'message': 'Registration successful'
        })
        
        # Notify all clients
        emit('user_joined', {
            'username': username,
            'users_online': len(users)
        }, broadcast=True)
        
        print(f'User {username} registered successfully')
        
    except Exception as e:
        print(f'Registration error: {str(e)}')
        emit('registration_status', {
            'success': False, 
            'message': 'Registration failed, please try again'
        })

@socketio.on('send_message')
def handle_message(data):
    """Handle incoming messages"""
    try:
        username = data.get('username', '').strip()
        message = data.get('message', '')
        timestamp = data.get('timestamp')
        
        # Verify user authentication
        if username not in users or users[username] != request.sid:
            emit('error', {'message': 'Authentication error'})
            return
        
        # Update last activity
        if username in user_sessions:
            user_sessions[username]['last_activity'] = time.time()
        
        # Validate message
        if not message or not isinstance(message, str):
            emit('error', {'message': 'Message cannot be empty'})
            return
        
        if len(message) > MAX_MESSAGE_LENGTH:
            emit('error', {
                'message': f'Message too long (max {MAX_MESSAGE_LENGTH} characters)'
            })
            return
        
        # Check rate limiting
        if not check_rate_limit(username):
            emit('error', {
                'message': f'Too many messages. Limit: {RATE_LIMIT_MESSAGES} messages per {RATE_LIMIT_WINDOW} seconds'
            })
            return
        
        # Sanitize message
        clean_message = sanitize_message(message)
        if not clean_message:
            emit('error', {'message': 'Invalid message content'})
            return
        
        # Record message timestamp for rate limiting
        user_message_times[username].append(time.time())
        
        # Broadcast message to all clients
        emit('receive_message', {
            'username': username,
            'message': clean_message,
            'timestamp': timestamp or int(time.time() * 1000)
        }, broadcast=True)
        
        print(f'Message from {username}: {clean_message[:50]}...')
        
    except Exception as e:
        print(f'Message handling error: {str(e)}')
        emit('error', {'message': 'Failed to send message'})

@socketio.on('get_users')
def handle_get_users():
    """Send list of online users"""
    try:
        username = None
        
        # Find requesting user
        for name, sid in users.items():
            if sid == request.sid:
                username = name
                break
        
        if not username:
            emit('error', {'message': 'Authentication required'})
            return
        
        # Update last activity
        if username in user_sessions:
            user_sessions[username]['last_activity'] = time.time()
        
        # Send users list
        emit('users_list', {
            'users': list(users.keys()),
            'count': len(users)
        })
        
    except Exception as e:
        print(f'Get users error: {str(e)}')
        emit('error', {'message': 'Failed to get users list'})

@socketio.on('ping')
def handle_ping():
    """Handle ping for keepalive"""
    username = None
    
    # Find requesting user
    for name, sid in users.items():
        if sid == request.sid:
            username = name
            break
    
    if username and username in user_sessions:
        user_sessions[username]['last_activity'] = time.time()
    
    emit('pong')

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return {'error': 'Not found'}, 404

@app.errorhandler(500)
def internal_error(error):
    return {'error': 'Internal server error'}, 500

# Periodic cleanup (you might want to use a proper task scheduler in production)
def periodic_cleanup():
    """Run periodic cleanup of inactive sessions"""
    cleanup_inactive_sessions()

if __name__ == '__main__':
    # Production settings
    debug_mode = os.environ.get('DEBUG', 'False').lower() == 'true'
    host = os.environ.get('HOST', '0.0.0.0')
    port = int(os.environ.get('PORT', 5000))
    
    print(f"Starting server on {host}:{port}")
    print(f"Debug mode: {debug_mode}")
    # print(f"Allowed origins: {ALLOWED_ORIGINS}")
    print(f"Max users: {MAX_USERS}")
    print(f"Rate limit: {RATE_LIMIT_MESSAGES} messages per {RATE_LIMIT_WINDOW} seconds")
    
    socketio.run(
        app, 
        debug=debug_mode, 
        host=host, 
        port=port, 
        use_reloader=False
    )