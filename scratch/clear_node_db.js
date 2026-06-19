const fs = require('fs');
const path = require('path');

const EMPLOYEES_FILE = path.join(__dirname, '..', 'backend-node', 'employees.json');
const LOGS_FILE = path.join(__dirname, '..', 'backend-node', 'logs.json');

try {
  fs.writeFileSync(EMPLOYEES_FILE, JSON.stringify([]));
  console.log('Cleared employees.json');
  fs.writeFileSync(LOGS_FILE, JSON.stringify([]));
  console.log('Cleared logs.json');
  console.log('JSON databases purged successfully!');
} catch (err) {
  console.error('Failed to purge JSON databases:', err);
}
