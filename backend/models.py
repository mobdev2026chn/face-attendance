from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Date, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime
from backend.database import Base

class User(Base):
    """
    User account credentials for role-based system dashboard access.
    """
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    role = Column(String, default="Employee")  # Admin, HR, Employee
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    employee_profile = relationship("Employee", back_populates="user", uselist=False)


class Employee(Base):
    """
    Core profile schema containing employee details and registrations.
    """
    __tablename__ = "employees"

    id = Column(String, primary_key=True, index=True)  # Custom Employee ID (e.g. EMP001)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    full_name = Column(String, nullable=False)
    department = Column(String, nullable=False)
    designation = Column(String, nullable=False)
    phone_number = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    profile_photo = Column(Text, nullable=True)  # Base64 string or file path
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="employee_profile")
    embeddings = relationship("FaceEmbedding", back_populates="employee", cascade="all, delete-orphan")
    attendance_records = relationship("Attendance", back_populates="employee", cascade="all, delete-orphan")


class FaceEmbedding(Base):
    """
    Stores encrypted biometric face signatures.
    Each profile captures 20-30 face samples under varied settings.
    """
    __tablename__ = "face_embeddings"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(String, ForeignKey("employees.id"), nullable=False)
    
    # Store the encrypted 512-dimension face embedding array (saved as secure AES bytes/text representation)
    encrypted_embedding = Column(Text, nullable=False)
    
    # Contextual metadata during face enrollments
    lighting_condition = Column(String, nullable=True)  # bright, normal, dim
    pose_angle = Column(String, nullable=True)  # front, left, right, up, down
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    employee = relationship("Employee", back_populates="embeddings")


class Attendance(Base):
    """
    Main attendance ledger capturing exact timestamps, locations, calculations, and AI feedback.
    """
    __tablename__ = "attendance"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(String, ForeignKey("employees.id"), nullable=False)
    date = Column(Date, nullable=False, index=True)
    check_in = Column(DateTime, nullable=True)
    check_out = Column(DateTime, nullable=True)
    
    # Status levels: Present, Late, Absent, Half-Day, Holiday
    status = Column(String, default="Absent", nullable=False)
    
    # Geolocation GPS Verification coordinates
    gps_lat = Column(Float, nullable=True)
    gps_lon = Column(Float, nullable=True)
    
    # Access and Device channels
    check_in_device = Column(String, default="Mobile App")
    check_out_device = Column(String, nullable=True)
    
    # AI validation confidence logs
    confidence_score = Column(Float, nullable=True)
    liveness_score = Column(Float, nullable=True)
    
    # Hours & Overtime Calculations
    total_hours = Column(Float, default=0.0)
    overtime_hours = Column(Float, default=0.0)
    is_synced = Column(Boolean, default=True)  # Supporting offline attendance sync
    
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    employee = relationship("Employee", back_populates="attendance_records")


class AuditLog(Base):
    """
    Immutable system history for system actions and HR overrides.
    """
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    action = Column(String, nullable=False)  # REGISTER_EMPLOYEE, MARK_ATTENDANCE, DELETE_EMPLOYEE, etc.
    performed_by = Column(String, nullable=False)  # User Email / System process
    timestamp = Column(DateTime, default=datetime.utcnow)
    details = Column(Text, nullable=True)
    ip_address = Column(String, nullable=True)
