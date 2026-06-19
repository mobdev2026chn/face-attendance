import os

class Settings:
    PROJECT_NAME: str = "FaceAttend AI API"
    PROJECT_VERSION: str = "1.0.0"
    
    # Database Settings
    # Default to SQLite local database for development, can be configured for PostgreSQL
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./faceattend.db")
    
    # Security & Authentication
    JWT_SECRET: str = os.getenv("JWT_SECRET", "faceattend_super_secret_jwt_key_2026_change_in_production")
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440  # 24 hours
    
    # Face Recognition Settings
    # Cosine similarity margin (above this score is considered a match)
    SIMILARITY_THRESHOLD: float = 0.95
    # Cooldown time in seconds to prevent duplicate attendance marks
    DUPLICATE_COOLDOWN_SECONDS: int = 300  # 5 minutes
    
    # AES-256 Symmetric Encryption Key for Face Embeddings (Fernet uses a 32-byte URL-safe base64-encoded key)
    # In production, this should be set as an environment variable
    ENCRYPTION_KEY: str = os.getenv(
        "FACE_ENCRYPTION_KEY", 
        "vKjG9N_hSgV5dGk9P9j2Jb3wX5z7r8t9W2y1V8z4n3s="  # Demo key
    )
    
    # Company Shift Schedule Constants (for Late & Overtime detection)
    SHIFT_START_TIME: str = "09:00"  # HH:MM (9:00 AM)
    SHIFT_END_TIME: str = "18:00"    # HH:MM (6:00 PM)
    LATE_GRACE_PERIOD_MINUTES: int = 15
    HALF_DAY_THRESHOLD_HOURS: float = 4.0
    OVERTIME_THRESHOLD_HOURS: float = 9.0

settings = Settings()
