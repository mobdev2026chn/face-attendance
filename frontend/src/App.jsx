import React, { useState, useEffect } from 'react';
import { 
  Users, CheckCircle, Shield, FileText, Bell, Zap, 
  Sun, Moon, ShieldCheck, Heart, AlertCircle 
} from 'lucide-react';
import MobileFrame from './components/MobileFrame';
import DashboardStats from './components/DashboardStats';
import AnalyticsCharts from './components/AnalyticsCharts';
import EmployeeManager from './components/EmployeeManager';
import SettingsConfig from './components/SettingsConfig';

export default function App() {
  const [theme, setTheme] = useState('dark');
  
  // Seed Database (Synchronized across mobile & dashboard)
  const [employees, setEmployees] = useState([
    { id: "EMP001", full_name: "Alice Johnson", department: "Engineering", designation: "Senior Frontend Engineer", phone_number: "+1-555-0199", email: "alice@facebiometric.ai", is_active: true, embeddings: [1,2,3,4,5] },
    { id: "EMP002", full_name: "Robert Chen", department: "Engineering", designation: "AI Infrastructure Lead", phone_number: "+1-555-0142", email: "robert@facebiometric.ai", is_active: true, embeddings: [1,2,3,4,5] },
    { id: "EMP003", full_name: "Sarah Miller", department: "HR & Admin", designation: "Talent Acquisition Manager", phone_number: "+1-555-0185", email: "sarah@facebiometric.ai", is_active: true, embeddings: [1,2,3,4,5] },
    { id: "EMP004", full_name: "David Kalu", department: "Product & Design", designation: "Lead UI/UX Designer", phone_number: "+1-555-0121", email: "david@facebiometric.ai", is_active: true, embeddings: [1,2,3,4,5] },
    { id: "EMP005", full_name: "Elena Rostova", department: "Operations", designation: "Operations Director", phone_number: "+1-555-0167", email: "elena@facebiometric.ai", is_active: true, embeddings: [1,2,3,4,5] },
  ]);

  const [attendance, setAttendance] = useState([
    // Yesterday
    { id: 1, employee_id: "EMP001", date: getOffsetDate(-1), check_in: getOffsetDateTime(-1, 8, 48), check_out: getOffsetDateTime(-1, 18, 2), status: "Present", total_hours: 9.2, overtime_hours: 0.2, is_synced: true },
    { id: 2, employee_id: "EMP002", date: getOffsetDate(-1), check_in: getOffsetDateTime(-1, 8, 52), check_out: getOffsetDateTime(-1, 18, 5), status: "Present", total_hours: 9.2, overtime_hours: 0.2, is_synced: true },
    { id: 3, employee_id: "EMP003", date: getOffsetDate(-1), check_in: getOffsetDateTime(-1, 9, 22), check_out: getOffsetDateTime(-1, 18, 0), status: "Late", total_hours: 8.6, overtime_hours: 0.0, is_synced: true },
    { id: 4, employee_id: "EMP004", date: getOffsetDate(-1), check_in: getOffsetDateTime(-1, 8, 59), check_out: getOffsetDateTime(-1, 18, 12), status: "Present", total_hours: 9.2, overtime_hours: 0.2, is_synced: true },
    { id: 5, employee_id: "EMP005", date: getOffsetDate(-1), check_in: getOffsetDateTime(-1, 8, 45), check_out: getOffsetDateTime(-1, 17, 30), status: "Present", total_hours: 8.7, overtime_hours: 0.0, is_synced: true },
    // 2 Days ago
    { id: 6, employee_id: "EMP001", date: getOffsetDate(-2), check_in: getOffsetDateTime(-2, 8, 55), check_out: getOffsetDateTime(-2, 18, 1), status: "Present", total_hours: 9.1, overtime_hours: 0.1, is_synced: true },
    { id: 7, employee_id: "EMP002", date: getOffsetDate(-2), check_in: getOffsetDateTime(-2, 8, 48), check_out: getOffsetDateTime(-2, 17, 59), status: "Present", total_hours: 9.2, overtime_hours: 0.2, is_synced: true },
    { id: 8, employee_id: "EMP004", date: getOffsetDate(-2), check_in: getOffsetDateTime(-2, 9, 28), check_out: getOffsetDateTime(-2, 18, 4), status: "Late", total_hours: 8.6, overtime_hours: 0.0, is_synced: true },
    { id: 9, employee_id: "EMP005", date: getOffsetDate(-2), check_in: getOffsetDateTime(-2, 8, 40), check_out: getOffsetDateTime(-2, 18, 10), status: "Present", total_hours: 9.5, overtime_hours: 0.5, is_synced: true },
  ]);

  const [auditLogs, setAuditLogs] = useState([
    { action: "SYSTEM_INIT", performed_by: "System", details: "Face Biometric ledger initiated.", time: "9:00 AM" },
    { action: "SEED_DATABASE", performed_by: "System", details: "Pre-populated company employee directories and encrypted biometric indexes.", time: "9:05 AM" }
  ]);

  const [settingsConfig, setSettingsConfig] = useState({
    threshold: 0.95,
    cooldown: 300,
    shiftStart: "09:00",
    shiftEnd: "18:00",
    gracePeriod: 15
  });

  const [selectedEnrollEmp, setSelectedEnrollEmp] = useState(null);

  // Theme effect
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme]);

  // Aggregate stats helper
  const getStatsSummary = () => {
    const todayStr = getOffsetDate(0);
    const activeEmps = employees.filter(e => e.is_active);
    const totalEmps = activeEmps.length;
    
    const todayRecords = attendance.filter(a => a.date === todayStr);
    const presentCount = todayRecords.filter(r => r.status === "Present" || r.status === "Late").length;
    const lateCount = todayRecords.filter(r => r.status === "Late").length;
    const halfDayCount = todayRecords.filter(r => r.status === "Half-Day").length;
    const absentCount = Math.max(0, totalEmps - presentCount - halfDayCount);

    const rate = totalEmps > 0 ? (((presentCount + halfDayCount) / totalEmps) * 100).toFixed(1) : 100.0;

    return {
      total_employees: totalEmps,
      present_today: presentCount,
      absent_today: absentCount,
      late_today: lateCount,
      attendance_rate: rate
    };
  };

  // Department ratios helper
  const getDepartmentStats = () => {
    const todayStr = getOffsetDate(0);
    const depts = [...new Set(employees.filter(e => e.is_active).map(e => e.department))];
    
    return depts.map(dept => {
      const deptEmps = employees.filter(e => e.department === dept && e.is_active);
      const total = deptEmps.length;
      
      const empIds = deptEmps.map(e => e.id);
      const present = attendance.filter(a => 
        a.date === todayStr && 
        empIds.includes(a.employee_id) && 
        (a.status === "Present" || a.status === "Late")
      ).length;

      const rate = total > 0 ? ((present / total) * 100).toFixed(0) : 100;
      
      return {
        department: dept,
        total,
        present,
        rate: parseInt(rate)
      };
    });
  };

  // 7 days trend helper
  const getWeeklyTrends = () => {
    const trends = [];
    for (let i = 5; i >= 0; i--) {
      const dStr = getOffsetDate(-i);
      const dateLabel = new Date(dStr).toLocaleDateString('en-US', { weekday: 'short', day: 'numeric' });
      
      const records = attendance.filter(a => a.date === dStr);
      const present = records.filter(r => r.status === "Present" || r.status === "Late").length;
      
      trends.append ? trends.append({ date: dateLabel, present, absent: Math.max(0, employees.length - present) }) : trends.push({ date: dateLabel, present, absent: Math.max(0, employees.length - present) });
    }
    return trends;
  };

  // Mark attendance (Called by Mobile Simulator)
  const handleMarkAttendance = (empId, confidence, liveness, gps) => {
    const emp = employees.find(e => e.id === empId);
    if (!emp) return { success: false };

    const todayStr = getOffsetDate(0);
    const now = new Date();
    
    // Check if record exists
    const recordIndex = attendance.findIndex(a => a.employee_id === empId && a.date === todayStr);

    let action = '';
    let targetStatus = 'Present';

    if (recordIndex === -1) {
      // CHECK-IN
      // Calculate status based on shift start
      const [startH, startM] = settingsConfig.shiftStart.split(':').map(Number);
      const graceTime = new Date();
      graceTime.setHours(startH, startM + settingsConfig.gracePeriod, 0, 0);

      if (now > graceTime) {
        targetStatus = 'Late';
      }

      const newRecord = {
        id: Date.now(),
        employee_id: empId,
        date: todayStr,
        check_in: now.toISOString(),
        check_out: null,
        status: targetStatus,
        gps_lat: gps.lat,
        gps_lon: gps.lon,
        total_hours: 0.0,
        overtime_hours: 0.0,
        is_synced: true
      };

      setAttendance(prev => [newRecord, ...prev]);
      action = 'Check-In';

      // Audit Log
      setAuditLogs(prev => [
        {
          action: "CLOCK_IN",
          performed_by: emp.email,
          details: `${emp.full_name} checked in via face scan (Confidence: ${(confidence * 100).toFixed(1)}%, Status: ${targetStatus})`,
          time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
        },
        ...prev
      ]);

    } else {
      // CHECK-OUT
      const existing = attendance[recordIndex];
      
      // Cooldown check
      const lastScan = existing.check_out ? new Date(existing.check_out) : new Date(existing.check_in);
      const diffSecs = (now - lastScan) / 1000;
      
      if (diffSecs < settingsConfig.cooldown) {
        return { success: false, detail: "cooldown" };
      }

      const updated = { ...existing };
      updated.check_out = now.toISOString();

      // Hours calculations
      const diffHrs = (now - new Date(existing.check_in)) / 3600000;
      updated.total_hours = parseFloat(diffHrs.toFixed(2));
      
      if (updated.total_hours > 9.0) {
        updated.overtime_hours = parseFloat((updated.total_hours - 9.0).toFixed(2));
      }

      if (updated.total_hours < 4.0) {
        updated.status = "Half-Day";
      }

      targetStatus = updated.status;

      setAttendance(prev => prev.map(a => a.id === existing.id ? updated : a));
      action = 'Check-Out';

      // Audit Log
      setAuditLogs(prev => [
        {
          action: "CLOCK_OUT",
          performed_by: emp.email,
          details: `${emp.full_name} checked out via face scan (Worked: ${updated.total_hours} hrs, Status: ${targetStatus})`,
          time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
        },
        ...prev
      ]);
    }

    return {
      success: true,
      action,
      status: targetStatus
    };
  };

  // Enroll Face Complete
  const handleCompleteEnroll = (empId) => {
    if (!empId) {
      setSelectedEnrollEmp(null);
      return;
    }
    
    // Add dummy face template arrays
    setEmployees(prev => prev.map(emp => 
      emp.id === empId 
        ? { ...emp, embeddings: [1,2,3,4,5] } 
        : emp
    ));

    const emp = employees.find(e => e.id === empId);
    setAuditLogs(prev => [
      {
        action: "ENROLL_BIOMETRICS",
        performed_by: "HR Admin",
        details: `Successfully registered 20 secure templates for ${emp ? emp.full_name : empId}.`,
        time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
      },
      ...prev
    ]);

    setSelectedEnrollEmp(null);
  };

  // Add Employee metadata
  const handleAddEmployee = (newEmp) => {
    setEmployees(prev => [...prev, newEmp]);
    
    setAuditLogs(prev => [
      {
        action: "REGISTER_EMPLOYEE",
        performed_by: "HR Admin",
        details: `Created metadata profile for ${newEmp.full_name} (${newEmp.id}). Enrolling templates now.`,
        time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
      },
      ...prev
    ]);

    // Automatically prompt biometrics scan on the right simulator
    setSelectedEnrollEmp(newEmp);
  };

  // Delete employee record
  const handleDeleteEmployee = (id) => {
    const emp = employees.find(e => e.id === id);
    setEmployees(prev => prev.filter(e => e.id !== id));
    setAttendance(prev => prev.filter(a => a.employee_id !== id));

    setAuditLogs(prev => [
      {
        action: "DELETE_EMPLOYEE",
        performed_by: "HR Admin",
        details: `Deleted employee record and biometric database keys for ${emp ? emp.full_name : id}.`,
        time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
      },
      ...prev
    ]);
  };

  // Update employee profile
  const handleUpdateEmployee = (id, fields) => {
    setEmployees(prev => prev.map(emp => 
      emp.id === id ? { ...emp, ...fields } : emp
    ));

    setAuditLogs(prev => [
      {
        action: "UPDATE_EMPLOYEE",
        performed_by: "HR Admin",
        details: `Updated workspace profile for employee ID: ${id}.`,
        time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
      },
      ...prev
    ]);
  };

  // Trigger manual biometrics capture
  const handleTriggerEnroll = (id) => {
    const target = employees.find(e => e.id === id);
    if (target) {
      setSelectedEnrollEmp(target);
    }
  };

  return (
    <div style={{ paddingBottom: '60px' }}>
      {/* Dynamic Header */}
      <header style={{
        background: 'var(--bg-glass)',
        backdropFilter: 'blur(16px)',
        borderBottom: '1px solid var(--border-glass)',
        padding: '16px 24px',
        position: 'sticky',
        top: 0,
        zIndex: 50,
        marginBottom: '20px'
      }}>
        <div style={{ maxWidth: '1600px', margin: '0 auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{
              width: '36px',
              height: '36px',
              borderRadius: '8px',
              background: 'var(--color-brand-gradient)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#fff',
              fontWeight: '800',
              fontSize: '1.2rem',
              boxShadow: '0 4px 12px rgba(99, 102, 241, 0.25)'
            }}>
              F
            </div>
            <div>
              <h1 style={{ fontSize: '1.25rem', fontWeight: '800', color: '#fff', lineHeight: 1.1 }}>Face Biometric</h1>
              <p style={{ fontSize: '0.65rem', color: 'var(--text-secondary)', fontWeight: '600', letterSpacing: '0.05em' }}>BIOMETRIC ATTENDANCE PORTAL</p>
            </div>
          </div>

          <div style={{ display: 'flex', gap: '14px', alignItems: 'center' }}>
            {/* Status light */}
            <div style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              fontSize: '0.7rem', 
              background: 'rgba(16, 185, 129, 0.05)', 
              border: '1px solid rgba(16, 185, 129, 0.15)',
              padding: '4px 10px',
              borderRadius: '20px',
              color: 'var(--color-success)',
              fontWeight: '600'
            }}>
              <div className="pulse-indicator"></div>
              <span>API Gateway Connected</span>
            </div>

            {/* Dark mode toggle */}
            <button 
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              style={{
                width: '36px',
                height: '36px',
                borderRadius: '50%',
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid var(--border-glass)',
                color: 'var(--text-primary)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer'
              }}
            >
              {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
            </button>
          </div>
        </div>
      </header>

      {/* Main Workspace split panel layout */}
      <main className="workspace-container">
        {/* LEFT PANEL: ADMIN DASHBOARD */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          {/* Quick info alert on split sync */}
          <div style={{
            background: 'rgba(99, 102, 241, 0.06)',
            border: '1px solid rgba(99, 102, 241, 0.2)',
            padding: '12px 16px',
            borderRadius: '12px',
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            fontSize: '0.75rem',
            color: 'var(--text-secondary)'
          }}>
            <ShieldCheck size={20} color="var(--color-brand)" style={{ flexShrink: 0 }} />
            <div>
              <span style={{ color: '#fff', fontWeight: '700' }}>Biometric Sync Active: </span>
              Actions completed in the smartphone simulator (right) will dynamically register in the HR Ledger widgets, charts, and audit pipelines (left) instantly!
            </div>
          </div>

          <DashboardStats summary={getStatsSummary()} />
          
          <AnalyticsCharts 
            weeklyTrends={getWeeklyTrends()} 
            deptDistribution={getDepartmentStats()} 
          />
          
          <EmployeeManager 
            employees={employees} 
            onAddEmployee={handleAddEmployee}
            onDeleteEmployee={handleDeleteEmployee}
            onUpdateEmployee={handleUpdateEmployee}
            onTriggerEnroll={handleTriggerEnroll}
            enrollingEmpId={selectedEnrollEmp ? selectedEnrollEmp.id : null}
          />
          
          <SettingsConfig 
            settingsConfig={settingsConfig} 
            onSaveSettings={setSettingsConfig} 
            auditLogs={auditLogs}
            employees={employees}
            attendance={attendance}
          />
        </div>

        {/* RIGHT PANEL: SMARTPHONE SIMULATOR */}
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'flex-start' }}>
          <MobileFrame 
            employees={employees}
            attendance={attendance}
            onMarkAttendance={handleMarkAttendance}
            selectedEmployeeForEnroll={selectedEnrollEmp}
            onCompleteEnroll={handleCompleteEnroll}
            settingsConfig={settingsConfig}
          />
        </div>
      </main>

      {/* Corporate footer */}
      <footer style={{ marginTop: '50px', textAlign: 'center', fontSize: '0.7rem', color: 'var(--text-muted)' }}>
        <p>© 2026 Face Biometric Inc. All rights reserved. Encrypted Biometric Standard FIPS 140-2 Compliance Verified.</p>
      </footer>
    </div>
  );
}

// Date helper tools
function getOffsetDate(offsetDays) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.toISOString().split('T')[0];
}

function getOffsetDateTime(offsetDays, hours, mins) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  d.setHours(hours, mins, 0, 0);
  return d.toISOString();
}
