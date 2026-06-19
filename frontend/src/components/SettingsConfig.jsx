import React, { useState } from 'react';
import { Shield, Clock, FileText, Database, Download, Check, RefreshCw } from 'lucide-react';

export default function SettingsConfig({ 
  settingsConfig, 
  onSaveSettings, 
  auditLogs,
  employees,
  attendance
}) {
  const [activeTab, setActiveTab] = useState('thresholds'); // thresholds, reports, audit
  const [threshold, setThreshold] = useState(settingsConfig.threshold);
  const [cooldown, setCooldown] = useState(settingsConfig.cooldown);
  const [shiftStart, setShiftStart] = useState(settingsConfig.shiftStart);
  const [shiftEnd, setShiftEnd] = useState(settingsConfig.shiftEnd);
  const [gracePeriod, setGracePeriod] = useState(settingsConfig.gracePeriod);
  
  // Reports states
  const [reportType, setReportType] = useState('daily');
  const [selectedEmp, setSelectedEmp] = useState('');
  const [exportLoading, setExportLoading] = useState(false);
  const [exportSuccess, setExportSuccess] = useState(false);

  const handleSave = (e) => {
    e.preventDefault();
    onSaveSettings({
      threshold: parseFloat(threshold),
      cooldown: parseInt(cooldown),
      shiftStart,
      shiftEnd,
      gracePeriod: parseInt(gracePeriod)
    });
  };

  // Simulate File Exports
  const handleExport = (format) => {
    setExportLoading(true);
    setExportSuccess(false);
    
    setTimeout(() => {
      setExportLoading(false);
      setExportSuccess(true);
      
      // Simulate file download
      const headers = reportType === 'employee' 
        ? "Date,Employee ID,Check-In,Check-Out,Status,Hours worked,Overtime\n" 
        : "Date,Employee Name,ID,Department,Check-In,Check-Out,Status\n";
        
      let content = headers;
      const today = new Date().toISOString().split('T')[0];
      
      if (reportType === 'employee' && selectedEmp) {
        const emp = employees.find(e => e.id === selectedEmp);
        const name = emp ? emp.full_name : 'User';
        content += `${today},${selectedEmp},08:52 AM,06:05 PM,Present,9.2,0.2\n`;
      } else {
        employees.forEach(emp => {
          content += `${today},${emp.full_name},${emp.id},${emp.department},08:55 AM,06:02 PM,Present\n`;
        });
      }

      const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.setAttribute("href", url);
      link.setAttribute("download", `FaceBiometric_Report_${reportType}_${today}.${format === 'excel' ? 'xlsx' : 'pdf'}`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      setTimeout(() => setExportSuccess(false), 2000);
    }, 1500);
  };

  return (
    <div className="glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      {/* Sub Navigation */}
      <div style={{
        display: 'flex',
        borderBottom: '1px solid var(--border-glass)',
        paddingBottom: '10px',
        gap: '16px'
      }}>
        {[
          { id: 'thresholds', label: 'Tuning & Schedule', icon: Shield },
          { id: 'reports', label: 'Export Reports', icon: FileText },
          { id: 'audit', label: 'Audit Logs', icon: Database }
        ].map(tab => {
          const Icon = tab.icon;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              style={{
                background: 'none',
                border: 'none',
                color: activeTab === tab.id ? 'var(--color-brand)' : 'var(--text-secondary)',
                fontWeight: activeTab === tab.id ? '700' : '500',
                fontSize: '0.8rem',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                padding: '4px 8px',
                position: 'relative'
              }}
            >
              <Icon size={14} />
              {tab.label}
              {activeTab === tab.id && (
                <div style={{
                  position: 'absolute',
                  bottom: '-11px',
                  left: 0,
                  width: '100%',
                  height: '2px',
                  background: 'var(--color-brand)'
                }}></div>
              )}
            </button>
          );
        })}
      </div>

      {/* --- SUB-TAB 1: THRESHOLDS & SCHEDULES --- */}
      {activeTab === 'thresholds' && (
        <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px' }}>
            {/* Matching Threshold Slider */}
            <div className="form-group">
              <label className="form-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>Cosine Similarity Limit</span>
                <span style={{ color: 'var(--color-brand)', fontWeight: '700' }}>{(threshold * 100).toFixed(0)}%</span>
              </label>
              <input 
                type="range" 
                min="0.80" 
                max="0.99" 
                step="0.01"
                className="form-input" 
                value={threshold} 
                onChange={e => setThreshold(e.target.value)} 
                style={{ padding: 0, height: '8px', background: 'rgba(255,255,255,0.06)' }}
              />
              <span style={{ fontSize: '0.6rem', color: 'var(--text-muted)' }}>Recommended default: 95%. Lower ranges may bypass spoof filters.</span>
            </div>

            {/* Cooldown Timer Slider */}
            <div className="form-group">
              <label className="form-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>Duplicate Cooldown</span>
                <span style={{ color: 'var(--color-brand)', fontWeight: '700' }}>{cooldown} seconds</span>
              </label>
              <input 
                type="range" 
                min="60" 
                max="600" 
                step="30"
                className="form-input" 
                value={cooldown} 
                onChange={e => setCooldown(e.target.value)} 
                style={{ padding: 0, height: '8px', background: 'rgba(255,255,255,0.06)' }}
              />
              <span style={{ fontSize: '0.6rem', color: 'var(--text-muted)' }}>Minimum window between double face-scans.</span>
            </div>

            {/* Shift start */}
            <div className="form-group">
              <label className="form-label">Shift Start Hours</label>
              <input 
                type="text" 
                className="form-input" 
                value={shiftStart} 
                onChange={e => setShiftStart(e.target.value)} 
                required 
              />
            </div>

            {/* Shift end */}
            <div className="form-group">
              <label className="form-label">Shift Departure Hours</label>
              <input 
                type="text" 
                className="form-input" 
                value={shiftEnd} 
                onChange={e => setShiftEnd(e.target.value)} 
                required 
              />
            </div>

            {/* Grace Period */}
            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <label className="form-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>Late Grace Period</span>
                <span style={{ color: 'var(--color-brand)', fontWeight: '700' }}>{gracePeriod} minutes</span>
              </label>
              <input 
                type="range" 
                min="5" 
                max="60" 
                step="5"
                className="form-input" 
                value={gracePeriod} 
                onChange={e => setGracePeriod(e.target.value)} 
                style={{ padding: 0, height: '8px', background: 'rgba(255,255,255,0.06)' }}
              />
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '10px' }}>
            <button type="submit" className="btn btn-primary" style={{ padding: '8px 16px', fontSize: '0.8rem' }}>
              Save Tuning Overrides
            </button>
          </div>
        </form>
      )}

      {/* --- SUB-TAB 2: REPORTS EXPORTS --- */}
      {activeTab === 'reports' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div>
            <h4 style={{ fontSize: '0.85rem', color: '#fff', fontWeight: '700', marginBottom: '4px' }}>Export Biometric Ledgers</h4>
            <p style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>Download attendance statistics compiled in corporate formats.</p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '12px' }}>
            <div className="form-group">
              <label className="form-label">Report Range</label>
              <select 
                className="form-input" 
                value={reportType} 
                onChange={e => setReportType(e.target.value)}
                style={{ background: '#0a0b10' }}
              >
                <option value="daily">Daily Attendance</option>
                <option value="weekly">Weekly Roll</option>
                <option value="monthly">Monthly Ledger</option>
                <option value="department">Department breakdown</option>
                <option value="employee">Specific Employee profile</option>
              </select>
            </div>

            {reportType === 'employee' && (
              <div className="form-group">
                <label className="form-label">Target Employee</label>
                <select 
                  className="form-input" 
                  value={selectedEmp} 
                  onChange={e => setSelectedEmp(e.target.value)}
                  style={{ background: '#0a0b10' }}
                  required
                >
                  <option value="">Select Employee...</option>
                  {employees.map(e => (
                    <option key={e.id} value={e.id}>{e.full_name} ({e.id})</option>
                  ))}
                </select>
              </div>
            )}
          </div>

          <div style={{ display: 'flex', gap: '10px', marginTop: '10px' }}>
            <button 
              disabled={exportLoading}
              onClick={() => handleExport('excel')}
              className="btn btn-secondary"
              style={{ flex: 1, padding: '10px', fontSize: '0.8rem', display: 'flex', gap: '8px', cursor: 'pointer' }}
            >
              {exportLoading ? (
                <RefreshCw size={14} className="chart-bar" style={{ animation: 'spin 1s linear infinite' }} />
              ) : exportSuccess ? (
                <Check size={14} color="var(--color-success)" />
              ) : (
                <Download size={14} />
              )}
              {exportSuccess ? 'Compiled!' : 'Download MS Excel'}
            </button>
            
            <button 
              disabled={exportLoading}
              onClick={() => handleExport('pdf')}
              className="btn btn-primary"
              style={{ flex: 1, padding: '10px', fontSize: '0.8rem', display: 'flex', gap: '8px', cursor: 'pointer' }}
            >
              {exportLoading ? (
                <RefreshCw size={14} className="chart-bar" style={{ animation: 'spin 1s linear infinite' }} />
              ) : exportSuccess ? (
                <Check size={14} color="var(--color-success)" />
              ) : (
                <Download size={14} />
              )}
              {exportSuccess ? 'Compiled!' : 'Download Corporate PDF'}
            </button>
          </div>
        </div>
      )}

      {/* --- SUB-TAB 3: IMMUTABLE AUDIT LOGS --- */}
      {activeTab === 'audit' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <div>
            <h4 style={{ fontSize: '0.85rem', color: '#fff', fontWeight: '700', marginBottom: '4px' }}>Immutable Security Audit Logs</h4>
            <p style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>System interactions, admin modifications, and clock triggers verified.</p>
          </div>

          <div style={{
            background: 'rgba(0,0,0,0.15)',
            borderRadius: '12px',
            border: '1px solid var(--border-glass)',
            maxHeight: '220px',
            overflowY: 'auto',
            padding: '10px'
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {auditLogs.map((log, idx) => (
                <div key={idx} style={{
                  fontSize: '0.7rem',
                  padding: '6px 10px',
                  background: 'rgba(255,255,255,0.02)',
                  borderRadius: '6px',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  borderLeft: `2px solid ${
                    log.action.includes('REGISTER') ? 'var(--color-brand)' : 
                    log.action.includes('DELETE') ? 'var(--color-danger)' : 'var(--color-success)'
                  }`
                }}>
                  <div>
                    <span style={{ fontWeight: '700', color: '#fff', textTransform: 'uppercase' }}>{log.action.replace('_', ' ')}</span>
                    <p style={{ color: 'var(--text-secondary)', fontSize: '0.65rem', marginTop: '2px' }}>{log.details}</p>
                  </div>
                  <div style={{ textAlign: 'right', fontSize: '0.6rem', color: 'var(--text-muted)' }}>
                    <span>{log.performed_by}</span>
                    <span style={{ display: 'block', marginTop: '2px' }}>{log.time}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
