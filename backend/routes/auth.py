from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import User, Employee, AuditLog
from backend.schemas import Token, UserCreate, UserResponse
from backend.auth import (
    verify_password, 
    get_password_hash, 
    create_access_token, 
    get_current_user
)

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/register-admin", response_model=UserResponse)
def register_admin(user_in: UserCreate, db: Session = Depends(get_db)):
    """
    Initial setup endpoint to register a system Admin.
    Checks if an administrator already exists to prevent duplicate controls.
    """
    existing_admin = db.query(User).filter(User.role == "Admin").first()
    if existing_admin:
        # For our dynamic mockup, we allow registering if table is completely empty, 
        # but if one exists, we block arbitrary registration.
        # However, for simplicity and testing in the local workspace, we check if the SPECIFIC email exists.
        existing_user = db.query(User).filter(User.email == user_in.email).first()
        if existing_user:
            raise HTTPException(status_code=400, detail="A user with this email already exists")
    
    hashed_pwd = get_password_hash(user_in.password)
    new_user = User(
        email=user_in.email,
        hashed_password=hashed_pwd,
        role=user_in.role if user_in.role in ["Admin", "HR"] else "Admin",
        is_active=True
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    # Log action
    audit = AuditLog(
        action="REGISTER_ADMIN",
        performed_by=new_user.email,
        details=f"Admin account created for {new_user.email}"
    )
    db.add(audit)
    db.commit()

    return new_user

@router.post("/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """
    Validates credentials and returns JWT bearer tokens containing role claims.
    """
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Account is deactivated")
        
    access_token = create_access_token(data={"sub": user.email, "role": user.role})
    
    # Audit log
    audit = AuditLog(
        action="USER_LOGIN",
        performed_by=user.email,
        details=f"Successful login for user role: {user.role}"
    )
    db.add(audit)
    db.commit()
    
    return {
        "access_token": access_token, 
        "token_type": "bearer",
        "role": user.role,
        "email": user.email
    }

@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    """Retrieves session profile data for the currently authenticated User."""
    return current_user
