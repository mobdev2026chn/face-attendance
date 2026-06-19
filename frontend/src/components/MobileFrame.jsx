import React, { useState, useEffect } from 'react';
import { 
  Camera, User, Calendar, Bell, ChevronLeft, Lock, ShieldCheck, 
  MapPin, RefreshCw, Cpu, Award, Zap, AlertTriangle 
} from 'lucide-react';

export default function MobileFrame({ 
  employees, 
  attendance, 
  onMarkAttendance, 
  selectedEmployeeForEnroll,
  onCompleteEnroll,
  settingsConfig
}) {
  const [screen, setScreen] = useState('lock'); // lock, home, scanner, enroll, profile
  const [activeUser, setActiveUser] = useState(null);
  
  // Scanner states
  const [livenessChallenge, setLivenessChallenge] = useState('blink'); // blink, turn_left, turn_right, tilt_up
  const [challengeProgress, setChallengeProgress] = useState(0); // 0 to 100
  const [scanStatus, setScanStatus] = useState('idle'); // idle, scanning, challenging, success, failed
  const [detectedEmployee, setDetectedEmployee] = useState(null);
  const [confidenceScore, setConfidenceScore] = useState(0);
  const [gpsVerified, setGpsVerified] = useState(true);
  const [notifications, setNotifications] = useState([
    { id: 1, text: "Welcome to Face Biometric!", time: "9:00 AM" }
  ]);

  // Enrollment states
  const [enrollProgress, setEnrollProgress] = useState(0); // 0 to 20
  const [currentLighting, setCurrentLighting] = useState('normal'); // normal, bright, dim
  const [currentPose, setCurrentPose] = useState('front'); // front, left, right, up, down
  const [enrollStatus, setEnrollStatus] = useState('idle'); // idle, enrolling, complete

  // Time state for status bar
  const [currentTime, setCurrentTime] = useState('09:12 AM');

  useEffect(() => {
    const updateTime = () => {
      const d = new Date();
      let hrs = d.getHours();
      const mins = String(d.getMinutes()).padStart(2, '0');
      const amp = hrs >= 12 ? 'PM' : 'AM';
      hrs = hrs % 12 || 12;
      setCurrentTime(`${hrs}:${mins} ${amp}`);
    };
    updateTime();
    const interval = setInterval(updateTime, 60000);
    return () => clearInterval(interval);
  }, []);

  // Lockscreen bypass for demo
  const handleUnlock = (email) => {
    const matched = employees.find(e => e.email === email) || employees[0];
    setActiveUser(matched);
    setScreen('home');
  };

  // Run mock scanner sequence
  const startScan = () => {
    setScanStatus('scanning');
    setDetectedEmployee(null);
    setConfidenceScore(0);
    
    // Step 1: Detect Face (< 1 second)
    setTimeout(() => {
      // Pick a random employee from the database to simulate detection
      const randomEmp = employees[Math.floor(Math.random() * employees.length)];
      setDetectedEmployee(randomEmp);
      
      const targetConfidence = (95 + Math.random() * 4.5).toFixed(1);
      setConfidenceScore(targetConfidence);
      
      // Step 2: Trigger Liveness Challenge
      const challenges = ['blink', 'turn_left', 'turn_right', 'tilt_up'];
      const nextChallenge = challenges[Math.floor(Math.random() * challenges.length)];
      setLivenessChallenge(nextChallenge);
      setScanStatus('challenging');
      setChallengeProgress(20);

      // Step 3: Complete challenge progressively
      let progress = 20;
      const interval = setInterval(() => {
        progress += 30;
        setChallengeProgress(Math.min(100, progress));
        
        if (progress >= 100) {
          clearInterval(interval);
          
          // Step 4: Check-in / Check-out on backend
          setTimeout(() => {
            const gpsCoords = { lat: 37.7749 + (Math.random() - 0.5) * 0.001, lon: -122.4194 + (Math.random() - 0.5) * 0.001 };
            
            const result = onMarkAttendance(
              randomEmp.id, 
              parseFloat(targetConfidence) / 100.0, 
              0.97, // liveness score
              gpsCoords
            );
            
            if (result && result.success) {
              setScanStatus('success');
              
              // Push mock notification
              const actionText = result.action === 'Check-In' ? 'Checked in' : 'Checked out';
              setNotifications(prev => [
                { id: Date.now(), text: `${actionText} successfully! Status: ${result.status}`, time: 'Just now' },
                ...prev
              ]);

              // Update active user state to match scanner results if it's the current user
              if (activeUser && activeUser.id === randomEmp.id) {
                // updates local profile status
              }
            } else {
              setScanStatus('failed');
            }
          }, 600);
        }
      }, 500);

    }, 1200);
  };

  // Mock enrollment sequence
  const startEnrollment = () => {
    if (!selectedEmployeeForEnroll) return;
    setEnrollStatus('enrolling');
    setEnrollProgress(0);
    
    let currentSamples = 0;
    const interval = setInterval(() => {
      currentSamples += 1;
      setEnrollProgress(currentSamples);
      
      // Rotate lighting and pose guidelines
      if (currentSamples % 5 === 1) setCurrentPose('slight_left');
      else if (currentSamples % 5 === 2) setCurrentPose('slight_right');
      else if (currentSamples % 5 === 3) setCurrentPose('slight_up');
      else if (currentSamples % 5 === 4) setCurrentPose('slight_down');
      else setCurrentPose('front');

      if (currentSamples >= 15) setCurrentLighting('dim');
      else if (currentSamples >= 8) setCurrentLighting('bright');
      else setCurrentLighting('normal');

      if (currentSamples >= 20) {
        clearInterval(interval);
        setEnrollStatus('complete');
        
        // callback to save biometric vectors
        setTimeout(() => {
          onCompleteEnroll(selectedEmployeeForEnroll.id);
          setScreen('home');
          setEnrollStatus('idle');
          setEnrollProgress(0);
        }, 1200);
      }
    }, 200);
  };

  useEffect(() => {
    if (selectedEmployeeForEnroll) {
      setScreen('enroll');
    }
  }, [selectedEmployeeForEnroll]);

  // Check today's status of active employee
  const getTodayStatus = (empId) => {
    if (!empId) return { checkIn: '-', checkOut: '-', status: 'Absent' };
    const todayStr = new Date().toISOString().split('T')[0];
    const log = attendance.find(a => a.employee_id === empId && a.date === todayStr);
    
    if (!log) return { checkIn: '-', checkOut: '-', status: 'Absent' };
    
    const formatTime = (dtStr) => {
      if (!dtStr) return '-';
      const d = new Date(dtStr);
      let hrs = d.getHours();
      const mins = String(d.getMinutes()).padStart(2, '0');
      const amp = hrs >= 12 ? 'PM' : 'AM';
      hrs = hrs % 12 || 12;
      return `${hrs}:${mins} ${amp}`;
    };

    return {
      checkIn: formatTime(log.check_in),
      checkOut: formatTime(log.check_out),
      status: log.status
    };
  };

  const todayStatus = activeUser ? getTodayStatus(activeUser.id) : null;

  return (
    <div className="phone-mockup">
      <div className="phone-screen">
        {/* Notch */}
        <div className="phone-notch">
          <div className="phone-speaker"></div>
          <div className="phone-camera"></div>
        </div>

        {/* Status Bar */}
        <div style={{
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center', 
          padding: '28px 16px 8px 16px',
          fontSize: '0.75rem',
          fontWeight: '600',
          color: 'var(--text-primary)',
          background: 'rgba(0,0,0,0.1)',
          zIndex: 10
        }}>
          <span>{currentTime.split(' ')[0]}</span>
          <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
            <span style={{ fontSize: '0.65rem' }}>5G</span>
            <div style={{ width: '16px', height: '9px', border: '1px solid var(--text-primary)', borderRadius: '2px', padding: '1px', display: 'flex' }}>
              <div style={{ flex: 1, background: 'var(--text-primary)', borderRadius: '1px' }}></div>
            </div>
          </div>
        </div>

        {/* Dynamic Screen Mounting */}
        
        {/* --- LOCK SCREEN --- */}
        {screen === 'lock' && (
          <div style={{
            flex: 1, 
            display: 'flex', 
            flexDirection: 'column', 
            justifyContent: 'space-between',
            alignItems: 'center',
            padding: '30px 20px',
            background: 'linear-gradient(180deg, #10111a 0%, #1e1b4b 100%)',
            textAlign: 'center'
          }}>
            <div>
              <h2 style={{ fontSize: '2rem', fontWeight: '800', marginTop: '40px', color: '#fff', textShadow: '0 4px 12px rgba(0,0,0,0.4)' }}>Face Biometric</h2>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', marginTop: '6px' }}>Enterprise Biometric Portal</p>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '20px' }}>
              <div 
                onClick={() => handleUnlock('alice@facebiometric.ai')}
                style={{
                  width: '96px',
                  height: '96px',
                  borderRadius: '50%',
                  background: 'var(--color-brand-gradient)',
                  boxShadow: '0 8px 30px rgba(99, 102, 241, 0.4), inset 0 2px 4px rgba(255,255,255,0.3)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  animation: 'pulse-ring 2s infinite'
                }}
              >
                <ShieldCheck size={48} color="#fff" />
              </div>
              <p style={{ color: '#fff', fontSize: '0.875rem', fontWeight: '500' }}>Tap Biometric to Authenticate</p>
            </div>

            <div style={{ width: '100%' }}>
              <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '10px' }}>Demo Quick Login Profile:</p>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', justifyContent: 'center' }}>
                {employees.slice(0, 3).map(e => (
                  <button 
                    key={e.id}
                    onClick={() => handleUnlock(e.email)}
                    style={{
                      padding: '6px 12px',
                      background: 'rgba(255,255,255,0.06)',
                      border: '1px solid rgba(255,255,255,0.1)',
                      color: 'var(--text-primary)',
                      borderRadius: '20px',
                      fontSize: '0.7rem',
                      cursor: 'pointer'
                    }}
                  >
                    {e.full_name.split(' ')[0]}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* --- HOME SCREEN --- */}
        {screen === 'home' && activeUser && (
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflowY: 'auto', padding: '16px' }}>
            {/* Header User Card */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <div>
                <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Welcome back,</span>
                <h3 style={{ fontSize: '1.25rem', fontWeight: '700', color: '#fff' }}>{activeUser.full_name}</h3>
                <span style={{ fontSize: '0.7rem', color: 'var(--color-brand)', fontWeight: '600' }}>{activeUser.designation}</span>
              </div>
              <div 
                onClick={() => setScreen('profile')}
                style={{
                  width: '44px',
                  height: '44px',
                  borderRadius: '50%',
                  background: '#6366f1',
                  border: '2px solid rgba(255,255,255,0.2)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#fff',
                  fontWeight: '700',
                  cursor: 'pointer'
                }}
              >
                {activeUser.full_name.split(' ').map(n=>n[0]).join('')}
              </div>
            </div>

            {/* Attendance Status Ledger */}
            <div style={{
              background: 'rgba(255, 255, 255, 0.04)',
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: '20px',
              padding: '16px',
              marginBottom: '20px'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                <span style={{ fontSize: '0.75rem', fontWeight: '600', color: 'var(--text-secondary)' }}>TODAY'S LEDGER</span>
                <div className={`verification-badge badge-${todayStatus.status.toLowerCase().replace(' ', '')}`}>
                  {todayStatus.status}
                </div>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', textAlign: 'center' }}>
                <div style={{ background: 'rgba(0,0,0,0.15)', padding: '10px', borderRadius: '12px' }}>
                  <p style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>CHECK-IN</p>
                  <p style={{ fontSize: '0.9rem', fontWeight: '700', color: '#fff', marginTop: '2px' }}>{todayStatus.checkIn}</p>
                </div>
                <div style={{ background: 'rgba(0,0,0,0.15)', padding: '10px', borderRadius: '12px' }}>
                  <p style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>CHECK-OUT</p>
                  <p style={{ fontSize: '0.9rem', fontWeight: '700', color: '#fff', marginTop: '2px' }}>{todayStatus.checkOut}</p>
                </div>
              </div>
            </div>

            {/* Glowing Big Attendance Trigger */}
            <div style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              flex: 1,
              margin: '20px 0',
              textAlign: 'center'
            }}>
              <div 
                onClick={() => {
                  setScreen('scanner');
                  startScan();
                }}
                style={{
                  width: '130px',
                  height: '130px',
                  borderRadius: '50%',
                  background: 'linear-gradient(135deg, #4f46e5 0%, #6366f1 100%)',
                  boxShadow: '0 12px 40px rgba(99, 102, 241, 0.4), inset 0 2px 6px rgba(255,255,255,0.4)',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '6px',
                  cursor: 'pointer',
                  transition: 'all 0.2s',
                  transform: 'scale(1)',
                }}
                onMouseDown={(e)=>e.currentTarget.style.transform='scale(0.96)'}
                onMouseUp={(e)=>e.currentTarget.style.transform='scale(1)'}
              >
                <Camera size={36} color="#fff" />
                <span style={{ fontSize: '0.75rem', fontWeight: '700', color: '#fff', letterSpacing: '0.05em' }}>SCAN FACE</span>
              </div>
              <p style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '16px' }}>Face recognition will mark clock timings</p>
            </div>

            {/* Simulated GPS Shield */}
            <div style={{
              background: 'rgba(16, 185, 129, 0.06)',
              border: '1px solid rgba(16, 185, 129, 0.15)',
              borderRadius: '12px',
              padding: '10px 14px',
              display: 'flex',
              alignItems: 'center',
              gap: '10px',
              marginBottom: '16px'
            }}>
              <div className="pulse-indicator"></div>
              <div style={{ flex: 1 }}>
                <p style={{ fontSize: '0.7rem', color: 'var(--color-success)', fontWeight: '700' }}>GPS SECURE LINK</p>
                <p style={{ fontSize: '0.65rem', color: 'var(--text-secondary)' }}>HQ Branch Location Verified (Accuracy: 4.2m)</p>
              </div>
              <MapPin size={16} color="var(--color-success)" />
            </div>

            {/* Notification logs */}
            <div>
              <h4 style={{ fontSize: '0.8rem', fontWeight: '700', color: 'var(--text-secondary)', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                <Bell size={12} /> PUSH NOTIFICATIONS
              </h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                {notifications.map(n => (
                  <div key={n.id} style={{
                    background: 'rgba(255,255,255,0.03)',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    fontSize: '0.7rem',
                    borderLeft: '2px solid var(--color-brand)'
                  }}>
                    <p style={{ color: '#fff' }}>{n.text}</p>
                    <span style={{ color: 'var(--text-muted)', fontSize: '0.6rem' }}>{n.time}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* --- LIVE FACE RECOGNITION SCANNER --- */}
        {screen === 'scanner' && (
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '20px', background: '#07080d' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '20px' }}>
              <button 
                onClick={() => setScreen('home')}
                style={{ background: 'none', border: 'none', color: '#fff', cursor: 'pointer', display: 'flex', alignItems: 'center' }}
              >
                <ChevronLeft size={20} />
              </button>
              <h3 style={{ fontSize: '1rem', fontWeight: '700', color: '#fff', marginLeft: '8px' }}>Scanning Biometrics</h3>
            </div>

            {/* Camera View Simulator Container */}
            <div className="scanner-container" style={{ height: '300px', marginBottom: '20px', position: 'relative' }}>
              <div className="scanner-beam"></div>
              
              {/* Simulated camera grid backgrounds */}
              <div style={{
                width: '100%',
                height: '100%',
                background: 'radial-gradient(circle, #1a1a2e 0%, #030305 100%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                position: 'relative'
              }}>
                {/* Simulated Webcam Silhouette */}
                <div style={{
                  width: '180px',
                  height: '180px',
                  borderRadius: '50%',
                  border: '2px dashed rgba(99, 102, 241, 0.4)',
                  position: 'absolute',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  animation: 'pulse-ring 2s infinite'
                }}>
                  {scanStatus === 'scanning' && (
                    <Cpu size={48} className="chart-bar" style={{ animation: 'spin 4s linear infinite', opacity: 0.5 }} />
                  )}
                  {scanStatus === 'challenging' && (
                    <div style={{ color: 'var(--color-brand)', textAlign: 'center' }}>
                      <Zap size={32} style={{ margin: '0 auto 6px auto' }} />
                      <p style={{ fontSize: '0.65rem', fontWeight: '800', textTransform: 'uppercase' }}>LIVENESS TEST</p>
                    </div>
                  )}
                  {scanStatus === 'success' && (
                    <ShieldCheck size={64} color="var(--color-success)" style={{ filter: 'drop-shadow(0 0 12px var(--color-success))' }} />
                  )}
                  {scanStatus === 'failed' && (
                    <AlertTriangle size={64} color="var(--color-danger)" style={{ filter: 'drop-shadow(0 0 12px var(--color-danger))' }} />
                  )}
                </div>

                {/* Simulated Landmark dots */}
                {scanStatus === 'challenging' && (
                  <div style={{ position: 'absolute', width: '180px', height: '180px' }}>
                    <div style={{ position: 'absolute', top: '40px', left: '60px', width: '4px', height: '4px', background: '#00ffcc', borderRadius: '50%' }}></div>
                    <div style={{ position: 'absolute', top: '40px', right: '60px', width: '4px', height: '4px', background: '#00ffcc', borderRadius: '50%' }}></div>
                    <div style={{ position: 'absolute', top: '90px', left: '88px', width: '4px', height: '4px', background: '#00ffcc', borderRadius: '50%' }}></div>
                    <div style={{ position: 'absolute', bottom: '50px', left: '65px', width: '4px', height: '4px', background: '#00ffcc', borderRadius: '50%' }}></div>
                    <div style={{ position: 'absolute', bottom: '50px', right: '65px', width: '4px', height: '4px', background: '#00ffcc', borderRadius: '50%' }}></div>
                  </div>
                )}
              </div>
            </div>

            {/* Recognition analytical feedback cards */}
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
              {scanStatus === 'scanning' && (
                <div style={{ textAlign: 'center' }}>
                  <p style={{ color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>DETECTING FRONT FACE...</p>
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.65rem', marginTop: '4px' }}>Please look directly into the front camera feed</p>
                </div>
              )}

              {scanStatus === 'challenging' && (
                <div style={{ background: 'rgba(99, 102, 241, 0.08)', border: '1px solid rgba(99, 102, 241, 0.2)', padding: '16px', borderRadius: '16px', textAlign: 'center' }}>
                  <span style={{ fontSize: '0.65rem', color: 'var(--color-brand)', fontWeight: '800', letterSpacing: '0.1em' }}>ANTI-SPOOF CHALLENGE</span>
                  <h3 style={{ fontSize: '1.1rem', color: '#fff', margin: '4px 0 10px 0', textTransform: 'uppercase' }}>
                    {livenessChallenge === 'blink' && 'Blink your eyes!'}
                    {livenessChallenge === 'turn_left' && 'Turn head left!'}
                    {livenessChallenge === 'turn_right' && 'Turn head right!'}
                    {livenessChallenge === 'tilt_up' && 'Look up slightly!'}
                  </h3>
                  
                  {/* Progress bar */}
                  <div style={{ width: '100%', height: '6px', background: 'rgba(255,255,255,0.06)', borderRadius: '3px', overflow: 'hidden' }}>
                    <div style={{ width: `${challengeProgress}%`, height: '100%', background: 'var(--color-brand)', transition: 'width 0.3s' }}></div>
                  </div>
                </div>
              )}

              {scanStatus === 'success' && detectedEmployee && (
                <div style={{ background: 'rgba(16, 185, 129, 0.08)', border: '1px solid rgba(16, 185, 129, 0.2)', padding: '16px', borderRadius: '16px', textAlign: 'center' }}>
                  <span style={{ fontSize: '0.65rem', color: 'var(--color-success)', fontWeight: '800' }}>BIOMETRIC VERIFIED</span>
                  <h3 style={{ fontSize: '1.2rem', color: '#fff', margin: '2px 0' }}>{detectedEmployee.full_name}</h3>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>ID: {detectedEmployee.id} | {detectedEmployee.department}</p>
                  
                  <div style={{ display: 'flex', gap: '8px', justifyContent: 'center', marginTop: '10px', fontSize: '0.65rem' }}>
                    <span style={{ padding: '3px 8px', background: 'rgba(0,0,0,0.3)', borderRadius: '10px', color: 'var(--color-success)', fontWeight: '700' }}>
                      Match Confidence: {confidenceScore}%
                    </span>
                    <span style={{ padding: '3px 8px', background: 'rgba(0,0,0,0.3)', borderRadius: '10px', color: '#fff' }}>
                      Liveness: 97.4%
                    </span>
                  </div>

                  <button 
                    onClick={() => setScreen('home')}
                    className="btn btn-success" 
                    style={{ width: '100%', marginTop: '14px', fontSize: '0.75rem', padding: '8px' }}
                  >
                    Back to Home
                  </button>
                </div>
              )}

              {scanStatus === 'failed' && (
                <div style={{ background: 'rgba(239,68,68, 0.08)', border: '1px solid rgba(239, 68, 68, 0.2)', padding: '16px', borderRadius: '16px', textAlign: 'center' }}>
                  <span style={{ fontSize: '0.65rem', color: 'var(--color-danger)', fontWeight: '800' }}>VERIFICATION FAILED</span>
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', margin: '6px 0 12px 0' }}>Confidence rating below 95.0% threshold.</p>
                  <button 
                    onClick={startScan}
                    className="btn btn-danger" 
                    style={{ width: '100%', fontSize: '0.75rem', padding: '8px' }}
                  >
                    Retry Recognition
                  </button>
                </div>
              )}
            </div>
          </div>
        )}

        {/* --- BIOMETRIC FACE ENROLLMENT SCREEN --- */}
        {screen === 'enroll' && selectedEmployeeForEnroll && (
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '20px', background: '#08090d' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '20px' }}>
              <button 
                onClick={() => {
                  onCompleteEnroll(null);
                  setScreen('home');
                }}
                style={{ background: 'none', border: 'none', color: '#fff', cursor: 'pointer', display: 'flex', alignItems: 'center' }}
              >
                <ChevronLeft size={20} />
              </button>
              <h3 style={{ fontSize: '1rem', fontWeight: '700', color: '#fff', marginLeft: '8px' }}>Facial Enrollment</h3>
            </div>

            {/* Profile detail card */}
            <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: '12px', padding: '12px', marginBottom: '16px' }}>
              <p style={{ fontSize: '0.65rem', color: 'var(--text-muted)', fontWeight: '700' }}>ENROLLING EMPLOYEE</p>
              <h4 style={{ fontSize: '0.9rem', color: '#fff', fontWeight: '700' }}>{selectedEmployeeForEnroll.full_name}</h4>
              <p style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>ID: {selectedEmployeeForEnroll.id} | {selectedEmployeeForEnroll.department}</p>
            </div>

            {/* Camera Enrollment Capture Box */}
            <div className="scanner-container" style={{ height: '240px', marginBottom: '16px' }}>
              <div className="scanner-beam"></div>
              
              <div style={{
                width: '100%',
                height: '100%',
                background: 'radial-gradient(circle, #1a1a2e 0%, #030305 100%)',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                position: 'relative'
              }}>
                {/* Silhouette guide circle */}
                <div style={{
                  width: '140px',
                  height: '140px',
                  borderRadius: '50%',
                  border: '2px solid var(--color-brand)',
                  position: 'absolute',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}>
                  {enrollStatus === 'enrolling' && (
                    <div style={{ position: 'absolute', width: '100%', height: '100%', borderRadius: '50%', border: '4px solid transparent', borderTopColor: 'var(--color-success)', animation: 'spin 1s linear infinite' }} />
                  )}
                  
                  <User size={48} color="rgba(99, 102, 241, 0.4)" />
                </div>

                {enrollStatus === 'enrolling' && (
                  <div style={{
                    position: 'absolute',
                    bottom: '10px',
                    background: 'rgba(0,0,0,0.7)',
                    padding: '3px 10px',
                    borderRadius: '20px',
                    fontSize: '0.6rem',
                    color: '#fff',
                    fontWeight: '700'
                  }}>
                    CAPTURE: {enrollProgress} / 20 SAMPLES
                  </div>
                )}
              </div>
            </div>

            {/* Enrollment guidelines */}
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
              {enrollStatus === 'idle' && (
                <div style={{ textAlign: 'center' }}>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginBottom: '16px' }}>
                    Capture 20 high-fidelity facial vector templates under dynamic poses and lights.
                  </p>
                  <button 
                    onClick={startEnrollment}
                    className="btn btn-primary" 
                    style={{ width: '100%', fontSize: '0.8rem' }}
                  >
                    Start Capture Cycle
                  </button>
                </div>
              )}

              {enrollStatus === 'enrolling' && (
                <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)', padding: '14px', borderRadius: '12px', textAlign: 'center' }}>
                  <span style={{ fontSize: '0.65rem', color: 'var(--color-brand)', fontWeight: '800' }}>GUIDE POSE CHALLENGE</span>
                  <h4 style={{ fontSize: '1rem', color: '#fff', margin: '4px 0', textTransform: 'uppercase' }}>
                    {currentPose === 'front' && 'Look straight center'}
                    {currentPose === 'slight_left' && 'Turn head slightly left'}
                    {currentPose === 'slight_right' && 'Turn head slightly right'}
                    {currentPose === 'slight_up' && 'Tilt chin slightly up'}
                    {currentPose === 'slight_down' && 'Tilt chin slightly down'}
                  </h4>

                  <div style={{ display: 'flex', gap: '6px', justifyContent: 'center', marginTop: '10px' }}>
                    <span style={{ fontSize: '0.6rem', padding: '3px 8px', background: 'rgba(0,0,0,0.2)', borderRadius: '10px', color: 'var(--color-warning)', fontWeight: '600' }}>
                      LIGHT: {currentLighting.toUpperCase()}
                    </span>
                    <span style={{ fontSize: '0.6rem', padding: '3px 8px', background: 'rgba(0,0,0,0.2)', borderRadius: '10px', color: 'var(--text-secondary)', fontWeight: '600' }}>
                      ENVELOPE SECURE: OK
                    </span>
                  </div>
                </div>
              )}

              {enrollStatus === 'complete' && (
                <div style={{ textAlign: 'center' }}>
                  <div style={{ display: 'inline-flex', width: '48px', height: '48px', borderRadius: '50%', background: 'var(--color-success-glow)', border: '1px solid var(--color-success)', alignItems: 'center', justifyItems: 'center', justifyContent: 'center', marginBottom: '8px' }}>
                    <ShieldCheck size={28} color="var(--color-success)" />
                  </div>
                  <h4 style={{ color: '#fff', fontSize: '0.9rem', fontWeight: '700' }}>ENROLLMENT COMPLETED</h4>
                  <p style={{ fontSize: '0.7rem', color: 'var(--text-secondary)', marginTop: '2px' }}>Biometric templates successfully generated & encrypted in database.</p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* --- PROFILE / ID SCREEN --- */}
        {screen === 'profile' && activeUser && (
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '20px', overflowY: 'auto' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '20px' }}>
              <button 
                onClick={() => setScreen('home')}
                style={{ background: 'none', border: 'none', color: '#fff', cursor: 'pointer' }}
              >
                <ChevronLeft size={20} />
              </button>
              <h3 style={{ fontSize: '1rem', fontWeight: '700', color: '#fff', marginLeft: '8px' }}>Digital Biometric ID</h3>
            </div>

            {/* ID Card Graphic */}
            <div style={{
              background: 'linear-gradient(135deg, #1e1b4b 0%, #312e81 100%)',
              border: '1px solid rgba(255,255,255,0.1)',
              borderRadius: '24px',
              padding: '20px',
              boxShadow: '0 10px 25px rgba(0,0,0,0.3)',
              position: 'relative',
              overflow: 'hidden',
              marginBottom: '20px'
            }}>
              {/* Decorative glows */}
              <div style={{ position: 'absolute', top: '-40px', right: '-40px', width: '120px', height: '120px', borderRadius: '50%', background: 'rgba(99,102,241,0.2)', filter: 'blur(30px)' }}></div>
              
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
                <div>
                  <h4 style={{ fontSize: '1rem', fontWeight: '800', color: '#fff', letterSpacing: '0.05em' }}>Face Biometric</h4>
                  <p style={{ fontSize: '0.55rem', color: 'var(--text-secondary)' }}>SECURE DIGITAL IDENTITY</p>
                </div>
                <Award size={20} color="var(--color-success)" />
              </div>

              <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
                <div style={{
                  width: '64px',
                  height: '64px',
                  borderRadius: '16px',
                  background: '#6366f1',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#fff',
                  fontSize: '1.5rem',
                  fontWeight: '700',
                  border: '2px solid rgba(255,255,255,0.1)'
                }}>
                  {activeUser.full_name.split(' ').map(n=>n[0]).join('')}
                </div>
                <div>
                  <h3 style={{ fontSize: '1.1rem', fontWeight: '700', color: '#fff' }}>{activeUser.full_name}</h3>
                  <p style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>{activeUser.designation}</p>
                  <p style={{ fontSize: '0.7rem', color: '#818cf8', fontWeight: '600', marginTop: '2px' }}>ID: {activeUser.id}</p>
                </div>
              </div>

              <div style={{ borderTop: '1px solid rgba(255,255,255,0.1)', marginTop: '20px', paddingTop: '12px', display: 'flex', justifyContent: 'space-between', fontSize: '0.65rem' }}>
                <div>
                  <p style={{ color: 'var(--text-muted)' }}>DEPARTMENT</p>
                  <p style={{ color: '#fff', fontWeight: '600' }}>{activeUser.department}</p>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <p style={{ color: 'var(--text-muted)' }}>BIOMETRIC STATUS</p>
                  <p style={{ color: 'var(--color-success)', fontWeight: '600' }}>ENROLLED (20/20)</p>
                </div>
              </div>
            </div>

            {/* Profile fields */}
            <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '16px', padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <div>
                <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>EMAIL ADDRESS</span>
                <p style={{ fontSize: '0.8rem', color: '#fff', fontWeight: '500' }}>{activeUser.email}</p>
              </div>
              <div>
                <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>PHONE NUMBER</span>
                <p style={{ fontSize: '0.8rem', color: '#fff', fontWeight: '500' }}>{activeUser.phone_number}</p>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid rgba(255,255,255,0.06)', paddingTop: '10px' }}>
                <div>
                  <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>SHIFT SCHEDULE</span>
                  <p style={{ fontSize: '0.75rem', color: '#fff', fontWeight: '600' }}>{settingsConfig.shiftStart} AM - {parseInt(settingsConfig.shiftEnd) - 12}:00 PM</p>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>COOLDOWN TIMER</span>
                  <p style={{ fontSize: '0.75rem', color: '#fff', fontWeight: '600' }}>{settingsConfig.cooldown}s active</p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Bottom Phone Bar */}
        <div style={{
          height: '48px', 
          borderTop: '1px solid rgba(255,255,255,0.06)',
          display: 'flex', 
          justifyContent: 'space-around', 
          alignItems: 'center',
          background: 'rgba(0,0,0,0.15)',
          paddingBottom: '8px',
          zIndex: 10
        }}>
          <button 
            onClick={() => setScreen('home')}
            style={{ background: 'none', border: 'none', color: screen === 'home' || screen === 'scanner' ? 'var(--color-brand)' : 'var(--text-muted)', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px' }}
          >
            <Zap size={18} />
            <span style={{ fontSize: '0.55rem', fontWeight: '600' }}>Portal</span>
          </button>
          <button 
            onClick={() => setScreen('profile')}
            style={{ background: 'none', border: 'none', color: screen === 'profile' ? 'var(--color-brand)' : 'var(--text-muted)', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px' }}
          >
            <User size={18} />
            <span style={{ fontSize: '0.55rem', fontWeight: '600' }}>ID Card</span>
          </button>
        </div>
      </div>
    </div>
  );
}
