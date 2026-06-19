const mongoose = require('mongoose');

// Employee Profile Schema (stores biometrics)
const employeeSchema = new mongoose.Schema({
  employeeId: { type: String, required: true, unique: true, index: true },
  fullName: { type: String, required: true },
  department: { type: String, default: 'General' },
  designation: { type: String, default: 'Staff' },
  faceEmbedding: { type: [Number], required: true }, // primary 128-d embedding (back-compat)
  // Additional embeddings accumulated from face-app punches + EHRMS images, so matching
  // is robust across lighting/angle and a one-time link survives day to day.
  faceEmbeddings: { type: [[Number]], default: [] },
  profile_photo: { type: String }, // base64 representation of profile photo
  registeredAt: { type: Date, default: Date.now },

  // --- EHRMS link ---
  // When linked, attendance/break for this face is driven through the EHRMS backend
  // (the single source of truth) instead of the local AttendanceLog.
  ehrmsLinked: { type: Boolean, default: false },
  ehrmsEmail: { type: String },
  ehrmsPassword: { type: String },       // AES-256-GCM encrypted; enables silent auto re-login
  ehrmsUserId: { type: String },
  ehrmsStaffId: { type: String },
  ehrmsEmployeeId: { type: String },
  ehrmsAccessToken: { type: String },   // EHRMS access token (~30d)
  ehrmsRefreshToken: { type: String }    // EHRMS refresh token (~60d), used to self-heal access token
});

// Attendance Punch Log Schema
const attendanceLogSchema = new mongoose.Schema({
  employeeId: { type: String, required: true, index: true },
  employeeName: { type: String, required: true },
  action: { type: String, required: true, enum: ['in', 'out', 'break_in', 'break_out'] }, // check-in, check-out, break-in or break-out
  timestamp: { type: Date, default: Date.now },
  gps: {
    lat: { type: Number },
    lon: { type: Number }
  },
  status: { type: String, default: 'Present' },
  confidence: { type: Number, default: 100.0 }
});

// Admin User Schema (for dashboard login)
const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true }, // hashed password
  role: { type: String, default: 'Admin' }
});

const Employee = mongoose.model('Employee', employeeSchema);
const AttendanceLog = mongoose.model('AttendanceLog', attendanceLogSchema);
const User = mongoose.model('User', userSchema);

module.exports = { Employee, AttendanceLog, User };
