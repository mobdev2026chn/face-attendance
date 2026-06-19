import React from 'react';
import { Users, CheckCircle, XCircle, Clock, TrendingUp } from 'lucide-react';

export default function DashboardStats({ summary }) {
  const cards = [
    {
      title: "Total Employees",
      value: summary.total_employees,
      icon: Users,
      color: "var(--color-brand)",
      bg: "var(--color-brand-glow)",
      desc: "Registered profiles"
    },
    {
      title: "Present Today",
      value: summary.present_today,
      icon: CheckCircle,
      color: "var(--color-success)",
      bg: "var(--color-success-glow)",
      desc: "Clocked check-in"
    },
    {
      title: "Absent Today",
      value: summary.absent_today,
      icon: XCircle,
      color: "var(--color-danger)",
      bg: "var(--color-danger-glow)",
      desc: "Unclocked schedules"
    },
    {
      title: "Late Employees",
      value: summary.late_today,
      icon: Clock,
      color: "var(--color-warning)",
      bg: "var(--color-warning-glow)",
      desc: "Past grace periods"
    },
    {
      title: "Attendance Rate",
      value: `${summary.attendance_rate}%`,
      icon: TrendingUp,
      color: "var(--color-brand)",
      bg: "rgba(99, 102, 241, 0.08)",
      desc: "Daily efficiency rating"
    }
  ];

  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
      gap: '16px',
      marginBottom: '24px'
    }}>
      {cards.map((c, i) => {
        const IconComponent = c.icon;
        return (
          <div key={i} className="glass-panel" style={{
            padding: '20px',
            display: 'flex',
            alignItems: 'center',
            gap: '16px',
            position: 'relative',
            overflow: 'hidden'
          }}>
            {/* Background glowing sphere */}
            <div style={{
              position: 'absolute',
              top: '-20px',
              right: '-20px',
              width: '60px',
              height: '60px',
              borderRadius: '50%',
              background: c.color,
              opacity: 0.04,
              filter: 'blur(10px)'
            }}></div>

            <div style={{
              width: '48px',
              height: '48px',
              borderRadius: '12px',
              background: c.bg,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: c.color
            }}>
              <IconComponent size={24} />
            </div>

            <div>
              <p style={{ fontSize: '0.75rem', fontWeight: '600', color: 'var(--text-secondary)' }}>{c.title}</p>
              <h3 style={{ fontSize: '1.5rem', fontWeight: '800', color: '#fff', margin: '2px 0 0 0', lineHeight: 1.1 }}>{c.value}</h3>
              <p style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginTop: '2px' }}>{c.desc}</p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
