from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from datetime import datetime, date, timedelta
import random
from backend.config import settings
from backend.database import engine, Base, SessionLocal
from backend.models import User, Employee, FaceEmbedding, Attendance, AuditLog
from backend.auth import get_password_hash
from backend.encryption import biometric_encryptor
from backend.routes import auth, employees, attendance, dashboard, reports

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.PROJECT_VERSION,
    description="Backend facial recognition endpoints and tracking ledger."
)

# CORS Policy configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For local workspace and cross-port communications
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Bind endpoints
app.include_router(auth.router, prefix="/api")
app.include_router(employees.router, prefix="/api")
app.include_router(attendance.router, prefix="/api")
app.include_router(dashboard.router, prefix="/api")
app.include_router(reports.router, prefix="/api")

@app.get("/health")
def health_check():
    """Diagnostic system health heartbeat."""
    return {"status": "healthy", "service": settings.PROJECT_NAME, "version": settings.PROJECT_VERSION}

def generate_mock_vector() -> list[float]:
    """Generates a pseudo-random normalized 512-dimension vector representing a face."""
    vector = [random.uniform(-0.1, 0.1) for _ in range(512)]
    # Normalize vector to unit length
    magnitude = sum(x*x for x in vector)**0.5
    return [x/magnitude for x in vector]

