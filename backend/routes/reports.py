from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session
from datetime import datetime, date, timedelta
from typing import List, Optional
import io
from backend.database import get_db
from backend.models import User, Employee, Attendance, AuditLog
from backend.auth import get_hr_user

router = APIRouter(prefix="/reports", tags=["Reports & Analytics"])

@router.get("/summary")
def get_reports_summary(
    report_type: str = Query(..., description="daily, weekly, monthly, department, employee"),
    employee_id: Optional[str] = Query(None),
    department: Optional[str] = Query(None),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_hr_user)
):
    """
    Retrieves filtered attendance metrics based on dates, departments, or individual employees.
    """
    # Fallback default ranges
    now = datetime.utcnow() + timedelta(hours=5, minutes=30)
    today = now.date()
    
    if not start_date:
        if report_type == "daily":
            start_date = today
        elif report_type == "weekly":
            start_date = today - timedelta(days=7)
        else: # monthly or others
            start_date = today - timedelta(days=30)
            
    if not end_date:
        end_date = today

    # Base query for attendance
    query = db.query(Attendance).filter(
        Attendance.date >= start_date,
        Attendance.date <= end_date
    )

    if employee_id:
        query = query.filter(Attendance.employee_id == employee_id)

    # 1. Process Report Details
    records = query.all()
    total_employees = db.query(Employee).filter(Employee.is_active == True).count()

    if report_type == "employee" and employee_id:
        # Generate detailed statistics for one employee
        emp = db.query(Employee).filter(Employee.id == employee_id).first()
        if not emp:
            raise HTTPException(status_code=404, detail="Employee not found")
        
        present_days = sum(1 for r in records if r.status in ["Present", "Late"])
        late_days = sum(1 for r in records if r.status == "Late")
        half_days = sum(1 for r in records if r.status == "Half-Day")
        absent_days = sum(1 for r in records if r.status == "Absent")
        
        total_days = max(1, len(records))
        attendance_percentage = round(((present_days + half_days) / total_days) * 100, 1)
        total_hours = sum(r.total_hours for r in records)
        overtime_hours = sum(r.overtime_hours for r in records)

        return {
            "metadata": {
                "employee_id": emp.id,
                "full_name": emp.full_name,
                "department": emp.department,
                "designation": emp.designation,
                "start_date": start_date,
                "end_date": end_date
            },
            "stats": {
                "present_days": present_days,
                "late_days": late_days,
                "half_days": half_days,
                "absent_days": absent_days,
                "attendance_percentage": attendance_percentage,
                "total_hours": round(total_hours, 2),
                "overtime_hours": round(overtime_hours, 2)
            },
            "records": [
                {
                    "date": r.date,
                    "check_in": r.check_in.strftime("%I:%M %p") if r.check_in else "-",
                    "check_out": r.check_out.strftime("%I:%M %p") if r.check_out else "-",
                    "status": r.status,
                    "total_hours": r.total_hours,
                    "overtime": r.overtime_hours,
                    "device": r.check_in_device
                }
                for r in records
            ]
        }

    elif report_type == "department":
        # Group by departments
        depts = db.query(Employee.department).distinct().all()
        dept_reports = []
        for (dept_name,) in depts:
            if department and dept_name != department:
                continue
            
            dept_emps = db.query(Employee).filter(Employee.department == dept_name, Employee.is_active == True).all()
            emp_ids = [e.id for e in dept_emps]
            dept_total = len(emp_ids)
            
            # Attendance records for these employees in range
            dept_records = db.query(Attendance).filter(
                Attendance.date >= start_date,
                Attendance.date <= end_date,
                Attendance.employee_id.in_(emp_ids)
            ).all()

            p_count = sum(1 for r in dept_records if r.status in ["Present", "Late"])
            l_count = sum(1 for r in dept_records if r.status == "Late")
            h_count = sum(1 for r in dept_records if r.status == "Half-Day")
            
            # calculate metrics
            expected_slots = max(1, dept_total * ((end_date - start_date).days + 1))
            a_rate = round(((p_count + h_count) / expected_slots) * 100, 1)

            dept_reports.append({
                "department": dept_name,
                "total_employees": dept_total,
                "presents": p_count,
                "lates": l_count,
                "half_days": h_count,
                "attendance_rate": a_rate
            })

        return {"reports": dept_reports, "start_date": start_date, "end_date": end_date}

    else:
        # Default Daily/Weekly/Monthly aggregates
        day_logs = {}
        for r in records:
            day_str = r.date.isoformat()
            if day_str not in day_logs:
                day_logs[day_str] = {"p": 0, "l": 0, "h": 0, "a": 0}
            
            if r.status == "Present":
                day_logs[day_str]["p"] += 1
            elif r.status == "Late":
                day_logs[day_str]["l"] += 1
            elif r.status == "Half-Day":
                day_logs[day_str]["h"] += 1
            elif r.status == "Absent":
                day_logs[day_str]["a"] += 1

        trends = []
        for d_str, tallies in sorted(day_logs.items()):
            p_total = tallies["p"] + tallies["l"]
            pct = round((p_total / max(1, total_employees)) * 100, 1)
            trends.append({
                "date": d_str,
                "present": p_total,
                "late": tallies["l"],
                "half_day": tallies["h"],
                "absent": max(0, total_employees - p_total - tallies["h"]),
                "percentage": pct
            })

        return {
            "trends": trends,
            "report_type": report_type,
            "start_date": start_date,
            "end_date": end_date,
            "total_employees": total_employees
        }


