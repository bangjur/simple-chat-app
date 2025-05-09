from flask import Flask, render_template, request
from flask_socketio import SocketIO, emit, join_room, leave_room

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your-secret-key'
socketio = SocketIO(app, cors_allowed_origins="*")

# Store active users
users = {}

@app.route('/')
def index():
    return render_template('index.html')

@socketio.on('connect')
def handle_connect():
    print('Client connected')

@socketio.on('disconnect')
def handle_disconnect():
    # Find and remove disconnected user
    user_id = request.sid
    username = None
    
    for name, sid in users.items():
        if sid == user_id:
            username = name
            break
    
    if username:
        del users[username]
        # Notify all clients that a user has left
        emit('user_left', {'username': username}, broadcast=True)
        print(f'User {username} disconnected')
    else:
        print('Unknown client disconnected')

@socketio.on('register_user')
def handle_register(data):
    username = data['username']
    user_id = request.sid
    
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

@socketio.on('send_message')
def handle_message(data):
    username = data['username']
    message = data['message']
    timestamp = data['timestamp']
    
    # Verify user exists
    if username not in users or users[username] != request.sid:
        emit('error', {'message': 'Authentication error'})
        return
    
    # Broadcast message to all clients
    emit('receive_message', {
        'username': username,
        'message': message,
        'timestamp': timestamp
    }, broadcast=True)
    
    print(f'Message from {username}: {message}')

if __name__ == '__main__':
    # Use this if you're using eventlet

    socketio.run(app, debug=True, host='0.0.0.0', port=5000)