from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime, date, timedelta
from backend.database import get_db
from backend.models import User, Employee, Attendance, AuditLog
from backend.auth import get_hr_user

router = APIRouter(prefix="/dashboard", tags=["Dashboard Statistics"])

@router.get("/stats")
def get_dashboard_statistics(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_hr_user)
):
    """
    Computes real-time analytical tallies for Admin and HR control dashboard widgets.
    """
    now = datetime.utcnow() + timedelta(hours=5, minutes=30)  # IST adjustment
    today = now.date()

    # 1. Base counts
    total_employees = db.query(Employee).filter(Employee.is_active == True).count()
    
    # 2. Present details (Today)
    today_records = db.query(Attendance).filter(Attendance.date == today).all()
    
    present_today = sum(1 for r in today_records if r.status in ["Present", "Late"])
    late_today = sum(1 for r in today_records if r.status == "Late")
    half_day_today = sum(1 for r in today_records if r.status == "Half-Day")
    
    # Simple logic for absent count
    absent_today = max(0, total_employees - present_today - half_day_today)
    
    # Attendance Rate calculation
    attendance_rate = 100.0
    if total_employees > 0:
        # include half days as 0.5 or just standard presents
        attendance_rate = round(((present_today + half_day_today) / total_employees) * 100, 1)

    # 3. Departmental Distribution tallies
    departments = db.query(Employee.department).distinct().all()
    dept_distribution = []
    
    for (dept,) in departments:
        dept_emps = db.query(Employee).filter(
            Employee.department == dept, 
            Employee.is_active == True
        ).all()
        dept_emp_ids = [e.id for e in dept_emps]
        dept_total = len(dept_emp_ids)
        
        dept_present = db.query(Attendance).filter(
            Attendance.date == today,
            Attendance.employee_id.in_(dept_emp_ids),
            Attendance.status.in_(["Present", "Late"])
        ).count()
        
        dept_absent = max(0, dept_total - dept_present)
        dept_rate = round((dept_present / dept_total) * 100, 1) if dept_total > 0 else 100.0
        
        dept_distribution.append({
            "department": dept,
            "total": dept_total,
            "present": dept_present,
            "absent": dept_absent,
            "rate": dept_rate
        })

    # 4. Activity Logs (last 10 transactions)
    recent_activities = []
    attendance_activities = db.query(Attendance).order_by(Attendance.created_at.desc()).limit(5).all()
    for act in attendance_activities:
        emp = db.query(Employee).filter(Employee.id == act.employee_id).first()
        name = emp.full_name if emp else "Unknown"
        recent_activities.append({
            "type": "ATTENDANCE",
            "employee_id": act.employee_id,
            "employee_name": name,
            "action": "Check-In" if not act.check_out else "Check-Out",
            "time": (act.check_out or act.check_in).strftime("%I:%M %p"),
            "status": act.status
        })

    audit_activities = db.query(AuditLog).filter(
        AuditLog.action.in_(["REGISTER_EMPLOYEE", "DELETE_EMPLOYEE", "MANUAL_ATTENDANCE_ADJUST"])
    ).order_by(AuditLog.timestamp.desc()).limit(5).all()
    
    for act in audit_activities:
        recent_activities.append({
            "type": "AUDIT",
            "employee_id": "SYSTEM",
            "employee_name": act.performed_by,
            "action": act.action.replace("_", " ").title(),
            "time": act.timestamp.strftime("%I:%M %p"),
            "status": "Logged"
        })

    # Sort recent activity by time descending
    recent_activities = recent_activities[:10]

    # Weekly Trends (Last 7 Days)
    weekly_trends = []
    for i in range(6, -1, -1):
        target_date = today - timedelta(days=i)
        day_records = db.query(Attendance).filter(Attendance.date == target_date).all()
        p_count = sum(1 for r in day_records if r.status in ["Present", "Late"])
        weekly_trends.append({
            "date": target_date.strftime("%a %d"),
            "present": p_count,
            "absent": max(0, total_employees - p_count)
        })

    return {
        "summary": {
            "total_employees": total_employees,
            "present_today": present_today,
            "absent_today": absent_today,
            "late_today": late_today,
            "attendance_rate": attendance_rate
        },
        "dept_distribution": dept_distribution,
        "weekly_trends": weekly_trends,
        "recent_activities": recent_activities
    }
