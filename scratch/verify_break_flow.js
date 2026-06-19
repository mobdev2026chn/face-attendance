const fs = require('fs');
const path = require('path');

const BACKEND_URL = 'http://localhost:8000/api';

async function runTests() {
  console.log('Starting automated attendance validation for complete Break and Punch Out flow...');

  const employeeId = 'test_employee_break_seq_' + Date.now();
  const mockPhoto = 'mock_test_face'; // Trigger mock embedding on backend

  // 1. Enroll Test Employee
  console.log(`\nStep 1: Enrolling employee: ${employeeId}...`);
  let enrollRes = await fetch(`${BACKEND_URL}/employees/enroll-face-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      employee_id: employeeId,
      image_base64: mockPhoto
    })
  });

  let enrollData = await enrollRes.json();
  if (enrollRes.status !== 200) {
    console.error('Enrollment failed:', enrollData);
    process.exit(1);
  }
  console.log('Enrollment successful:', enrollData);

  // 2. Perform First Scan (Auto Check-In)
  console.log('\nStep 2: Performing first scan of the day (Check-In)...');
  let firstScanRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face', 
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let firstScanData = await firstScanRes.json();
  if (firstScanRes.status !== 200) {
    console.error('First scan failed:', firstScanData);
    process.exit(1);
  }
  console.log('First scan response:', firstScanData);
  
  if (firstScanData.action !== 'Check-In') {
    console.error(`FAIL: Expected first scan action to be 'Check-In', got '${firstScanData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Auto Check-In completed successfully.');

  // 3. Perform Second Scan (Subsequent Scan showing buttons)
  console.log('\nStep 3: Performing second scan of the day (Should show buttons)...');
  let secondScanRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let secondScanData = await secondScanRes.json();
  if (secondScanRes.status !== 200) {
    console.error('Second scan failed:', secondScanData);
    process.exit(1);
  }
  console.log('Second scan response:', secondScanData);
  
  if (secondScanData.action !== 'Already-Checked-In') {
    console.error(`FAIL: Expected action to be 'Already-Checked-In', got '${secondScanData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Subsequent scan correctly returned Already-Checked-In.');

  // 4. Trigger "Take a Break" action
  console.log('\nStep 4: Simulating "Take a Break" button tap...');
  let breakInRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      action: 'break_in',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let breakInData = await breakInRes.json();
  if (breakInRes.status !== 200) {
    console.error('Break action failed:', breakInData);
    process.exit(1);
  }
  console.log('Break In action response:', breakInData);
  
  if (breakInData.action !== 'Break-In') {
    console.error(`FAIL: Expected action to be 'Break-In', got '${breakInData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Take a Break action completed successfully.');

  // Verify break log was written in the JSON database
  const logsPath = path.join(__dirname, '..', 'backend-node', 'logs.json');
  let logs = JSON.parse(fs.readFileSync(logsPath, 'utf8'));
  let breakInLog = logs.find(l => l.employeeId === employeeId && l.action === 'break_in');
  if (!breakInLog) {
    console.error('FAIL: Break in log not recorded in logs.json!');
    process.exit(1);
  }
  console.log('PASS: Break in log successfully written to database.');

  // 5. Perform Third Scan (Scanning while on Break)
  console.log('\nStep 5: Performing third scan of the day (Should show End Break only)...');
  let thirdScanRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let thirdScanData = await thirdScanRes.json();
  if (thirdScanRes.status !== 200) {
    console.error('Third scan failed:', thirdScanData);
    process.exit(1);
  }
  console.log('Third scan response:', thirdScanData);
  
  if (thirdScanData.action !== 'On-Break-Scan') {
    console.error(`FAIL: Expected action to be 'On-Break-Scan', got '${thirdScanData.action}'`);
    process.exit(1);
  }
  console.log('PASS: On-Break scan correctly returned On-Break-Scan.');

  // 6. Trigger "End Break" action
  console.log('\nStep 6: Simulating "End Break" button tap...');
  let breakOutRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      action: 'break_out',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let breakOutData = await breakOutRes.json();
  if (breakOutRes.status !== 200) {
    console.error('Break out action failed:', breakOutData);
    process.exit(1);
  }
  console.log('Break Out action response:', breakOutData);
  
  if (breakOutData.action !== 'Break-Out') {
    console.error(`FAIL: Expected action to be 'Break-Out', got '${breakOutData.action}'`);
    process.exit(1);
  }
  console.log('PASS: End Break action completed successfully.');

  // Verify break out log was written in the JSON database
  logs = JSON.parse(fs.readFileSync(logsPath, 'utf8'));
  let breakOutLog = logs.find(l => l.employeeId === employeeId && l.action === 'break_out');
  if (!breakOutLog) {
    console.error('FAIL: Break out log not recorded in logs.json!');
    process.exit(1);
  }
  console.log('PASS: Break out log successfully written to database.');

  // 7. Perform Fourth Scan (Scan after ending break -> should show buttons again)
  console.log('\nStep 7: Performing fourth scan of the day (Should show buttons again)...');
  let fourthScanRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let fourthScanData = await fourthScanRes.json();
  if (fourthScanRes.status !== 200) {
    console.error('Fourth scan failed:', fourthScanData);
    process.exit(1);
  }
  console.log('Fourth scan response:', fourthScanData);
  
  if (fourthScanData.action !== 'Already-Checked-In') {
    console.error(`FAIL: Expected action to be 'Already-Checked-In', got '${fourthScanData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Scan after break ended correctly returned Already-Checked-In.');

  // 8. Trigger "Punch Out" action
  console.log('\nStep 8: Simulating "Punch Out" button tap...');
  let checkoutRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      action: 'out',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let checkoutData = await checkoutRes.json();
  if (checkoutRes.status !== 200) {
    console.error('Punch out action failed:', checkoutData);
    process.exit(1);
  }
  console.log('Punch out action response:', checkoutData);
  
  if (checkoutData.action !== 'Check-Out') {
    console.error(`FAIL: Expected action to be 'Check-Out', got '${checkoutData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Punch Out action completed successfully.');

  // Verify checkout log was written in the JSON database
  const finalLogs = JSON.parse(fs.readFileSync(logsPath, 'utf8'));
  const checkoutLog = finalLogs.find(l => l.employeeId === employeeId && l.action === 'out');
  if (!checkoutLog) {
    console.error('FAIL: Punch out log not recorded in logs.json!');
    process.exit(1);
  }
  console.log('PASS: Punch out log successfully written to database.');

  // 9. Simulate scan after check-out (Punch-Completed)
  console.log('\nStep 9: Simulating scan after check-out...');
  let postCheckoutRes = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      image_base64: 'mock_test_face',
      gps_lat: 13.0827,
      gps_lon: 80.2707
    })
  });

  let postCheckoutData = await postCheckoutRes.json();
  if (postCheckoutRes.status !== 200) {
    console.error('Post check-out scan failed:', postCheckoutData);
    process.exit(1);
  }
  console.log('Post check-out scan response:', postCheckoutData);
  
  if (postCheckoutData.action !== 'Punch-Completed') {
    console.error(`FAIL: Expected action to be 'Punch-Completed', got '${postCheckoutData.action}'`);
    process.exit(1);
  }
  console.log('PASS: Post check-out scan correctly returned Punch-Completed.');

  console.log('\nALL BREAK AND PUNCH-OUT SEQUENCE LIFECYCLE TESTS PASSED SUCCESSFULLY!');
}

runTests();