# Simulated Exports
@router.get("/export/excel")
def export_excel(
    report_type: str = Query(...),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    db: Session = Depends(get_db)
):
    """
    Exports attendance data as an Excel file.
    Utilizes a simulated in-memory stream representing typical spreadsheet outputs.
    """
    # Create simple CSV-style sheet mapping
    output = io.StringIO()
    output.write("Date,Employee ID,Employee Name,Department,Check-In,Check-Out,Status,Hours Worked,Overtime\n")
    
    # fetch records
    records = db.query(Attendance).all()
    for r in records:
        emp = db.query(Employee).filter(Employee.id == r.employee_id).first()
        name = emp.full_name if emp else "N/A"
        dept = emp.department if emp else "N/A"
        c_in = r.check_in.isoformat() if r.check_in else "-"
        c_out = r.check_out.isoformat() if r.check_out else "-"
        output.write(f"{r.date},{r.employee_id},{name},{dept},{c_in},{c_out},{r.status},{r.total_hours},{r.overtime_hours}\n")
        
    excel_data = output.getvalue().encode('utf-8')
    
    headers = {
        'Content-Disposition': f'attachment; filename="Attendance_Report_{report_type}.xlsx"'
    }
    
    return Response(
        content=excel_data, 
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
        headers=headers
    )


@router.get("/export/pdf")
def export_pdf(
    report_type: str = Query(...),
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    db: Session = Depends(get_db)
):
    """
    Exports attendance summaries as a corporate PDF print document.
    """
    # Create a simulated mock PDF document containing report text layout
    pdf_buffer = io.BytesIO()
    pdf_buffer.write(b"%PDF-1.4\n")
    pdf_buffer.write(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    pdf_buffer.write(b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
    pdf_buffer.write(b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R >>\nendobj\n")
    pdf_buffer.write(b"4 0 obj\n<< /Length 120 >>\nstream\n")
    pdf_buffer.write(f"BT /F1 24 Tf 50 750 Td (FaceAttend AI - Attendance Summary) Tj ET\n".encode())
    pdf_buffer.write(f"BT /F1 12 Tf 50 710 Td (Report Period: {report_type.upper()}) Tj ET\n".encode())
    pdf_buffer.write(f"BT /F1 10 Tf 50 670 Td (Generated by HR admin on {date.today().isoformat()}) Tj ET\n".encode())
    pdf_buffer.write(b"endstream\nendobj\n")
    pdf_buffer.write(b"xref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000062 00000 n\n0000000117 00000 n\n0000000212 00000 n\n")
    pdf_buffer.write(b"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n382\n%%EOF\n")
    
    pdf_data = pdf_buffer.getvalue()
    
    headers = {
        'Content-Disposition': f'attachment; filename="Attendance_Report_{report_type}.pdf"'
    }
    
    return Response(
        content=pdf_data, 
        media_type="application/pdf", 
        headers=headers
    )
