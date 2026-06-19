const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');

const EMPLOYEES_FILE = path.join(__dirname, 'employees.json');
const LOGS_FILE = path.join(__dirname, 'logs.json');
const USERS_FILE = path.join(__dirname, 'users.json');

// Ensure local JSON database files exist
if (!fs.existsSync(EMPLOYEES_FILE)) fs.writeFileSync(EMPLOYEES_FILE, JSON.stringify([]));
if (!fs.existsSync(LOGS_FILE)) fs.writeFileSync(LOGS_FILE, JSON.stringify([]));
if (!fs.existsSync(USERS_FILE)) fs.writeFileSync(USERS_FILE, JSON.stringify([]));

let useMongoose = false;

async function connectDB(uri) {
  try {
    // Attempt Mongoose connection with a short 3-second timeout
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 3000 });
    console.log('[INFO] MongoDB connected successfully.');
    useMongoose = true;
  } catch (err) {
    console.warn('\n[WARNING] Local MongoDB database is not running or offline.');
    console.warn('[INFO] Automatically falling back to secure local JSON file database pipeline!\n');
    useMongoose = false;
  }
}

// --- DATABASE OPERATIONS SCHEMAS LAYER ---

const db = {
  // --- Employee Ops ---
  Employee: {
    find: async () => {
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.find({});
      } else {
        return JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
      }
    },
    findOne: async (query) => {
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.findOne(query);
      } else {
        const list = JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
        if (query.employeeId) {
          return list.find(e => e.employeeId === query.employeeId) || null;
        }
        return null;
      }
    },
    create: async (data) => {
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.create(data);
      } else {
        const list = JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
        // Spread `data` first so any extra fields (e.g. EHRMS link fields ehrmsLinked,
        // ehrmsAccessToken, …) persist; then set defaults/ids.
        const newEmp = {
          ...data,
          _id: 'emp_' + Math.random().toString(36).substr(2, 9),
          employeeId: data.employeeId,
          fullName: data.fullName,
          department: data.department || 'General',
          faceEmbedding: data.faceEmbedding,
          profile_photo: data.profile_photo || null,
          registeredAt: new Date().toISOString()
        };
        list.push(newEmp);
        fs.writeFileSync(EMPLOYEES_FILE, JSON.stringify(list, null, 2));
        return newEmp;
      }
    },
    updateOne: async (query, update) => {
      // Supports { $set: {...} } and plain-object updates. Used to attach EHRMS link fields.
      const set = (update && update.$set) ? update.$set : update;
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.updateOne(query, { $set: set });
      } else {
        const list = JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
        let matched = 0;
        const updated = list.map(e => {
          const hit = (query.employeeId && e.employeeId === query.employeeId) ||
                      (query._id && e._id === query._id);
          if (hit) { matched++; return { ...e, ...set }; }
          return e;
        });
        fs.writeFileSync(EMPLOYEES_FILE, JSON.stringify(updated, null, 2));
        return { matchedCount: matched, modifiedCount: matched };
      }
    },
    countDocuments: async () => {
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.countDocuments({});
      } else {
        const list = JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
        return list.length;
      }
    },
    deleteOne: async (query) => {
      if (useMongoose) {
        const { Employee } = require('./models');
        return await Employee.deleteOne(query);
      } else {
        const list = JSON.parse(fs.readFileSync(EMPLOYEES_FILE, 'utf8'));
        let updated = list;
        if (query.employeeId) {
          updated = list.filter(e => e.employeeId !== query.employeeId);
        } else if (query._id) {
          updated = list.filter(e => e._id !== query._id);
        }
        fs.writeFileSync(EMPLOYEES_FILE, JSON.stringify(updated, null, 2));
        return { deletedCount: list.length - updated.length };
      }
    }
  },

  // --- AttendanceLog Ops ---
  AttendanceLog: {
    find: async () => {
      if (useMongoose) {
        const { AttendanceLog } = require('./models');
        return await AttendanceLog.find({}).sort({ timestamp: -1 });
      } else {
        const list = JSON.parse(fs.readFileSync(LOGS_FILE, 'utf8'));
        return [...list].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
      }
    },
    findOne: async (query) => {
      // Used to find last punch for double punch check
      const list = JSON.parse(fs.readFileSync(LOGS_FILE, 'utf8'));
      const sorted = [...list].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
      if (query.employeeId) {
        return sorted.find(l => l.employeeId === query.employeeId) || null;
      }
      return null;
    },
    create: async (data) => {
      if (useMongoose) {
        const { AttendanceLog } = require('./models');
        return await AttendanceLog.create(data);
      } else {
        const list = JSON.parse(fs.readFileSync(LOGS_FILE, 'utf8'));
        const newLog = {
          _id: 'log_' + Math.random().toString(36).substr(2, 9),
          employeeId: data.employeeId,
          employeeName: data.employeeName,
          action: data.action,
          gps: data.gps || { lat: 0.0, lon: 0.0 },
          status: data.status || 'Present',
          confidence: data.confidence || 100.0,
          timestamp: new Date().toISOString()
        };
        list.push(newLog);
        fs.writeFileSync(LOGS_FILE, JSON.stringify(list, null, 2));
        return newLog;
      }
    },
    distinct: async (field, query) => {
      // Used to find today's unique present counts
      if (useMongoose) {
        const { AttendanceLog } = require('./models');
        return await AttendanceLog.distinct(field, query);
      } else {
        const list = JSON.parse(fs.readFileSync(LOGS_FILE, 'utf8'));
        const todayStr = new Date().toISOString().split('T')[0];
        const todayLogs = list.filter(l => l.timestamp.startsWith(todayStr));
        const unique = new Set(todayLogs.map(l => l.employeeId));
        return Array.from(unique);
      }
    }
  },

  // --- User Ops ---
  User: {
    findOne: async (query) => {
      if (useMongoose) {
        const { User } = require('./models');
        return await User.findOne(query);
      } else {
        const list = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
        if (query.username) {
          return list.find(u => u.username === query.username) || null;
        }
        return null;
      }
    },
    create: async (data) => {
      if (useMongoose) {
        const { User } = require('./models');
        return await User.create(data);
      } else {
        const list = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
        const newUser = {
          _id: 'user_' + Math.random().toString(36).substr(2, 9),
          username: data.username,
          email: data.email,
          password: data.password,
          role: data.role || 'Admin'
        };
        list.push(newUser);
        fs.writeFileSync(USERS_FILE, JSON.stringify(list, null, 2));
        return newUser;
      }
    }
  }
};

module.exports = { connectDB, db };
