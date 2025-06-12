# SonarQube Setup with Docker

This guide explains how to set up SonarQube using Docker for code analysis in this project.

## Prerequisites

- Docker installed and running
- Network `sonarnet` created in Docker
- Environment variables set in `.env` file

## Environment Variables

Create a `.env` file with the following variables:
```env
POSTGRES_PASSWORD=your_db_password
SONAR_JDBC_PASSWORD=your_db_password
SONAR_HOST_URL=http://localhost:9000
SONAR_TOKEN=your_sonar_token
```

## Setup Steps

### 1. Database Setup

First, create a PostgreSQL database container for SonarQube:

```bash
docker run -d --name sonar-db \
  --network sonarnet \
  -e POSTGRES_USER=sonar \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=sonarqube \
  postgres:13
```

### 2. SonarQube Server

Next, start the SonarQube server connected to the database:

```bash
docker run -d --name sonarqube \
  --network sonarnet \
  -p 9000:9000 \
  -e SONAR_JDBC_URL=jdbc:postgresql://sonar-db:5432/sonarqube \
  -e SONAR_JDBC_USERNAME=sonar \
  -e SONAR_JDBC_PASSWORD="$SONAR_JDBC_PASSWORD" \
  sonarqube:community
```

### 3. Code Analysis

Finally, run the SonarScanner to analyze your code:

```bash
# Load environment variables first
source .env

docker run \
    --rm \
    --network host \
    -e SONAR_HOST_URL="$SONAR_HOST_URL" \
    -e SONAR_TOKEN="$SONAR_TOKEN" \
    -v "./:/usr/src" \
    sonarsource/sonar-scanner-cli
```

## Accessing SonarQube

After setup is complete:
1. Open your browser and navigate to `http://localhost:9000`
2. Login with default credentials (admin/admin)
3. View your project's analysis results in the dashboard

## Notes

- Make sure to change default admin password after first login
- Keep your SONAR_TOKEN secure and never commit it to the repository
- See [sonar-project.properties](./sonar-project.properties) for project-specific configurations