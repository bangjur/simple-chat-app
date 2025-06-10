# Langkah-langkah menjalankan SonarQube dengan Docker

# 1. Jalankan database PostgreSQL untuk SonarQube
# Membuat container database dengan user, password, dan database untuk SonarQube
# Ganti $POSTGRES_PASSWORD sesuai kebutuhan
docker run -d --name sonar-db \
  --network sonarnet \
  -e POSTGRES_USER=sonar \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=sonarqube \
  postgres:13

# 2. Jalankan SonarQube server
# Membuat container SonarQube dan menghubungkannya ke database yang sudah dibuat
# Ganti $SONAR_JDBC_PASSWORD sesuai password database
docker run -d --name sonarqube \
  --network sonarnet \
  -p 9000:9000 \
  -e SONAR_JDBC_URL=jdbc:postgresql://sonar-db:5432/sonarqube \
  -e SONAR_JDBC_USERNAME=sonar \
  -e SONAR_JDBC_PASSWORD="$SONAR_JDBC_PASSWORD" \
  sonarqube:community

# 3. Jalankan SonarScanner untuk analisis kode
# Pastikan sudah membuat file sonar-project.properties dan variabel environment sudah di-load
# Ganti $SONAR_HOST_URL dan $SONAR_TOKEN sesuai konfigurasi SonarQube

# Load .env terlebih dahulu jika menggunakan variabel environment
source .env

docker run \
    --rm \
    --network host \
    -e SONAR_HOST_URL="$SONAR_HOST_URL" \
    -e SONAR_TOKEN="$SONAR_TOKEN" \
    -v "./:/usr/src" \
    sonarsource/sonar-scanner-cli