from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from datetime import datetime, date

# --- AUTH SCHEMAS ---
class UserBase(BaseModel):
    email: EmailStr
    role: str = "Employee"

class UserCreate(UserBase):
    password: str

class UserResponse(UserBase):
    id: int
    is_active: bool
    created_at: datetime

    class Config:
        orm_mode = True

class Token(BaseModel):
    access_token: str
    token_type: str
    role: str
    email: str

class TokenData(BaseModel):
    email: Optional[str] = None
    role: Optional[str] = None


# --- EMBEDDING SCHEMAS ---
class FaceEmbeddingBase(BaseModel):
    lighting_condition: Optional[str] = "normal"
    pose_angle: Optional[str] = "front"

class FaceEmbeddingCreate(FaceEmbeddingBase):
    embedding: List[float]  # 512 dimensions array

class FaceEmbeddingResponse(FaceEmbeddingBase):
    id: int
    employee_id: str
    created_at: datetime

    class Config:
        orm_mode = True


# --- EMPLOYEE SCHEMAS ---
class EmployeeBase(BaseModel):
    full_name: str
    department: str
    designation: str
    phone_number: str
    email: EmailStr

class EmployeeCreate(EmployeeBase):
    id: str  # Custom Employee ID (e.g. EMP001)
    profile_photo: Optional[str] = None  # Base64 string of profile photo
    face_samples: Optional[List[List[float]]] = None  # Capturing 20-30 sample vectors

class EmployeeUpdate(BaseModel):
    full_name: Optional[str] = None
    department: Optional[str] = None
    designation: Optional[str] = None
    phone_number: Optional[str] = None
    email: Optional[EmailStr] = None
    profile_photo: Optional[str] = None

class EmployeeResponse(EmployeeBase):
    id: str
    profile_photo: Optional[str] = None
    is_active: bool
    created_at: datetime
    embeddings: List[FaceEmbeddingResponse] = []

    class Config:
        orm_mode = True


# --- ATTENDANCE SCHEMAS ---
class AttendanceBase(BaseModel):
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    check_in_device: Optional[str] = "Mobile App"

class AttendanceCreate(AttendanceBase):
    employee_id: str
    date: date
    check_in: Optional[datetime] = None

class AttendanceUpdate(BaseModel):
    check_out: Optional[datetime] = None
    status: Optional[str] = None
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    total_hours: Optional[float] = None
    overtime_hours: Optional[float] = None

class AttendanceResponse(BaseModel):
    id: int
    employee_id: str
    date: date
    check_in: Optional[datetime] = None
    check_out: Optional[datetime] = None
    status: str
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    check_in_device: Optional[str] = None
    check_out_device: Optional[str] = None
    confidence_score: Optional[float] = None
    liveness_score: Optional[float] = None
    total_hours: float
    overtime_hours: float
    is_synced: bool
    created_at: datetime

    class Config:
        orm_mode = True

# Request model when checking in/out through the camera view
class AttendanceMarkRequest(BaseModel):
    gps_lat: Optional[float] = Field(None, description="GPS Latitude")
    gps_lon: Optional[float] = Field(None, description="GPS Longitude")
    device_name: Optional[str] = "Mobile App"
    
    # Target face embedding extracted in real time from the video feed
    live_embedding: List[float] = Field(..., description="512-dimension live face vector")
    
    # Verification details
    liveness_score: float = Field(..., description="Anti-spoofing rating")
    is_liveness_verified: bool = Field(..., description="Flags whether user passed liveness challenge")


# --- REPORT SCHEMAS ---
class DepartmentReport(BaseModel):
    department: str
    total_employees: int
    present_today: int
    absent_today: int
    late_today: int
    attendance_rate: float

class DailySummaryReport(BaseModel):
    date: date
    total_employees: int
    present: int
    absent: int
    late: int
    half_day: int
    attendance_percentage: float


# --- AUDIT LOGS ---
class AuditLogResponse(BaseModel):
    id: int
    action: str
    performed_by: str
    timestamp: datetime
    details: Optional[str] = None
    ip_address: Optional[str] = None

    class Config:
        orm_mode = True
