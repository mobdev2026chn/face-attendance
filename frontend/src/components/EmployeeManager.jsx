import React, { useState } from 'react';
import { Search, UserPlus, Trash2, Edit2, ShieldAlert, Check, X, Camera } from 'lucide-react';

export default function EmployeeManager({ 
  employees, 
  onAddEmployee, 
  onDeleteEmployee, 
  onUpdateEmployee,
  onTriggerEnroll,
  enrollingEmpId
}) {
  const [searchTerm, setSearchTerm] = useState('');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  
  // Registration form states
  const [formId, setFormId] = useState('');
  const [formName, setFormName] = useState('');
  const [formDept, setFormDept] = useState('');
  const [formDesig, setFormDesig] = useState('');
  const [formPhone, setFormPhone] = useState('');
  const [formEmail, setFormEmail] = useState('');
  
  // Editing form states
  const [editName, setEditName] = useState('');
  const [editDept, setEditDept] = useState('');
  const [editDesig, setEditDesig] = useState('');

  // Handle register submission
  const handleSubmit = (e) => {
    e.preventDefault();
    if (!formId || !formName || !formDept || !formDesig || !formEmail) return;

    onAddEmployee({
      id: formId,
      full_name: formName,
      department: formDept,
      designation: formDesig,
      phone_number: formPhone || '+1-555-0100',
      email: formEmail,
      is_active: true,
      embeddings: []
    });

    // Reset Form
    setFormId('');
    setFormName('');
    setFormDept('');
    setFormDesig('');
    setFormPhone('');
    setFormEmail('');
    setShowAddForm(false);
  };

  // Start edit line
  const startEdit = (emp) => {
    setEditingId(emp.id);
    setEditName(emp.full_name);
    setEditDept(emp.department);
    setEditDesig(emp.designation);
  };

  // Save edit line
  const saveEdit = (id) => {
    onUpdateEmployee(id, {
      full_name: editName,
      department: editDept,
      designation: editDesig
    });
    setEditingId(null);
  };

  // Search filter
  const filtered = employees.filter(e => {
    const s = searchTerm.toLowerCase();
    return (
      e.full_name.toLowerCase().includes(s) ||
      e.id.toLowerCase().includes(s) ||
      e.department.toLowerCase().includes(s) ||
      e.designation.toLowerCase().includes(s)
    );
  });

  return (
    <div className="glass-panel" style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
        <div>
          <h3 style={{ fontSize: '1rem', fontWeight: '700', color: '#fff' }}>Employee Directory</h3>
          <p style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Manage profiles and biometric enrollments</p>
        </div>
        <button 
          onClick={() => setShowAddForm(!showAddForm)}
          className="btn btn-primary"
          style={{ padding: '8px 14px', fontSize: '0.8rem' }}
        >
          <UserPlus size={16} /> {showAddForm ? 'Cancel' : 'Add Employee'}
        </button>
      </div>

      {/* --- ADD NEW EMPLOYEE FORM PANEL --- */}
      {showAddForm && (
        <form onSubmit={handleSubmit} style={{
          background: 'rgba(0,0,0,0.15)',
          border: '1px solid var(--border-glass)',
          borderRadius: '12px',
          padding: '16px',
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
          gap: '12px'
        }}>
          <div className="form-group">
            <label className="form-label">Employee ID</label>
            <input 
              placeholder="e.g. EMP006" 
              className="form-input" 
              value={formId} 
              onChange={e => setFormId(e.target.value)} 
              required 
            />
          </div>
          <div className="form-group">
            <label className="form-label">Full Name</label>
            <input 
              placeholder="e.g. Elena Smith" 
              className="form-input" 
              value={formName} 
              onChange={e => setFormName(e.target.value)} 
              required 
            />
          </div>
          <div className="form-group">
            <label className="form-label">Department</label>
            <input 
              placeholder="e.g. Engineering" 
              className="form-input" 
              value={formDept} 
              onChange={e => setFormDept(e.target.value)} 
              required 
            />
          </div>
          <div className="form-group">
            <label className="form-label">Designation</label>
            <input 
              placeholder="e.g. Frontend Engineer" 
              className="form-input" 
              value={formDesig} 
              onChange={e => setFormDesig(e.target.value)} 
              required 
            />
          </div>
          <div className="form-group">
            <label className="form-label">Email</label>
            <input 
              type="email"
              placeholder="elena@company.com" 
              className="form-input" 
              value={formEmail} 
              onChange={e => setFormEmail(e.target.value)} 
              required 
            />
          </div>
          <div className="form-group">
            <label className="form-label">Phone Number</label>
            <input 
              placeholder="+1-555-0100" 
              className="form-input" 
              value={formPhone} 
              onChange={e => setFormPhone(e.target.value)} 
            />
          </div>
          <div style={{ gridColumn: '1 / -1', display: 'flex', justifyContent: 'flex-end', marginTop: '6px' }}>
            <button type="submit" className="btn btn-success" style={{ padding: '8px 16px', fontSize: '0.8rem' }}>
              Create Account & Trigger Biometrics
            </button>
          </div>
        </form>
      )}

      {/* Directory Search & Filter */}
      <div style={{ position: 'relative' }}>
        <input 
          placeholder="Search by name, ID, department..." 
          className="form-input" 
          value={searchTerm} 
          onChange={e => setSearchTerm(e.target.value)} 
          style={{ paddingLeft: '36px' }}
        />
        <Search size={16} style={{ position: 'absolute', left: '12px', top: '12px', color: 'var(--text-muted)' }} />
      </div>

      {/* Directory Table */}
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.8rem', textAlign: 'left' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid var(--border-glass)', color: 'var(--text-secondary)' }}>
              <th style={{ padding: '12px 8px' }}>Employee</th>
              <th style={{ padding: '12px 8px' }}>Department</th>
              <th style={{ padding: '12px 8px' }}>Designation</th>
              <th style={{ padding: '12px 8px' }}>Face Template</th>
              <th style={{ padding: '12px 8px', textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(emp => (
              <tr 
                key={emp.id} 
                style={{ 
                  borderBottom: '1px solid rgba(255,255,255,0.03)', 
                  color: 'var(--text-primary)',
                  background: enrollingEmpId === emp.id ? 'rgba(99, 102, 241, 0.05)' : 'none'
                }}
              >
                {/* Employee Base Column */}
                <td style={{ padding: '12px 8px' }}>
                  {editingId === emp.id ? (
                    <input 
                      className="form-input" 
                      style={{ padding: '4px 8px', fontSize: '0.75rem' }} 
                      value={editName} 
                      onChange={e => setEditName(e.target.value)} 
                    />
                  ) : (
                    <div>
                      <span style={{ fontWeight: '700', color: '#fff' }}>{emp.full_name}</span>
                      <span style={{ display: 'block', fontSize: '0.65rem', color: 'var(--text-muted)' }}>ID: {emp.id} | {emp.email}</span>
                    </div>
                  )}
                </td>

                {/* Department Column */}
                <td style={{ padding: '12px 8px' }}>
                  {editingId === emp.id ? (
                    <input 
                      className="form-input" 
                      style={{ padding: '4px 8px', fontSize: '0.75rem' }} 
                      value={editDept} 
                      onChange={e => setEditDept(e.target.value)} 
                    />
                  ) : (
                    emp.department
                  )}
                </td>

                {/* Designation Column */}
                <td style={{ padding: '12px 8px' }}>
                  {editingId === emp.id ? (
                    <input 
                      className="form-input" 
                      style={{ padding: '4px 8px', fontSize: '0.75rem' }} 
                      value={editDesig} 
                      onChange={e => setEditDesig(e.target.value)} 
                    />
                  ) : (
                    emp.designation
                  )}
                </td>

                {/* Face Template Count */}
                <td style={{ padding: '12px 8px' }}>
                  {emp.embeddings && emp.embeddings.length > 0 ? (
                    <span style={{ color: 'var(--color-success)', fontWeight: '600', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <Check size={12} /> Active ({emp.embeddings.length} samples)
                    </span>
                  ) : (
                    <button 
                      onClick={() => onTriggerEnroll(emp.id)}
                      className="btn btn-secondary" 
                      style={{ padding: '4px 8px', fontSize: '0.65rem', color: 'var(--color-warning)', borderColor: 'rgba(245,158,11,0.2)' }}
                    >
                      <Camera size={10} /> Enroll Face
                    </button>
                  )}
                </td>

                {/* Operations Column */}
                <td style={{ padding: '12px 8px', textAlign: 'right' }}>
                  {editingId === emp.id ? (
                    <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                      <button onClick={() => saveEdit(emp.id)} style={{ background: 'none', border: 'none', color: 'var(--color-success)', cursor: 'pointer' }}><Check size={16} /></button>
                      <button onClick={() => setEditingId(null)} style={{ background: 'none', border: 'none', color: 'var(--color-danger)', cursor: 'pointer' }}><X size={16} /></button>
                    </div>
                  ) : (
                    <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                      <button onClick={() => startEdit(emp)} style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer' }}><Edit2 size={14} /></button>
                      <button onClick={() => onDeleteEmployee(emp.id)} style={{ background: 'none', border: 'none', color: 'var(--color-danger)', cursor: 'pointer' }}><Trash2 size={14} /></button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td colSpan="5" style={{ textAlign: 'center', padding: '24px', color: 'var(--text-muted)' }}>
                  No employees matched this query.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
