import React from 'react';

export default function AnalyticsCharts({ weeklyTrends, deptDistribution }) {
  // Compute SVG coordinates for the weekly trend chart
  const maxVal = Math.max(...weeklyTrends.map(t => t.present + t.absent), 10);
  const chartHeight = 140;
  const chartWidth = 420;
  const paddingLeft = 30;
  const paddingBottom = 20;
  const barGap = 16;
  const barWidth = 24;

  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
      gap: '20px',
      marginBottom: '24px'
    }}>
      {/* --- WEEKLY ATTENDANCE TRENDS --- */}
      <div className="glass-panel" style={{ minHeight: '260px', display: 'flex', flexDirection: 'column' }}>
        <h3 style={{ fontSize: '0.95rem', fontWeight: '700', color: '#fff', marginBottom: '16px' }}>Weekly Attendance Trends</h3>
        
        <div style={{ flex: 1, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg viewBox={`0 0 ${chartWidth} ${chartHeight + 40}`} style={{ width: '100%', height: '100%', overflow: 'visible' }}>
            {/* Grid lines */}
            {[0, 0.25, 0.5, 0.75, 1.0].map((ratio, i) => {
              const y = chartHeight * (1 - ratio) + 10;
              const val = Math.round(maxVal * ratio);
              return (
                <g key={i}>
                  <line 
                    x1={paddingLeft} 
                    y1={y} 
                    x2={chartWidth} 
                    y2={y} 
                    stroke="rgba(255,255,255,0.04)" 
                    strokeWidth="1" 
                  />
                  <text 
                    x={paddingLeft - 8} 
                    y={y + 4} 
                    fill="var(--text-muted)" 
                    fontSize="9" 
                    textAnchor="end"
                  >
                    {val}
                  </text>
                </g>
              );
            })}

            {/* Render Bars */}
            {weeklyTrends.map((t, idx) => {
              const total = t.present + t.absent;
              const hPresent = total > 0 ? (t.present / maxVal) * chartHeight : 0;
              const hAbsent = total > 0 ? (t.absent / maxVal) * chartHeight : 0;
              
              const x = paddingLeft + idx * (barWidth + barGap) + barGap;
              const yPresent = chartHeight - hPresent + 10;
              const yAbsent = chartHeight - hPresent - hAbsent + 10;
              
              return (
                <g key={idx} className="chart-group">
                  {/* Absent block (top segment of stack) */}
                  {hAbsent > 0 && (
                    <rect 
                      x={x} 
                      y={yAbsent} 
                      width={barWidth} 
                      height={hAbsent} 
                      fill="rgba(239, 68, 68, 0.85)" 
                      rx="3"
                      style={{ transition: 'height 0.4s ease, y 0.4s ease' }}
                    />
                  )}
                  {/* Present block (bottom segment of stack) */}
                  {hPresent > 0 && (
                    <rect 
                      x={x} 
                      y={yPresent} 
                      width={barWidth} 
                      height={hPresent} 
                      fill="var(--color-brand)" 
                      rx="3"
                      style={{ transition: 'height 0.4s ease, y 0.4s ease' }}
                    />
                  )}
                  {/* X Axis Label */}
                  <text 
                    x={x + barWidth / 2} 
                    y={chartHeight + 24} 
                    fill="var(--text-secondary)" 
                    fontSize="9" 
                    textAnchor="middle"
                  >
                    {t.date}
                  </text>
                </g>
              );
            })}
          </svg>
        </div>

        {/* Legend */}
        <div style={{ display: 'flex', gap: '16px', justifyContent: 'center', marginTop: '12px', fontSize: '0.75rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <div style={{ width: '10px', height: '10px', borderRadius: '3px', background: 'var(--color-brand)' }}></div>
            <span style={{ color: 'var(--text-secondary)' }}>Present / Late</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <div style={{ width: '10px', height: '10px', borderRadius: '3px', background: 'rgba(239,68,68,0.85)' }}></div>
            <span style={{ color: 'var(--text-secondary)' }}>Absent</span>
          </div>
        </div>
      </div>

      {/* --- DEPARTMENT RATIOS --- */}
      <div className="glass-panel" style={{ minHeight: '260px', display: 'flex', flexDirection: 'column' }}>
        <h3 style={{ fontSize: '0.95rem', fontWeight: '700', color: '#fff', marginBottom: '16px' }}>Department Breakdown Today</h3>
        
        <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', flex: 1, justifyContent: 'center' }}>
          {deptDistribution.map((dept, idx) => (
            <div key={idx}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', fontWeight: '600', marginBottom: '4px' }}>
                <span style={{ color: '#fff' }}>{dept.department}</span>
                <span style={{ color: 'var(--text-secondary)' }}>
                  {dept.present}/{dept.total} Present ({dept.rate}%)
                </span>
              </div>
              
              <div style={{
                width: '100%',
                height: '10px',
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid var(--border-glass)',
                borderRadius: '5px',
                overflow: 'hidden',
                position: 'relative'
              }}>
                <div style={{
                  width: `${dept.rate}%`,
                  height: '100%',
                  background: dept.rate > 85 ? 'var(--color-success-gradient)' : (dept.rate > 60 ? 'linear-gradient(90deg, #6366f1, #4f46e5)' : 'linear-gradient(90deg, #ef4444, #f59e0b)'),
                  borderRadius: '5px',
                  transition: 'width 0.6s cubic-bezier(0.4, 0, 0.2, 1)'
                }}></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
