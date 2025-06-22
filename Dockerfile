# Gunakan image Python yang ringan
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Salin file requirements dan install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Salin semua source code ke dalam container
COPY . .

# Expose port Flask (default 5000)
EXPOSE 5000

# Jalankan aplikasi dengan Gunicorn + eventlet
CMD ["gunicorn", "-k", "eventlet", "-w", "2", "-b", "0.0.0.0:5000", "app:app"]
