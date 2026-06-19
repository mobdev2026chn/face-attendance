# FaceAttend AI - Enterprise Deployment & Operations Guide

Welcome to the FaceAttend AI deployment guide. This document provides step-by-step instructions for running the application locally, deploying it to production cloud servers (AWS), and detailed references for the backend REST APIs.

---

## 1. System Architecture Overview

```
                                  +-----------------------+
                                  |   React Vite Client   |
                                  |      (Port 3000)      |
                                  +-----------+-----------+
                                              |
                                              | HTTPS REST (JWT)
                                              v
+------------------------+        +-----------+-----------+
|    PostgreSQL Database | <----> |   FastAPI REST Engine |
|      (Port 5432)       |        |      (Port 8000)      |
+------------------------+        +-----------+-----------+
                                              |
                                              | Decrypted Vectors
                                              v
                                  +-----------+-----------+
                                  |   AI OpenCV Liveness  |
                                  |        Pipeline       |
                                  +-----------------------+
```

FaceAttend AI divides responsibilities into three logical tiers:
1. **Frontend Tier (React + Vite)**: Renders the Admin/HR dashboards and coordinates real-time liveness sequences inside the mobile app simulator.
2. **Application Tier (FastAPI)**: Drives the REST endpoints, decrypts matching templates in-memory using symmetric AES-256 keys, and monitors cooldowns.
3. **Database Tier (PostgreSQL)**: Holds the encrypted float embeddings, audit logs, employee directories, and daily schedules.

---

## 2. Local Setup Guide

### Prerequisites
- Python 3.10 or higher
- Node.js 18.0 or higher
- SQLite (default) or PostgreSQL

### Step 2.1: Spin up Backend Server
1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Create a virtual environment and activate it:
   ```bash
   python -m venv venv
   # On Windows
   .\venv\Scripts\activate
   # On macOS/Linux
   source venv/bin/activate
   ```
3. Install standard requirements:
   ```bash
   pip install -r ../ai_module/requirements.txt
   ```
4. Run the development server using Uvicorn:
   ```bash
   uvicorn main:app --reload --port 8000
   ```
5. Verification: Open [http://localhost:8000/health](http://localhost:8000/health) in your browser. You should receive a `{"status": "healthy"}` heartbeat.

### Step 2.2: Launch Frontend Client
1. Navigate to the frontend directory:
   ```bash
   cd ../frontend
   ```
2. Install npm dependencies:
   ```bash
   npm install
   ```
3. Start the Vite dev server:
   ```bash
   npm run dev
   ```
4. Verification: Open the printed URL (usually [http://localhost:5173](http://localhost:5173)) to view the synchronized FaceAttend AI workspace.

---

## 3. Production Deployment Guide (AWS Cloud)

To deploy the production-ready application to Amazon Web Services (AWS), we utilize **Amazon ECS (Elastic Container Service)** with Fargate for serverless orchestrations and **Amazon RDS (Relational Database Service)** for PostgreSQL storage.

### Step 3.1: Database Provisioning
1. Launch an **RDS PostgreSQL** database instance inside your company VPC.
2. Enable encryption-at-rest using AWS KMS keys.
3. Configure security groups to allow inbound traffic only from the application ECS security group on port `5432`.

### Step 3.2: Secret Key Configurations
Secure the environment variables inside **AWS Secrets Manager**:
- `DATABASE_URL`: `postgresql://[user]:[password]@[rds_host]:5432/faceattend_db`
- `JWT_SECRET`: Generate a highly-secure random string (`openssl rand -hex 32`)
- `FACE_ENCRYPTION_KEY`: A 32-byte URL-safe base64 encryption key for `cryptography.fernet`.

### Step 3.3: ECR Push and ECS Deployment
1. Build and push backend and frontend Docker containers to **Amazon ECR (Elastic Container Registry)**.
2. Define a **Task Definition** mapping the containers and matching IAM execution roles to pull Secrets Manager variables.
3. Deploy the ECS Service behind an **Application Load Balancer (ALB)**.
4. Configure ALB listener rules to enforce **HTTPS (SSL/TLS)**. 

> [!IMPORTANT]
> **Biometric Camera Permissions Notice**: Modern mobile operating systems and browsers require a secure origin (`https://` or `localhost`) to access hardware camera resources (`getUserMedia`). Ensure SSL certificates are fully configured on the production load balancer.

---

## 4. API Reference Sheets

All request and response objects use strict JSON formats. Below are key schemas:

### 4.1: User Credentials Authentication
- **Endpoint**: `POST /api/auth/login`
- **Headers**: `Content-Type: application/x-www-form-urlencoded`
- **Body Parameters**:
  - `username`: Email address (e.g. `admin@faceattend.ai`)
  - `password`: Password
- **Response (200 OK)**:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "role": "Admin",
    "email": "admin@faceattend.ai"
  }
  ```

### 4.2: Biometric Attendance Scanning
- **Endpoint**: `POST /api/attendance/scan`
- **Headers**: `Content-Type: application/json`
- **Request Body**:
  ```json
  {
    "gps_lat": 37.7749,
    "gps_lon": -122.4194,
    "device_name": "iPhone 15 Pro",
    "live_embedding": [0.0125, -0.0034, ..., 0.0874],
    "liveness_score": 0.985,
    "is_liveness_verified": true
  }
  ```
- **Response (200 OK - Check-In)**:
  ```json
  {
    "success": true,
    "employee_id": "EMP001",
    "employee_name": "Alice Johnson",
    "department": "Engineering",
    "action": "Check-In",
    "timestamp": "2026-06-01 09:12:45 AM",
    "status": "Present",
    "confidence": 98.2,
    "total_hours": 0.0,
    "overtime": 0.0
  }
  ```

### 4.3: Register Employee
- **Endpoint**: `POST /api/employees/`
- **Headers**: `Authorization: Bearer [JWT_TOKEN]`
- **Request Body**:
  ```json
  {
    "id": "EMP006",
    "full_name": "Elena Smith",
    "department": "Engineering",
    "designation": "Frontend Specialist",
    "phone_number": "+1-555-0104",
    "email": "elena@faceattend.ai",
    "face_samples": [
      [0.01, -0.05, ..., 0.02],
      [0.011, -0.048, ..., 0.022]
    ]
  }
  ```

---

## 5. Security & Regulatory Compliance

FaceAttend AI implements best practices to conform to biometric privacy laws (GDPR, CCPA, BIPA):
1. **Raw Image Deletion**: We do not store raw pixel images in databases or disk storage. Captured frames are immediately mapped to vector embeddings in volatile memory and discarded.
2. **Encrypted Embeddings**: Embedding arrays (512-dimension numbers) are encrypted using AES-256 (via cryptography libraries) before database write. If database backups are breached, biometrics remain unreadable.
3. **Audit Ledger Logs**: Every security action (like deactivating templates, editing grace schedules, overriding attendance times) generates an immutable, timestamped record in the `audit_logs` table containing user IPs.