def populate_mock_data(db: Session):
    """
    Seeds the database with premium mock information to populate tables 
    and enable the charts and simulators to function immediately on startup.
    """
    # 1. Check if admin exists
    admin_user = db.query(User).filter(User.role == "Admin").first()
    if admin_user:
        return  # Already seeded
        
    print("Seeding database with FaceAttend AI demo data...")
    
    # 2. Add System Administrator
    admin_pwd = get_password_hash("admin123")
    admin = User(
        email="admin@faceattend.ai",
        hashed_password=admin_pwd,
        role="Admin",
        is_active=True
    )
    db.add(admin)
    db.commit()

    # 3. Add HR Administrator
    hr_pwd = get_password_hash("hr123")
    hr_user = User(
        email="hr@faceattend.ai",
        hashed_password=hr_pwd,
        role="HR",
        is_active=True
    )
    db.add(hr_user)
    db.commit()

    # 4. Add Mock Employees
    mock_staff = [
        {"id": "EMP001", "name": "Alice Johnson", "dept": "Engineering", "desig": "Senior Frontend Engineer", "phone": "+1-555-0199", "email": "alice@faceattend.ai"},
        {"id": "EMP002", "name": "Robert Chen", "dept": "Engineering", "desig": "AI Infrastructure Lead", "phone": "+1-555-0142", "email": "robert@faceattend.ai"},
        {"id": "EMP003", "name": "Sarah Miller", "dept": "HR & Admin", "desig": "Talent Acquisition Manager", "phone": "+1-555-0185", "email": "sarah@faceattend.ai"},
        {"id": "EMP004", "name": "David Kalu", "dept": "Product & Design", "desig": "Lead UI/UX Designer", "phone": "+1-555-0121", "email": "david@faceattend.ai"},
        {"id": "EMP005", "name": "Elena Rostova", "dept": "Operations", "desig": "Operations Director", "phone": "+1-555-0167", "email": "elena@faceattend.ai"},
    ]

    for staff in mock_staff:
        # Create Employee User accounts
        emp_pwd = get_password_hash(f"FaceAttend@{staff['id']}")
        user_acct = User(
            email=staff["email"],
            hashed_password=emp_pwd,
            role="Employee",
            is_active=True
        )
        db.add(user_acct)
        db.commit()
        db.refresh(user_acct)

        # Create Employee profile
        employee = Employee(
            id=staff["id"],
            user_id=user_acct.id,
            full_name=staff["name"],
            department=staff["dept"],
            designation=staff["desig"],
            phone_number=staff["phone"],
            email=staff["email"],
            is_active=True
        )
        db.add(employee)
        db.commit()
        db.refresh(employee)

        # Generate and secure 5 mock face templates for matching simulation
        base_vector = generate_mock_vector()
        for idx in range(5):
            # introduce small pertubations representing glasses, beard, or light changes
            perturbed = [x + random.uniform(-0.01, 0.01) for x in base_vector]
            mag = sum(y*y for y in perturbed)**0.5
            norm_vector = [y/mag for y in perturbed]
            
            encrypted_str = biometric_encryptor.encrypt_embedding(norm_vector)
            
            face = FaceEmbedding(
                employee_id=employee.id,
                encrypted_embedding=encrypted_str,
                lighting_condition="bright" if idx == 1 else ("dim" if idx == 2 else "normal"),
                pose_angle="front" if idx in [0, 3, 4] else ("slight_left" if idx == 1 else "slight_right")
            )
            db.add(face)
        db.commit()

        # Seed historical attendance records for the past 7 days
        today = datetime.utcnow().date()
        for offset in range(6, -1, -1):
            record_date = today - timedelta(days=offset)
            
            # Skip weekends for realistic simulation
            if record_date.weekday() >= 5:
                continue
                
            # Randomize daily check-in (some on time, some late, some absent)
            attendance_roll = random.random()
            if attendance_roll > 0.08:  # 92% present rate
                # Determine hour
                if attendance_roll < 0.25:  # Late arrival (around 9:20 - 9:45)
                    check_in_hour = 9
                    check_in_min = random.randint(16, 45)
                    status = "Late"
                elif attendance_roll < 0.30:  # Half-Day arrival (or checked out early)
                    check_in_hour = 10
                    check_in_min = random.randint(0, 30)
                    status = "Half-Day"
                else:  # On time (8:45 - 8:59)
                    check_in_hour = 8
                    check_in_min = random.randint(40, 59)
                    status = "Present"

                # Check-out time (between 5:30 PM and 7:30 PM)
                check_out_hour = random.randint(17, 19)
                check_out_min = random.randint(0, 59)
                
                check_in_dt = datetime.combine(record_date, datetime.min.time()).replace(
                    hour=check_in_hour, minute=check_in_min
                )
                check_out_dt = datetime.combine(record_date, datetime.min.time()).replace(
                    hour=check_out_hour, minute=check_out_min
                )

                # working duration aggregates
                duration_sec = (check_out_dt - check_in_dt).total_seconds()
                total_hours = round(duration_sec / 3600.0, 2)
                
                # Check for Overtime
                overtime_hours = 0.0
                if total_hours > settings.OVERTIME_THRESHOLD_HOURS:
                    overtime_hours = round(total_hours - settings.OVERTIME_THRESHOLD_HOURS, 2)

                # Override for Half-Day
                if total_hours < settings.HALF_DAY_THRESHOLD_HOURS:
                    status = "Half-Day"

                att = Attendance(
                    employee_id=employee.id,
                    date=record_date,
                    check_in=check_in_dt,
                    check_out=check_out_dt,
                    status=status,
                    gps_lat=37.7749 + random.uniform(-0.001, 0.001),
                    gps_lon=-122.4194 + random.uniform(-0.001, 0.001),
                    check_in_device="Mobile App",
                    check_out_device="Mobile App",
                    confidence_score=random.uniform(0.96, 0.99),
                    liveness_score=random.uniform(0.95, 0.99),
                    total_hours=total_hours,
                    overtime_hours=overtime_hours,
                    is_synced=True
                )
                db.add(att)
        db.commit()

    # Create administrative log entries
    logs = [
        AuditLog(action="SYSTEM_INIT", performed_by="System", details="FaceAttend AI biometric ledger successfully initiated."),
        AuditLog(action="DATABASE_SEED", performed_by="System", details="Inserted mock employees, secure face vectors, and historical logs.")
    ]
    for l in logs:
        db.add(l)
    db.commit()
    print("Database seeding completed successfully.")

@app.on_event("startup")
def startup_event():
    """Initializes tables and seeds credentials on server launch."""
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        populate_mock_data(db)
    finally:
        db.close()
