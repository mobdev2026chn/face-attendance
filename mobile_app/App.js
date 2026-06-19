import React, { useState, useEffect, useRef } from 'react';
import { 
  StyleSheet, Text, View, TextInput, TouchableOpacity, 
  ActivityIndicator, Image, Modal, Alert, SafeAreaView, StatusBar,
  Dimensions, Animated, FlatList, ScrollView
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Location from 'expo-location';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

// Calculate optimal 16:9 aspect ratio camera dimensions to cover the viewport without stretching
const SCREEN_RATIO = SCREEN_HEIGHT / SCREEN_WIDTH;
const CAMERA_ASPECT_RATIO = 16 / 9;
let CALC_CAMERA_WIDTH = SCREEN_WIDTH;
let CALC_CAMERA_HEIGHT = SCREEN_HEIGHT;
let CALC_CAMERA_LEFT = 0;

if (SCREEN_RATIO > CAMERA_ASPECT_RATIO) {
  CALC_CAMERA_WIDTH = SCREEN_HEIGHT * (9 / 16);
  CALC_CAMERA_LEFT = (SCREEN_WIDTH - CALC_CAMERA_WIDTH) / 2;
} else {
  CALC_CAMERA_HEIGHT = SCREEN_WIDTH * (16 / 9);
}

// Configuration: Replace with your backend computer's LAN IP address when running Expo Go on your phone!
const BACKEND_URL = "http://172.28.43.234:8000/api";

export default function App() {
  const [screen, setScreen] = useState('splash'); // splash, login, home, scanner, passcode, admin, dashboard
  const [loginEmail, setLoginEmail] = useState('temp@mail');
  const [loginPassword, setLoginPassword] = useState('123');
  const [showLoginPassword, setShowLoginPassword] = useState(false);
  const [activeDot, setActiveDot] = useState(0);
  const [recognizedEmployee, setRecognizedEmployee] = useState(null);

  // Multi-Admin Database State
  const [registeredAdmins, setRegisteredAdmins] = useState([
    { name: "System Admin", email: "temp@mail", password: "123" }
  ]);
  const [currentUser, setCurrentUser] = useState({ name: "System Admin", email: "temp@mail" });

  // Sign-Up Input Form States
  const [signUpName, setSignUpName] = useState('');
  const [signUpEmail, setSignUpEmail] = useState('');
  const [signUpPassword, setSignUpPassword] = useState('');
  const [signUpConfirmPassword, setSignUpConfirmPassword] = useState('');
  const [showSignUpPassword, setShowSignUpPassword] = useState(false);

  const [showSidebar, setShowSidebar] = useState(false);
  const [hasPermission, setHasPermission] = useState(null);
  
  // App States
  const [empId, setEmpId] = useState('');
  const [isEnrollNameEntered, setIsEnrollNameEntered] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [scanResult, setScanResult] = useState(null);
  const [showResultModal, setShowResultModal] = useState(false);
  const [cameraLocked, setCameraLocked] = useState(false);
  const [scanSuccessful, setScanSuccessful] = useState(false);
  const [capturedSelfie, setCapturedSelfie] = useState(null);
  const [locationStr, setLocationStr] = useState("Detecting location...");
  const [gpsCoords, setGpsCoords] = useState({ latitude: 13.0827, longitude: 80.2707 });
  
  // Scanner & Overlay Settings
  const [scannerAction, setScannerAction] = useState('in'); // 'in' (Punch In) or 'out' (Punch Out) or 'register'
  const [guidanceText, setGuidanceText] = useState('Align Face Inside Guide');
  const [ovalColor, setOvalColor] = useState('#f5a623'); // Golden Orange per mockup
  
  // Passcode Settings
  const [passcode, setPasscode] = useState('');
  
  // Admin & Registry Settings
  const [adminTab, setAdminTab] = useState('enroll'); // 'enroll' or 'registry'
  const [enrolledUsers, setEnrolledUsers] = useState([]);
  const [attendanceRecords, setAttendanceRecords] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [dashboardStats, setDashboardStats] = useState({ total_enrolled: 0, present_today: 0 });
  const [shiftStatusText, setShiftStatusText] = useState('On Time • Day Shift');

  const cameraRef = useRef(null);
  const glowAnim = useRef(new Animated.Value(0.6)).current;

  const [permission, requestPermission] = useCameraPermissions();

  useEffect(() => {
    if (permission) {
      setHasPermission(permission.granted);
    }
  }, [permission]);

  const handleRequestPermission = async () => {
    const res = await requestPermission();
    setHasPermission(res.granted);
  };

  const updateLocation = async () => {
    setLocationStr("Detecting location...");
    try {
      let { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setLocationStr("Location permission denied");
        return;
      }

      let location = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.Balanced,
      });
      
      const { latitude, longitude } = location.coords;
      setGpsCoords({ latitude, longitude });

      let geocode = await Location.reverseGeocodeAsync({ latitude, longitude });
      if (geocode && geocode.length > 0) {
        const addr = geocode[0];
        const parts = [];
        if (addr.name && addr.name !== addr.street) parts.push(addr.name);
        if (addr.street) parts.push(addr.street);
        if (addr.district) parts.push(addr.district);
        if (addr.city) parts.push(addr.city);
        if (addr.region) parts.push(addr.region);
        if (addr.country) parts.push(addr.country);

        const formatted = parts.join(", ");
        setLocationStr(formatted || `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`);
      } else {
        setLocationStr(`${latitude.toFixed(4)}, ${longitude.toFixed(4)}`);
      }
    } catch (error) {
      console.warn("Location error:", error);
      setLocationStr("Failed to resolve geocode address");
    }
  };

  useEffect(() => {
    updateLocation();
    
    // Cycle the splash screen loading dots animation
    const dotInterval = setInterval(() => {
      setActiveDot(prev => (prev === 0 ? 1 : 0));
    }, 500);

    // Auto transition to login screen after 2.5s
    const timer = setTimeout(() => {
      setScreen('login');
    }, 2500);

    return () => {
      clearInterval(dotInterval);
      clearTimeout(timer);
    };
  }, []);

  // Soft glowing animation for the Electric Blue Oval
  useEffect(() => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(glowAnim, {
          toValue: 1.0,
          duration: 1500,
          useNativeDriver: true
        }),
        Animated.timing(glowAnim, {
          toValue: 0.6,
          duration: 1500,
          useNativeDriver: true
        })
      ])
    ).start();
  }, [glowAnim]);
  // Automatic Zero-Touch face punch scanner capture loop!
  useEffect(() => {
    let interval = null;
    if (screen === 'scanner' && !cameraLocked && !scanSuccessful) {
      interval = setInterval(() => {
        if (!isLoading && !cameraLocked && !scanSuccessful) {
          handleScanAttendance();
        }
      }, 2500); // Scans automatically every 2.5 seconds until success or exit!
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [screen, cameraLocked, scanSuccessful, isLoading]);

  // Fetch Database Data for registries and stats dynamically
  const fetchDashboardData = async () => {
    try {
      const statsRes = await fetch(`${BACKEND_URL}/employees/metrics`);
      if (statsRes.ok) {
        const stats = await statsRes.json();
        setDashboardStats(stats);
      }
      
      const recordsRes = await fetch(`${BACKEND_URL}/attendance/records`);
      if (recordsRes.ok) {
        const records = await recordsRes.json();
        setAttendanceRecords(records);
      }
    } catch (e) {
      console.warn("Could not load dashboard records:", e);
    }
  };

  const fetchRegistryData = async () => {
    try {
      // In NodeJS Express system, get_enrolled_users_metrics maps user lists
      const recordsRes = await fetch(`${BACKEND_URL}/attendance/records`); 
      const usersSet = new Set();
      const formattedUsers = [];
      if (recordsRes.ok) {
        const records = await recordsRes.json();
        records.forEach(r => {
          if (!usersSet.has(r.employeeId)) {
            usersSet.add(r.employeeId);
            formattedUsers.push({
              id: r._id || r.employeeId,
              name: r.employeeName,
              date: new Date(r.timestamp).toLocaleDateString(),
              punches: records.filter(log => log.employeeId === r.employeeId).length
            });
          }
        });
        setEnrolledUsers(formattedUsers);
      }
    } catch (e) {
      console.warn("Could not load users registry:", e);
    }
  };

  if (hasPermission === null) {
    return (
      <View style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color="#00D2FF" />
        <Text style={styles.loadingText}>Initializing camera...</Text>
      </View>
    );
  }
  if (hasPermission === false) {
    return (
      <View style={[styles.container, styles.center]}>
        <Text style={styles.errorText}>Camera Access Required</Text>
        <Text style={styles.errorSubtext}>We need secure front-facing camera access to verify your biometric face attendance.</Text>
        <TouchableOpacity 
          style={[styles.btn, styles.btnPrimary, { width: '80%', marginTop: 20 }]}
          onPress={handleRequestPermission}
        >
          <Text style={styles.btnText}>Grant Camera Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // --- CONTROLLER 0: IMMERSIVE SIGN-IN AUTHENTICATION ---
  const handleLogin = () => {
    if (!loginEmail.trim() || !loginPassword) {
      Alert.alert("Input Required", "Please enter both your email and password.");
      return;
    }

    const email = loginEmail.trim().toLowerCase();
    const password = loginPassword;

    // Search inside dynamic local multi-admin account registry state
    const matchedAdmin = registeredAdmins.find(admin => admin.email.toLowerCase() === email && admin.password === password);

    if (matchedAdmin) {
      setCurrentUser({
        name: matchedAdmin.name,
        email: matchedAdmin.email
      });
      setLoginEmail('');
      setLoginPassword('');
      openPunchScanner('in');
      return;
    }

    Alert.alert("Invalid Credentials", "Incorrect email or password. Only registered admin accounts can log in.");
  };

  // --- CONTROLLER 0.5: REGISTER A NEW ADMIN ACCOUNT ---
  const handleSignUp = () => {
    if (!signUpName.trim() || !signUpEmail.trim() || !signUpPassword || !signUpConfirmPassword) {
      Alert.alert("Input Required", "Please fill in all the input fields.");
      return;
    }

    const email = signUpEmail.trim().toLowerCase();
    const name = signUpName.trim();

    // Verify correct email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      Alert.alert("Invalid Format", "Please enter a valid email address.");
      return;
    }

    // Verify passwords match
    if (signUpPassword !== signUpConfirmPassword) {
      Alert.alert("Error", "Passwords do not match. Please verify.");
      return;
    }

    // Verify duplicate emails
    const emailExists = registeredAdmins.some(admin => admin.email.toLowerCase() === email);
    if (emailExists) {
      Alert.alert("Error", `Email "${email}" is already registered. Please log in.`);
      return;
    }

    // Register account
    const newAdmin = {
      name,
      email,
      password: signUpPassword
    };

    setRegisteredAdmins([...registeredAdmins, newAdmin]);
    Alert.alert(
      "Success", 
      `Account created successfully for "${name}"!\nYou can now log in with your credentials.`,
      [{ text: "OK", onPress: () => {
        setSignUpName('');
        setSignUpEmail('');
        setSignUpPassword('');
        setSignUpConfirmPassword('');
        setScreen('login');
      }}]
    );
  };

  // --- CONTROLLER 1: BIOMETRIC FRONT-FACE ENROLLMENT ---
  const handleEnrollFace = async () => {
    if (!empId.trim()) {
      Alert.alert("Input Required", "Please type the Username/ID first to unlock guided enrollment.");
      return;
    }

    if (!cameraRef.current) return;
    setIsLoading(true);

    try {
      const options = { quality: 0.5, base64: true, skipProcessing: true };
      const photo = await cameraRef.current.takePictureAsync(options);

      setCameraLocked(true);
      setScanSuccessful(true);
      setOvalColor('#10b981'); // Emerald Green success oval
      setGuidanceText('Face Registered! Click Done.');

      const response = await fetch(`${BACKEND_URL}/employees/enroll-face-mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employee_id: empId.trim(),
          image_base64: photo.base64
        })
      });

      const data = await response.json();

      if (response.ok) {
        Alert.alert(
          "Success", 
          `Face registered successfully for "${empId.trim()}"!\nBiometrics encrypted & saved.`,
          [{ text: "OK", onPress: () => { 
            resetScannerState();
            setScreen('admin');
            setEmpId('');
            setIsEnrollNameEntered(false);
            fetchRegistryData();
          } }]
        );
      } else {
        Alert.alert("Enrollment Failed", data.detail || "Error connecting to server.");
        resetScannerState();
      }
    } catch (error) {
      Alert.alert("Connection Error", "Could not connect to Express server. Please check your IP address.");
      resetScannerState();
    } finally {
      setIsLoading(false);
    }
  };

  // --- CONTROLLER 2: SCAN FRONT-FACE PUNCH IN/OUT ---
  const handleScanAttendance = async () => {
    if (!cameraRef.current || cameraLocked) return;
    setIsLoading(true);

    try {
      const options = { quality: 0.5, base64: true, skipProcessing: true };
      const photo = await cameraRef.current.takePictureAsync(options);

      const response = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image_base64: photo.base64,
          action: 'auto',
          gps_lat: gpsCoords.latitude,
          gps_lon: gpsCoords.longitude
        })
      });

      const data = await response.json();

      if (response.ok) {
        setCameraLocked(true);
        setScanSuccessful(true);
        setOvalColor('#10b981'); // Green Success Oval
        
        let guidance = "Verification Passed!";
        if (data.action === "Check-In") {
          guidance = data.status === "Punched Late" ? "PUNCHED LATE" : "PUNCH IN SUCCESSFUL";
        } else if (data.action === "Already-Checked-In" || data.action === "On-Break-Scan") {
          guidance = "Verification Passed!";
        } else if (data.action === "Check-Out") {
          guidance = data.status === "Punched Out Early" ? "PUNCHED OUT EARLY" : "PUNCH OUT SUCCESSFUL";
        } else if (data.action === "Break" || data.action === "Break-In") {
          guidance = "BREAK MARKED SUCCESSFUL";
        } else if (data.action === "Break-Out") {
          guidance = "BREAK ENDED SUCCESSFUL";
        } else {
          guidance = "PUNCH COMPLETED FOR TODAY";
        }
        
        setGuidanceText(guidance);
        setScanResult(data);
        setCapturedSelfie(photo.base64);
        setRecognizedEmployee(data);
        
        // Wait 5 seconds so the employee can view details, then reset automatically to scan the next person
        setTimeout(() => {
          setRecognizedEmployee(null);
          resetScannerState();
        }, 5000);
      } else {
        const errMsg = data.detail || "";
        setOvalColor('#ef4444'); // Red Warning Oval
        
        if (errMsg.includes("off-center horizontally")) {
          setGuidanceText("Align Center (Move Left/Right)");
        } else if (errMsg.includes("off-center vertically")) {
          setGuidanceText("Align Center (Move Up/Down)");
        } else if (errMsg.includes("too far")) {
          setGuidanceText("Come Front Little");
        } else if (errMsg.includes("too close")) {
          setGuidanceText("Go Back Little");
        } else if (errMsg.includes("Side angles")) {
          setGuidanceText("Look Straight at Camera");
        } else if (errMsg.includes("Multiple faces")) {
          setGuidanceText("Ensure Only 1 Face Visible");
        } else if (errMsg.includes("Spoof Alert") || errMsg.includes("fake")) {
          setGuidanceText("Spoof Alert! Fake Face Detected");
        } else {
          setGuidanceText(errMsg || "Face Not Recognized. Retrying...");
        }

        // Keep scanner unlocked so automatic loop continues scanning
        setCameraLocked(false);
        setScanSuccessful(false);
      }
    } catch (error) {
      setGuidanceText("Connection Error. Retrying...");
      setCameraLocked(false);
      setScanSuccessful(false);
    } finally {
      setIsLoading(false);
    }
  };

  // --- CONTROLLER 2.2: SUBSEQUENT SCAN BUTTON HANDLERS ---
  const handleTakeBreak = async () => {
    if (!recognizedEmployee) return;
    setIsLoading(true);
    try {
      const response = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image_base64: capturedSelfie || 'mock_test_face',
          action: 'break_in',
          gps_lat: gpsCoords.latitude,
          gps_lon: gpsCoords.longitude
        })
      });
      const data = await response.json();
      if (response.ok) {
        setGuidanceText("BREAK MARKED SUCCESSFUL");
        setRecognizedEmployee(data);
        setTimeout(() => {
          setRecognizedEmployee(null);
          resetScannerState();
        }, 5000);
      } else {
        Alert.alert("Error", data.detail || "Failed to mark break.");
      }
    } catch (error) {
      Alert.alert("Error", "Connection error. Failed to mark break.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleEndBreak = async () => {
    if (!recognizedEmployee) return;
    setIsLoading(true);
    try {
      const response = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image_base64: capturedSelfie || 'mock_test_face',
          action: 'break_out',
          gps_lat: gpsCoords.latitude,
          gps_lon: gpsCoords.longitude
        })
      });
      const data = await response.json();
      if (response.ok) {
        setGuidanceText("BREAK ENDED SUCCESSFUL");
        setRecognizedEmployee(data);
        setTimeout(() => {
          setRecognizedEmployee(null);
          resetScannerState();
        }, 5000);
      } else {
        Alert.alert("Error", data.detail || "Failed to end break.");
      }
    } catch (error) {
      Alert.alert("Error", "Connection error. Failed to end break.");
    } finally {
      setIsLoading(false);
    }
  };

  const handlePunchOut = async () => {
    if (!recognizedEmployee) return;
    setIsLoading(true);
    try {
      const response = await fetch(`${BACKEND_URL}/attendance/scan-mobile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image_base64: capturedSelfie || 'mock_test_face',
          action: 'out',
          gps_lat: gpsCoords.latitude,
          gps_lon: gpsCoords.longitude
        })
      });
      const data = await response.json();
      if (response.ok) {
        setGuidanceText("PUNCH OUT SUCCESSFUL");
        setRecognizedEmployee(data);
        setTimeout(() => {
          setRecognizedEmployee(null);
          resetScannerState();
        }, 5000);
      } else {
        Alert.alert("Error", data.detail || "Failed to punch out.");
      }
    } catch (error) {
      Alert.alert("Error", "Connection error. Failed to punch out.");
    } finally {
      setIsLoading(false);
    }
  };

  const handleAdminVerify = () => {
    if (passcode === '1234') {
      setPasscode('');
      setScreen('admin');
      setAdminTab('enroll');
      fetchRegistryData();
    } else {
      Alert.alert("Access Denied", "Incorrect Admin Passkey!");
      setPasscode('');
    }
  };

  const deleteEnrolledUser = async (userId, name) => {
    Alert.alert(
      "Confirm Deletion",
      `Are you sure you want to permanently delete "${name}"?\nThis action cannot be undone!`,
      [
        { text: "Cancel", style: "cancel" },
        { text: "Delete User", style: "destructive", onPress: async () => {
          try {
            const response = await fetch(`${BACKEND_URL}/employees/delete`, {
              method: 'DELETE',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ employeeId: name, id: userId })
            });
            const data = await response.json();
            if (response.ok) {
              Alert.alert("Success", `User profile for "${name}" has been deleted.`);
              setEnrolledUsers(enrolledUsers.filter(u => u.name !== name));
              // Also refresh dashboard numbers
              fetchDashboardData();
            } else {
              Alert.alert("Error", data.detail || "Could not delete user.");
            }
          } catch (e) {
            Alert.alert("Error", "Could not connect to database server.");
          }
        }}
      ]
    );
  };

  const resetScannerState = () => {
    setCameraLocked(false);
    setScanSuccessful(false);
    setOvalColor('#f5a623');
    setGuidanceText('Align Face Inside Guide');
  };

  const openPunchScanner = (action) => {
    setScannerAction(action);
    setScreen('scanner');
    resetScannerState();
  };

  const openDashboard = () => {
    setScreen('dashboard');
    fetchDashboardData();
  };

  const handleSubmitPunch = () => {
    const now = new Date();
    const hours = now.getHours();
    const minutes = now.getMinutes();

    let alertTitle = "Punch Successful";
    let alertMsg = "Your attendance has been recorded successfully.";
    let shiftText = "On Time • Day Shift";

    const isCheckIn = scannerAction === 'in' || scanResult?.action === 'Check-In';
    const isCheckOut = scannerAction === 'out' || scanResult?.action === 'Check-Out';

    if (isCheckIn) {
      if (hours > 10 || (hours === 10 && minutes > 10)) {
        alertTitle = "PUNCHED LATE";
        alertMsg = "You have checked in after 10:10 AM.";
        shiftText = "Punched Late • Day Shift";
      }
    } else if (isCheckOut) {
      if (hours < 19) {
        alertTitle = "PUNCHED OUT EARLY";
        alertMsg = "You have checked out before 7:00 PM.";
        shiftText = "Punched Out Early • Day Shift";
      }
    }

    setShiftStatusText(shiftText);

    Alert.alert(
      alertTitle,
      alertMsg,
      [{ text: "OK", onPress: () => setShowResultModal(true) }]
    );
  };

  const filteredRecords = attendanceRecords.filter(r => 
    r.employeeName.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const isDarkScreen = screen === 'splash' || screen === 'scanner' || screen === 'passcode' || screen === 'login' || (screen === 'admin' && adminTab === 'enroll' && isEnrollNameEntered);

  return (
    <SafeAreaView style={[
      styles.parentSafeArea, 
      { backgroundColor: isDarkScreen ? (screen === 'splash' ? '#f5a623' : '#0E0E10') : '#F9FAFB' }
    ]}>
      <StatusBar barStyle={isDarkScreen ? "light-content" : "dark-content"} />
      
      {/* HEADER */}
      {screen !== 'splash' && screen !== 'scanner' && screen !== 'passcode' && screen !== 'review' && screen !== 'logout' && screen !== 'login' && !(screen === 'admin' && adminTab === 'enroll' && isEnrollNameEntered) && (
        <View style={styles.headerContainer}>
          {screen === 'home' ? (
            <TouchableOpacity 
              style={styles.hamburgerBtn}
              onPress={() => setShowSidebar(true)}
            >
              <Text style={styles.hamburgerText}>☰</Text>
            </TouchableOpacity>
          ) : (
            <>
              <View style={{ width: 36 }} />
              <View style={styles.headerTextWrapper}>
                <Text style={[styles.headerLogo, { color: isDarkScreen ? '#fff' : '#1E293B' }]}>Face Biometric</Text>
                <Text style={[styles.headerSubtitle, { color: '#f5a623' }]}>Biometric Terminal</Text>
              </View>
              <View style={{ width: 36 }} />
            </>
          )}
        </View>
      )}

      {/* --- SPLASH LOADING SCREEN (Mockup Match) --- */}
      {screen === 'splash' && (
        <View style={styles.splashContainer}>
          {/* Animated/Styled circular Symbol logo */}
          <View style={styles.splashHalo}>
            <View style={styles.splashCircle}>
              <Text style={styles.splashLetterE}>e</Text>
              <View style={styles.splashDot} />
            </View>
          </View>

          {/* White corporate branding text */}
          <Text style={styles.splashBrandText}>ektaHr</Text>

          {/* Loading Indicator dots */}
          <View style={styles.splashDotsRow}>
            <View style={[styles.splashDotIndicator, activeDot === 0 ? styles.splashDotActive : styles.splashDotInactive]} />
            <View style={[styles.splashDotIndicator, activeDot === 1 ? styles.splashDotActive : styles.splashDotInactive]} />
          </View>
        </View>
      )}

      {/* --- SIGN IN SCREEN (Mockup Match) --- */}
      {screen === 'login' && (
        <View style={styles.loginFullScreenContainer}>
          {/* Top Dark Header */}
          <View style={styles.loginTopDarkHalf}>
            <Image source={require('./logo.png')} style={styles.loginLogoImage} />
          </View>

          {/* Bottom Gold Area */}
          <View style={styles.loginBottomGoldHalf}>
            {/* Immersive Floating Login Card */}
            <View style={styles.loginCenterCard}>
              {/* Email Entry Field */}
              <View style={styles.loginInputWrapper}>
                <TextInput 
                  style={styles.loginTextInputField}
                  placeholder="Email"
                  placeholderTextColor="#64748b"
                  value={loginEmail}
                  onChangeText={setLoginEmail}
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoCorrect={false}
                />
              </View>

              {/* Password Entry Field */}
              <View style={styles.loginInputWrapper}>
                <TextInput 
                  style={styles.loginTextInputField}
                  placeholder="Password"
                  placeholderTextColor="#64748b"
                  value={loginPassword}
                  onChangeText={setLoginPassword}
                  secureTextEntry={!showLoginPassword}
                  autoCapitalize="none"
                  autoCorrect={false}
                />
                <TouchableOpacity 
                  style={styles.loginPasswordEyeToggle}
                  onPress={() => setShowLoginPassword(!showLoginPassword)}
                >
                  <Text style={styles.loginPasswordEyeText}>{showLoginPassword ? "Hide" : "Show"}</Text>
                </TouchableOpacity>
              </View>

              {/* Forgot Password Link */}
              <TouchableOpacity 
                style={{ alignSelf: 'flex-end', marginBottom: 24, marginTop: -4 }}
                onPress={() => Alert.alert("Forgot Password", "Password recovery instructions have been sent to your email.")}
              >
                <Text style={styles.loginForgotPasswordText}>Forgot Password?</Text>
              </TouchableOpacity>

              {/* Login Submit Trigger */}
              <TouchableOpacity 
                style={styles.loginBtn}
                onPress={handleLogin}
              >
                <Text style={styles.loginBtnText}>Login</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      )}

      {/* Home screen removed per user request (camera scanner is now the main view) */}

      {/* --- PASSCODE SCREEN (Image 2 Match) --- */}
      {screen === 'passcode' && (
        <View style={styles.passcodeContainer}>
          {/* Header Bar */}
          <View style={styles.passcodeHeader}>
            <TouchableOpacity 
              style={styles.circularBackBtn} 
              onPress={() => { setScreen('scanner'); setPasscode(''); }}
            >
              <Text style={styles.backBtnText}>←</Text>
            </TouchableOpacity>
            <Text style={styles.passcodeHeaderTitle}>Mark Attendance</Text>
            <View style={{ width: 40 }} />
          </View>

          {/* Glassmorphic PIN Box */}
          <View style={styles.pinCard}>
            <Text style={styles.pinTitle}>Enter PIN</Text>
            <Text style={styles.pinSubtitle}>Verify your identity to proceed</Text>

            {/* Circular PIN dots */}
            <View style={styles.pinDotsRow}>
              {[0, 1, 2, 3].map((idx) => (
                <View 
                  key={idx} 
                  style={[
                    styles.pinDot, 
                    idx < passcode.length ? styles.pinDotFilled : styles.pinDotEmpty
                  ]} 
                />
              ))}
            </View>
          </View>

          {/* Numeric Translucent Keypad */}
          <View style={styles.keypadGrid}>
            {[
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['CLEAR', '0', 'BACK']
            ].map((row, rIdx) => (
              <View key={rIdx} style={styles.keypadRow}>
                {row.map((btn) => (
                  <TouchableOpacity 
                    key={btn} 
                    style={[
                      styles.keypadBtn, 
                      (btn === 'CLEAR' || btn === 'BACK') && styles.keypadBtnSpecial
                    ]}
                    onPress={() => {
                      if (btn === 'CLEAR') {
                        setPasscode('');
                      } else if (btn === 'BACK') {
                        setPasscode(passcode.slice(0, -1));
                      } else {
                        if (passcode.length < 4) {
                          setPasscode(passcode + btn);
                        }
                      }
                    }}
                  >
                    {btn === 'BACK' ? (
                      <Text style={styles.keypadBtnText}>⌫</Text>
                    ) : (
                      <Text style={btn === 'CLEAR' ? styles.keypadSpecialText : styles.keypadBtnText}>
                        {btn}
                      </Text>
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            ))}
          </View>

          {/* Bottom Action Unlock Button */}
          <TouchableOpacity 
            style={[styles.btn, styles.btnOrangePrimary, { marginBottom: 20 }]}
            onPress={handleAdminVerify}
          >
            <Text style={styles.btnTextWhite}>Unlock</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* --- ADMIN SCREEN --- */}
      {screen === 'admin' && (
        <View style={
          (adminTab === 'enroll' && isEnrollNameEntered) 
            ? styles.scannerFullScreenContainer 
            : [styles.flexContainer, { paddingHorizontal: 0 }]
        }>
          {/* Admin Tabs */}
          {!(adminTab === 'enroll' && isEnrollNameEntered) && (
            <View style={{ paddingHorizontal: 20 }}>
              <View style={styles.tabRow}>
                <TouchableOpacity 
                  style={[styles.tabButton, adminTab === 'enroll' && styles.tabButtonActive]}
                  onPress={() => { setAdminTab('enroll'); setEmpId(''); setIsEnrollNameEntered(false); }}
                >
                  <Text style={[styles.tabButtonText, adminTab === 'enroll' && styles.tabButtonTextActive]}>Enroll User</Text>
                </TouchableOpacity>
                
                <TouchableOpacity 
                  style={[styles.tabButton, adminTab === 'registry' && styles.tabButtonActive]}
                  onPress={() => { setAdminTab('registry'); fetchRegistryData(); }}
                >
                  <Text style={[styles.tabButtonText, adminTab === 'registry' && styles.tabButtonTextActive]}>Registry</Text>
                </TouchableOpacity>
              </View>
            </View>
          )}

          {/* TAB 1: ENROLL USER */}
          {adminTab === 'enroll' && (
            <View style={[
              styles.enrollFullScreenContainer,
              isEnrollNameEntered && { backgroundColor: '#000' }
            ]}>
              {!isEnrollNameEntered ? (
                <View style={styles.cameraLockOverlay}>
                  {/* Name Input Card */}
                  <View style={[styles.enrollInputCard, { marginTop: 0, padding: 24, width: '90%', borderRadius: 24, backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2e8f0' }]}>
                    <Text style={[styles.enrollLabelText, { color: '#64748b', fontSize: 11, marginBottom: 8 }]}>ENTER EMPLOYEE USERNAME/ID</Text>
                    <TextInput 
                      style={[styles.enrollTextInput, { backgroundColor: '#f8fafc', color: '#1E293B', borderColor: '#cbd5e1', padding: 14 }]}
                      placeholder="e.g. Elena Smith"
                      placeholderTextColor="#94a3b8"
                      value={empId}
                      onChangeText={setEmpId}
                      autoCapitalize="words"
                    />

                    <TouchableOpacity 
                      style={[
                        styles.btn, 
                        styles.btnOrangePrimary, 
                        { marginTop: 20, paddingVertical: 16 },
                        !empId.trim() && styles.btnDisabled
                      ]}
                      disabled={!empId.trim()}
                      onPress={() => setIsEnrollNameEntered(true)}
                    >
                      <Text style={styles.btnTextWhite}>Proceed to Scan</Text>
                    </TouchableOpacity>
                  </View>

                  <Text style={[styles.lockText, { color: '#1E293B', marginTop: 30 }]}>Registration Lock</Text>
                  <Text style={[styles.lockSubtext, { color: '#64748b' }]}>Please enter the employee's name above to proceed to guided biometric scan.</Text>

                  <TouchableOpacity 
                    style={[styles.btn, styles.btnCancel, { width: '90%', marginTop: 30 }]}
                    onPress={() => setScreen('scanner')}
                  >
                    <Text style={styles.btnTextSecondary}>Exit Admin</Text>
                  </TouchableOpacity>
                </View>
              ) : (
                <View style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
                  <CameraView 
                    ref={cameraRef}
                    facing="front"
                    style={styles.unstretchedCamera}
                  />
                  <View style={[
                    styles.enrollCameraOverlay,
                    { paddingTop: (StatusBar.currentHeight || 24) + 15 }
                  ]}>
                    <View style={styles.enrollInputCard}>
                      <Text style={styles.enrollLabelText}>ENROLLING BIOMETRIC PROFILE</Text>
                      <Text style={{ color: '#f5a623', fontSize: 16, fontWeight: '800', marginTop: 4 }}>ID: {empId.trim()}</Text>
                    </View>

                    {/* Shivering Guide Oval (Exactly same as Punch Scanner) */}
                    <Animated.View style={[
                      styles.premiumFaceGuide, 
                      { borderColor: ovalColor, opacity: glowAnim, marginVertical: 10 }
                    ]}>
                      <View style={[styles.bracketTL, { borderColor: ovalColor }]} />
                      <View style={[styles.bracketTR, { borderColor: ovalColor }]} />
                      <View style={[styles.bracketBL, { borderColor: ovalColor }]} />
                      <View style={[styles.bracketBR, { borderColor: ovalColor }]} />

                      <View style={styles.contourFaceOutline}>
                        <View style={styles.contourEyebrows} />
                        <View style={styles.contourEyesRow}>
                          <View style={styles.contourEye} />
                          <View style={styles.contourEye} />
                        </View>
                        <View style={styles.contourNose} />
                        <View style={styles.contourLips} />
                      </View>

                      {scanSuccessful && (
                        <View style={styles.successTickBadgeCircular}>
                          <Text style={styles.successTickTextSymbol}>✓</Text>
                        </View>
                      )}
                    </Animated.View>

                    {/* Guidance text overlay */}
                    <Text style={[styles.scannerGuidanceText, { color: ovalColor, marginBottom: 10 }]}>
                      {guidanceText}
                    </Text>

                    {/* Floating Action Buttons overlayed inside Camera */}
                    <View style={styles.enrollFloatingActions}>
                      <TouchableOpacity 
                        style={[
                          styles.btn, 
                          styles.btnElectricGreen, 
                          (!empId.trim() || isLoading) && styles.btnDisabled
                        ]}
                        onPress={handleEnrollFace}
                        disabled={!empId.trim() || isLoading}
                      >
                        {isLoading ? (
                          <ActivityIndicator color="#fff" />
                        ) : (
                          <Text style={styles.btnTextWhite}>Capture & Save Face</Text>
                        )}
                      </TouchableOpacity>

                      <TouchableOpacity 
                        style={[styles.btn, styles.btnOrangePrimary]}
                        onPress={() => setIsEnrollNameEntered(false)}
                        disabled={isLoading}
                      >
                        <Text style={styles.btnTextWhite}>← Change Name</Text>
                      </TouchableOpacity>
                    </View>
                  </View>
                </View>
              )}
            </View>
          )}

          {/* TAB 2: USER REGISTRY */}
          {adminTab === 'registry' && (
            <View style={{ flex: 1, paddingHorizontal: 20 }}>
              <Text style={[styles.label, { marginVertical: 8 }]}>ENROLLED BIOMETRIC PROFILES</Text>
              
              <FlatList 
                data={enrolledUsers}
                keyExtractor={(item) => item.id}
                renderItem={({ item }) => (
                  <View style={styles.registryRow}>
                    <View>
                      <Text style={styles.rowTitle}>{item.name}</Text>
                      <Text style={styles.rowSubtitle}>Enrolled: {item.date} | Punches: {item.punches}</Text>
                    </View>
                    <TouchableOpacity 
                      style={styles.deleteButton}
                      onPress={() => deleteEnrolledUser(item.id, item.name)}
                    >
                      <Text style={styles.deleteButtonText}>Remove</Text>
                    </TouchableOpacity>
                  </View>
                )}
                ListEmptyComponent={
                  <View style={[styles.center, { padding: 40 }]}>
                    <Text style={{ color: '#64748b' }}>No users registered in database.</Text>
                  </View>
                }
              />

              <TouchableOpacity 
                style={[styles.btn, styles.btnCancel, { marginTop: 10 }]}
                onPress={() => setScreen('scanner')}
              >
                <Text style={styles.btnTextSecondary}>Exit Admin</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
      )}

      {/* --- DASHBOARD SCREEN --- */}
      {screen === 'dashboard' && (
        <View style={[styles.flexContainer, { paddingHorizontal: 20 }]}>
          <ScrollView horizontal={false} style={{ flex: 1 }}>
            {/* Stats row */}
            <View style={styles.statsRow}>
              <View style={styles.statsCard}>
                <Text style={styles.statsLabel}>Total Enrolled</Text>
                <Text style={styles.statsValue}>{dashboardStats.total_enrolled}</Text>
              </View>
              <View style={styles.statsCard}>
                <Text style={styles.statsLabel}>Present Today</Text>
                <Text style={styles.statsValue}>{dashboardStats.present_today}</Text>
              </View>
            </View>

            {/* Filter */}
            <View style={styles.formPanel}>
              <Text style={styles.label}>SEARCH ATTENDANCE PUNCHES</Text>
              <TextInput 
                style={styles.input}
                placeholder="Search username..."
                placeholderTextColor="#64748b"
                value={searchQuery}
                onChangeText={setSearchQuery}
              />
            </View>

            {/* Logs List */}
            <Text style={styles.label}>DAILY ATTENDANCE LOGS</Text>
            {(() => {
              const groups = {};
              filteredRecords.forEach(r => {
                const dateStr = new Date(r.timestamp).toLocaleDateString();
                const key = `${r.employeeId}_${dateStr}`;
                if (!groups[key]) {
                  groups[key] = {
                    id: key,
                    name: r.employeeName,
                    date: dateStr,
                    in: '-',
                    out: '-',
                    breaks: []
                  };
                }
                const timeStr = new Date(r.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                const rawTime = new Date(r.timestamp).getTime();
                if (r.action === 'in') {
                  groups[key].in = timeStr;
                } else if (r.action === 'out') {
                  groups[key].out = timeStr;
                } else if (r.action === 'break_in') {
                  groups[key].breaks.push({ type: 'in', time: timeStr, rawTime });
                } else if (r.action === 'break_out') {
                  groups[key].breaks.push({ type: 'out', time: timeStr, rawTime });
                }
              });
              
              const groupedList = Object.values(groups).sort((a, b) => new Date(b.date) - new Date(a.date));
              
              groupedList.forEach(item => {
                if (item.breaks) {
                  item.breaks.sort((a, b) => a.rawTime - b.rawTime);
                }
              });

              const formatBreaks = (breaks) => {
                if (!breaks || breaks.length === 0) return '';
                const result = [];
                for (let i = 0; i < breaks.length; i++) {
                  if (breaks[i].type === 'in') {
                    const nextOut = breaks.slice(i + 1).find(b => b.type === 'out');
                    if (nextOut) {
                      result.push(`${breaks[i].time} to ${nextOut.time}`);
                    } else {
                      result.push(`${breaks[i].time} (Ongoing)`);
                    }
                  }
                }
                if (result.length === 0 && breaks.some(b => b.type === 'out')) {
                  const outs = breaks.filter(b => b.type === 'out');
                  return ` | End Break: ${outs.map(o => o.time).join(', ')}`;
                }
                return ` | Break: ${result.join(', ')}`;
              };

              if (groupedList.length === 0) {
                return (
                  <View style={[styles.center, { padding: 40 }]}>
                    <Text style={{ color: '#64748b' }}>No punch records recorded today.</Text>
                  </View>
                );
              }

              return groupedList.map((item) => (
                <View key={item.id} style={styles.registryRow}>
                  <View style={{ flex: 1.8 }}>
                    <Text style={styles.rowTitle}>{item.name}</Text>
                    <Text style={styles.rowSubtitle}>{item.date}{formatBreaks(item.breaks)}</Text>
                  </View>
                  <View style={{ flex: 1.2, alignItems: 'center' }}>
                    <Text style={[styles.label, { marginBottom: 2, fontSize: 8 }]}>IN TIME</Text>
                    <View style={[styles.punchBadge, item.in !== '-' ? styles.badgeSuccessBg : styles.badgeDisabledBg]}>
                      <Text style={[styles.punchBadgeText, item.in !== '-' ? styles.badgeSuccessText : styles.badgeDisabledText]}>
                        {item.in}
                      </Text>
                    </View>
                  </View>
                  <View style={{ flex: 1.2, alignItems: 'center' }}>
                    <Text style={[styles.label, { marginBottom: 2, fontSize: 8 }]}>OUT TIME</Text>
                    <View style={[styles.punchBadge, item.out !== '-' ? styles.badgeDangerBg : styles.badgeDisabledBg]}>
                      <Text style={[styles.punchBadgeText, item.out !== '-' ? styles.badgeDangerText : styles.badgeDisabledText]}>
                        {item.out}
                      </Text>
                    </View>
                  </View>
                </View>
              ));
            })()}
          </ScrollView>

          <TouchableOpacity 
            style={[styles.btn, styles.btnCancel, { marginTop: 10 }]}
            onPress={() => setScreen('scanner')}
          >
            <Text style={styles.btnTextSecondary}>Done</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* --- ATTENDANCE SCANNER SCREEN (Image 3 Match) --- */}
      {screen === 'scanner' && (
        <View style={styles.scannerFullScreenContainer}>
          <CameraView 
            ref={cameraRef}
            facing="front"
            style={styles.unstretchedCamera}
          />
          {/* Dark Translucent Overlay covering the entire camera as a sibling */}
          <View style={[
            styles.scannerCameraOverlayImmersive, 
            { paddingTop: (StatusBar.currentHeight || 24) + 15 }
          ]}>
            {/* Header Bar overlayed at the top */}
            <View style={styles.scannerHeaderOverlay}>
              <TouchableOpacity 
                style={styles.circularBackBtnScanner} 
                onPress={() => setShowSidebar(true)}
              >
                <Text style={styles.backBtnText}>☰</Text>
              </TouchableOpacity>
              <Text style={styles.scannerHeaderTitle}>Mark Attendance</Text>
              <View style={{ width: 40 }} />
            </View>

            {/* Ready to Scan Pill */}
            <View style={styles.readyScanPill}>
              <View style={styles.orangeIndicatorDot} />
              <Text style={styles.readyScanText}>READY TO SCAN</Text>
            </View>

            {/* Real-time Guidance Banner */}
            <Text style={[styles.scannerGuidanceText, { color: ovalColor }]}>
              {guidanceText}
            </Text>

            {/* Styled Face Guide Oval with Corner Brackets & Contour */}
            <Animated.View style={[
              styles.premiumFaceGuide, 
              { borderColor: ovalColor, opacity: glowAnim }
            ]}>
              {/* Corner bracket styling */}
              <View style={[styles.bracketTL, { borderColor: ovalColor }]} />
              <View style={[styles.bracketTR, { borderColor: ovalColor }]} />
              <View style={[styles.bracketBL, { borderColor: ovalColor }]} />
              <View style={[styles.bracketBR, { borderColor: ovalColor }]} />

              {/* Translucent Face Contour Vector representation */}
              <View style={styles.contourFaceOutline}>
                <View style={styles.contourEyebrows} />
                <View style={styles.contourEyesRow}>
                  <View style={styles.contourEye} />
                  <View style={styles.contourEye} />
                </View>
                <View style={styles.contourNose} />
                <View style={styles.contourLips} />
              </View>

              {scanSuccessful && (
                <View style={styles.successTickBadgeCircular}>
                  <Text style={styles.successTickTextSymbol}>✓</Text>
                </View>
              )}
            </Animated.View>

            {/* Bottom Swappable Panel: Location Card OR Employee Information Overlay */}
            {recognizedEmployee ? (
              <View style={styles.bottomCardWrapper}>
                <View style={styles.employeeGlassCard}>
                  <View style={styles.employeeCardRow}>
                    {recognizedEmployee.profile_photo ? (
                      <Image 
                        source={{ uri: `data:image/jpeg;base64,${recognizedEmployee.profile_photo}` }}
                        style={styles.employeeCardPhoto}
                      />
                    ) : (
                      <View style={styles.employeeCardPhotoPlaceholder}>
                        <Text style={styles.employeeCardPhotoPlaceholderText}>
                          {recognizedEmployee.employee_name ? recognizedEmployee.employee_name.charAt(0) : '?'}
                        </Text>
                      </View>
                    )}
                    <View style={styles.employeeCardInfo}>
                      <Text style={styles.employeeCardName}>{recognizedEmployee.employee_name}</Text>
                      <Text style={styles.employeeCardSubText}>ID: {recognizedEmployee.employee_id}</Text>
                      <Text style={styles.employeeCardSubText}>Dept: {recognizedEmployee.department}</Text>
                      
                      <View style={styles.employeeCardBadgeRow}>
                        <View style={[
                          styles.employeeStatusBadge, 
                          recognizedEmployee.status?.toLowerCase().includes('late') 
                            ? styles.statusBadgeLate 
                            : recognizedEmployee.status?.toLowerCase().includes('early')
                              ? styles.statusBadgeEarly
                              : styles.statusBadgePresent
                        ]}>
                          <Text style={styles.employeeStatusBadgeText}>
                            {recognizedEmployee.status === 'Present' 
                              ? 'Punched In Successful' 
                              : recognizedEmployee.status}
                          </Text>
                        </View>
                        <Text style={styles.employeePunchTimeText}>
                          {recognizedEmployee.action === 'Check-Out' || recognizedEmployee.action === 'Punch-Completed'
                            ? `Out: ${recognizedEmployee.check_out_time ? recognizedEmployee.check_out_time.split(' ')[1] + ' ' + recognizedEmployee.check_out_time.split(' ')[2] : 'Just Now'}`
                            : `In: ${recognizedEmployee.check_in_time ? recognizedEmployee.check_in_time.split(' ')[1] + ' ' + recognizedEmployee.check_in_time.split(' ')[2] : 'Just Now'}`}
                        </Text>
                      </View>
                    </View>
                  </View>
                  
                  {/* Special toast warning banner for late checks or early outs */}
                  {(recognizedEmployee.status?.toLowerCase().includes('late') || recognizedEmployee.status?.toLowerCase().includes('early')) && (
                    <View style={[
                      styles.warningBanner,
                      recognizedEmployee.status?.toLowerCase().includes('late') ? styles.warningBannerLate : styles.warningBannerEarly
                    ]}>
                      <Text style={styles.warningBannerText}>
                        {recognizedEmployee.status?.toLowerCase().includes('late') 
                          ? 'PUNCHED LATE (After 10:10 AM)' 
                          : 'PUNCHED OUT EARLY (Before 7:00 PM)'}
                      </Text>
                    </View>
                  )}
                </View>

                {recognizedEmployee.action === 'Already-Checked-In' && (
                  <View style={styles.secondPunchButtonsContainer}>
                    <TouchableOpacity 
                      style={styles.btnTakeBreak}
                      onPress={handleTakeBreak}
                    >
                      <Text style={styles.btnTextWhite}>Take a Break</Text>
                    </TouchableOpacity>
                    <TouchableOpacity 
                      style={styles.btnPunchOut}
                      onPress={handlePunchOut}
                    >
                      <Text style={styles.btnTextWhite}>Punch Out</Text>
                    </TouchableOpacity>
                  </View>
                )}
                {recognizedEmployee.action === 'On-Break-Scan' && (
                  <View style={styles.secondPunchButtonsContainer}>
                    <TouchableOpacity 
                      style={styles.btnTakeBreak}
                      onPress={handleEndBreak}
                    >
                      <Text style={styles.btnTextWhite}>End Break</Text>
                    </TouchableOpacity>
                  </View>
                )}
              </View>
            ) : (
              <>
                {/* Bottom Location Card */}
                <View style={styles.translucentLocationCard}>
                  <View style={styles.locationCardLeft}>
                    <View style={styles.locationTextContainer}>
                      <Text style={styles.locationLabelText}>CURRENT LOCATION</Text>
                      <Text style={styles.locationValueText}>{locationStr}</Text>
                    </View>
                  </View>
                  <TouchableOpacity style={styles.reloadLocationBtn} onPress={updateLocation}>
                    <Text style={styles.reloadEmojiText}>↻</Text>
                  </TouchableOpacity>
                </View>

                {/* Visual Scanner Button Status Circle at absolute bottom */}
                <View style={styles.visualScannerButtonWrapper}>
                  <View style={styles.visualScannerOuterCircle}>
                    <View style={styles.visualScannerInnerCircle} />
                  </View>
                </View>
              </>
            )}
          </View>
        </View>
      )}

      {/* --- SELFIE REVIEW SCREEN (Image 4 Match) --- */}
      {screen === 'review' && (
        <View style={styles.reviewContainer}>
          {/* Header Bar */}
          <View style={styles.reviewHeader}>
            <TouchableOpacity 
              style={styles.circularBackBtnReview} 
              onPress={() => { setScreen('scanner'); setCapturedSelfie(null); }}
            >
              <Text style={styles.backBtnTextDark}>←</Text>
            </TouchableOpacity>
            <Text style={styles.reviewHeaderTitle}>Mark Attendance</Text>
            <View style={{ width: 40 }} />
          </View>

          {/* Status Alert Badge */}
          <View style={styles.reviewTopAlertPill}>
            <Text style={styles.alertPillText}>Selfie captured successfully</Text>
          </View>

          {/* Selfie Photo Card */}
          <View style={styles.reviewPhotoCard}>
            {capturedSelfie ? (
              <Image 
                source={{ uri: `data:image/jpeg;base64,${capturedSelfie}` }} 
                style={styles.reviewImage} 
              />
            ) : (
              <View style={[styles.reviewImage, styles.center, { backgroundColor: '#1e293b' }]}>
                <ActivityIndicator color="#fff" />
              </View>
            )}

            {/* Badges overlaid on top of photo */}
            <View style={styles.reviewPhotoOverlayTop}>
              <View style={styles.matchedBadgePill}>
                <Text style={styles.matchedBadgeTick}>✓</Text>
                <Text style={styles.matchedBadgeText}>FACE MATCHED</Text>
              </View>
              <View style={styles.timeBadgePill}>
                <Text style={styles.timeBadgeText}>
                  {scanResult?.timestamp ? new Date(scanResult.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '08:42 AM'}
                </Text>
              </View>
            </View>

            {/* Floating Location Card overlay at bottom of photo */}
            <View style={styles.reviewLocationOverlayBottom}>
              <View style={styles.locationTextContainer}>
                <Text style={styles.locationLabelText}>CURRENT LOCATION</Text>
                <Text style={styles.locationValueTextReview}>{locationStr}</Text>
              </View>
            </View>
          </View>

          {/* Review Text */}
          <View style={styles.reviewTextPanel}>
            <Text style={styles.reviewTitleText}>Review your selfie</Text>
            <Text style={styles.reviewSubtitleText}>Ensure your face is clearly visible and well-lit.</Text>
          </View>

          {/* Bottom Side-by-Side Actions */}
          <View style={styles.reviewActionsRow}>
            <TouchableOpacity 
              style={[styles.btn, styles.btnLightGreyCancel, { flex: 1 }]}
              onPress={() => { setScreen('scanner'); setCapturedSelfie(null); }}
            >
              <Text style={styles.btnTextGrey}>Retake</Text>
            </TouchableOpacity>

            <TouchableOpacity 
              style={[styles.btn, styles.btnOrangePrimary, { flex: 1.3, flexDirection: 'row', gap: 6, justifyContent: 'center' }]}
              onPress={handleSubmitPunch}
            >
              <Text style={styles.btnTextWhite}>Submit Punch</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* --- ATTENDANCE RESULT VERIFIED MODAL (Image 1 Success Match) --- */}
      <Modal
        visible={showResultModal}
        transparent={false}
        animationType="fade"
      >
        <SafeAreaView style={styles.successBgContainer}>
          <StatusBar barStyle="dark-content" />
          
          <ScrollView contentContainerStyle={styles.successContentScroll} showsVerticalScrollIndicator={false}>
            {/* Success Checkmark Circular Backdrop */}
            <View style={styles.successEmojiWrapper}>
              <View style={styles.successEmojiCircle}>
                <Text style={[styles.successEmojiTextCharacter, { color: '#ffffff', fontSize: 44, marginTop: -4 }]}>✓</Text>
              </View>
            </View>

            {/* Gratitude Heading */}
            <Text style={styles.successHeading}>Thanks for marking attendance</Text>
            <Text style={styles.successSubheading}>
              Your {scanResult?.action === 'Check-In' ? 'punch-in' : 'punch-out'} at{' '}
              {scanResult?.timestamp 
                ? new Date(scanResult.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) 
                : '08:45 AM'}{' '}
              was successful.
            </Text>

            {/* Shift Status Card */}
            <View style={styles.successRoundedCard}>
              <View style={styles.successCardTextCol}>
                <Text style={styles.successCardLabel}>SHIFT STATUS</Text>
                <Text style={styles.successCardValue}>{shiftStatusText}</Text>
              </View>
            </View>

            {/* Location Card */}
            <View style={styles.successRoundedCard}>
              <View style={styles.successCardTextCol}>
                <Text style={styles.successCardLabel}>LOCATION</Text>
                <Text style={styles.successCardValue}>{locationStr}</Text>
              </View>
            </View>

            {/* Done Action Button */}
            <TouchableOpacity 
              style={[styles.btn, styles.btnOrangePrimary, { marginTop: 30 }]}
              onPress={() => { 
                setShowResultModal(false); 
                setScreen('scanner'); 
                resetScannerState(); 
                setCapturedSelfie(null); 
              }}
            >
              <Text style={styles.btnTextWhite}>Done</Text>
            </TouchableOpacity>
          </ScrollView>
        </SafeAreaView>
      </Modal>

      {/* --- LOGOUT CONFIRMATION SCREEN (Image 5 Match) --- */}
      {screen === 'logout' && (
        <View style={styles.logoutBgContainer}>
          {/* Header Bar */}
          <View style={styles.logoutHeader}>
            <TouchableOpacity 
              style={styles.circularBackBtnLogout} 
              onPress={() => setScreen('scanner')}
            >
              <Text style={styles.backBtnTextDark}>←</Text>
            </TouchableOpacity>
            <Text style={styles.logoutHeaderTitle}>Logout</Text>
            <View style={{ width: 40 }} />
          </View>

          <View style={styles.logoutContentCenter}>
            {/* Logout Confirm Prompts */}
            <Text style={[styles.logoutPromptTitle, { marginTop: 40 }]}>Are you sure you want to log out?</Text>

            {/* Actions */}
            <TouchableOpacity 
              style={[styles.btn, styles.btnOrangePrimary, { width: '85%', marginTop: 24 }]}
              onPress={() => {
                setScreen('login');
              }}
            >
              <Text style={styles.btnTextWhite}>Log Out</Text>
            </TouchableOpacity>

            <TouchableOpacity 
              style={[styles.btn, styles.btnLightGreyCancel, { width: '85%', marginTop: 12 }]}
              onPress={() => setScreen('scanner')}
            >
              <Text style={styles.btnTextGrey}>Stay Logged In</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* SIDEBAR OVERLAY */}
      {showSidebar && (
        <View style={styles.sidebarOverlayContainer}>
          {/* Backdrop to close drawer */}
          <TouchableOpacity 
            style={styles.sidebarBackdrop} 
            activeOpacity={1}
            onPress={() => setShowSidebar(false)}
          />

          {/* Sidebar Panel Content */}
          <View style={styles.sidebarPanel}>
            {/* Header / Brand */}
            <View style={styles.sidebarHeader}>
              <View style={styles.sidebarBrandContainer}>
                <Image source={require('./logo.png')} style={styles.sidebarLogoImage} />
                <Text style={styles.sidebarBrandTitle}>Menu Bar</Text>
              </View>
            </View>

            {/* Menu Items */}
            <View style={styles.sidebarMenuItems}>
              <Text style={styles.sidebarSectionLabel}>QUICK ACTIONS</Text>
              
              <TouchableOpacity 
                style={styles.sidebarMenuBtn}
                onPress={() => {
                  setShowSidebar(false);
                  openDashboard();
                }}
              >
                <Text style={styles.sidebarMenuBtnText}>View Dashboard</Text>
              </TouchableOpacity>

              <TouchableOpacity 
                style={[styles.sidebarMenuBtn, { marginTop: 14 }]}
                onPress={() => {
                  setShowSidebar(false);
                  setScreen('passcode');
                }}
              >
                <Text style={styles.sidebarMenuBtnText}>Admin Panel</Text>
              </TouchableOpacity>

              <TouchableOpacity 
                style={[styles.sidebarMenuBtn, { marginTop: 14, borderColor: '#ef4444' }]}
                onPress={() => {
                  setShowSidebar(false);
                  setScreen('logout');
                }}
              >
                <Text style={[styles.sidebarMenuBtnText, { color: '#ef4444' }]}>Log Out</Text>
              </TouchableOpacity>
            </View>

            {/* Footer */}
            <View style={styles.sidebarFooter}>
              <Text style={styles.sidebarFooterText}>v1.0.0 • Powered by EktaHR</Text>
            </View>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  parentSafeArea: {
    flex: 1,
  },
  container: {
    flex: 1,
    paddingHorizontal: 20,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  flexContainer: {
    flex: 1,
    justifyContent: 'space-between',
    paddingVertical: 10,
  },
  loadingText: {
    color: '#64748b',
    fontSize: 14,
    marginTop: 10,
  },
  headerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    marginTop: 40, // Pushed down to clear Android status bar comfortably
    marginBottom: 10,
    width: '100%',
  },
  hamburgerBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#f5a623',
    shadowColor: '#f5a623',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  hamburgerText: {
    fontSize: 20,
    color: '#f5a623',
    fontWeight: 'bold',
    marginTop: -2,
  },
  headerTextWrapper: {
    alignItems: 'center',
    flex: 1,
  },
  header: {
    marginTop: 15,
    marginBottom: 10,
    alignItems: 'center',
  },
  headerLogo: {
    fontSize: 26,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  headerSubtitle: {
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 3,
    textTransform: 'uppercase',
    marginTop: 4,
  },
  homeContainer: {
    flex: 1,
    justifyContent: 'center',
    gap: 12,
  },
  card: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#e2e8f0',
    borderRadius: 24,
    padding: 24,
    marginBottom: 15,
    alignItems: 'center',
    overflow: 'hidden',
    shadowColor: '#0f172a',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.04,
    shadowRadius: 10,
    elevation: 4,
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: '800',
    color: '#1E293B',
    marginBottom: 8,
  },
  cardDesc: {
    fontSize: 12,
    color: '#64748b',
    textAlign: 'center',
    lineHeight: 18,
  },
  formPanel: {
    marginBottom: 12,
  },
  label: {
    fontSize: 10,
    fontWeight: '800',
    color: '#64748b',
    marginBottom: 6,
    letterSpacing: 1.2,
  },
  input: {
    backgroundColor: '#fff',
    borderWidth: 1.5,
    borderColor: '#e2e8f0',
    borderRadius: 16,
    padding: 14,
    color: '#1E293B',
    fontSize: 14,
    fontWeight: '600',
  },
  cameraContainer: {
    flex: 1,
    borderRadius: 30,
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: 'rgba(0, 210, 255, 0.1)',
    backgroundColor: '#000',
    minHeight: SCREEN_HEIGHT * 0.45,
  },
  cameraLockOverlay: {
    flex: 1,
    backgroundColor: '#ffffff',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 30,
  },
  lockText: {
    fontSize: 18,
    fontWeight: '800',
    color: '#e2e8f0',
    marginBottom: 8,
  },
  lockSubtext: {
    fontSize: 13,
    color: '#64748b',
    textAlign: 'center',
    lineHeight: 20,
  },
  camera: {
    flex: 1,
  },
  cameraOverlay: {
    flex: 1,
    backgroundColor: 'rgba(10,13,26,0.3)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  guidanceBanner: {
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'center',
    width: '90%',
    marginBottom: 16,
    letterSpacing: 0.5,
  },
  targetGuideOval: {
    width: 190,
    height: 260,
    borderRadius: 95,
    borderWidth: 3,
    borderStyle: 'solid',
    justifyContent: 'center',
    alignItems: 'center',
  },
  successTickBadge: {
    width: 90,
    height: 90,
    borderRadius: 45,
    backgroundColor: '#10b981', // green success badge circle (centered inside guide!)
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#10b981',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.5,
    shadowRadius: 10,
    elevation: 6,
  },
  tickText: {
    color: '#fff',
    fontSize: 48,
    fontWeight: '900',
    marginTop: -4,
  },
  footerActions: {
    marginTop: 15,
    gap: 10,
  },
  btn: {
    paddingVertical: 14,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    width: '100%',
  },
  btnPrimary: {
    backgroundColor: '#f5a623',
    borderWidth: 2,
    borderColor: '#d97706',
  },
  btnSecondary: {
    backgroundColor: '#f5a623',
    borderWidth: 2,
    borderColor: '#d97706',
  },
  btnSuccess: {
    backgroundColor: '#f5a623',
    borderWidth: 2,
    borderColor: '#d97706',
  },
  btnDanger: {
    backgroundColor: '#f5a623',
    borderWidth: 2,
    borderColor: '#d97706',
  },
  btnCancel: {
    backgroundColor: '#f5a623',
    borderWidth: 2,
    borderColor: '#d97706',
  },
  btnDisabled: {
    backgroundColor: '#cbd5e1',
    borderWidth: 2,
    borderColor: '#94a3b8',
    opacity: 0.5,
  },
  btnText: {
    color: '#ffffff',
    fontWeight: '800',
    fontSize: 14,
  },
  btnTextLight: {
    color: '#ffffff',
    fontWeight: '800',
    fontSize: 14,
  },
  btnTextSecondary: {
    color: '#ffffff',
    fontWeight: '800',
    fontSize: 14,
  },
  errorText: {
    color: '#ef4444',
    fontWeight: '800',
    fontSize: 16,
    marginBottom: 8,
  },
  errorSubtext: {
    color: '#64748b',
    fontSize: 13,
    textAlign: 'center',
  },
  modalBg: {
    flex: 1,
    backgroundColor: 'rgba(5,7,16,0.92)',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  modalContent: {
    backgroundColor: '#0a0d1a',
    borderWidth: 2,
    borderColor: 'rgba(16,185,129,0.3)',
    borderRadius: 32,
    padding: 30,
    alignItems: 'center',
    width: '100%',
  },
  modalTickBadge: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: 'rgba(16, 185, 129, 0.1)',
    borderWidth: 2,
    borderColor: '#10b981',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 14,
  },
  modalTickText: {
    color: '#10b981',
    fontSize: 28,
    fontWeight: '900',
    marginTop: -2,
  },
  modalStatus: {
    fontSize: 11,
    fontWeight: '900',
    color: '#10b981',
    letterSpacing: 2,
    marginBottom: 12,
  },
  resultDetails: {
    alignItems: 'center',
    width: '100%',
  },
  resultName: {
    fontSize: 20,
    fontWeight: '800',
    color: '#fff',
    marginBottom: 4,
  },
  resultId: {
    fontSize: 12,
    color: '#64748b',
    marginBottom: 14,
  },
  badgeRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 14,
  },
  badge: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 20,
  },
  badgeSuccess: {
    backgroundColor: 'rgba(16, 185, 129, 0.06)',
    borderWidth: 1,
    borderColor: 'rgba(16, 185, 129, 0.15)',
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '800',
    color: '#10b981',
  },
  confidenceText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#fff',
  },
  timeText: {
    fontSize: 11,
    color: '#64748b',
    marginTop: 8,
  },
  // Tab Layouts
  tabRow: {
    flexDirection: 'row',
    backgroundColor: '#11162d',
    borderRadius: 16,
    padding: 4,
    marginBottom: 12,
  },
  tabButton: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 12,
  },
  tabButtonActive: {
    backgroundColor: '#f5a623',
  },
  tabButtonText: {
    color: '#64748b',
    fontWeight: '700',
    fontSize: 13,
  },
  tabButtonTextActive: {
    color: '#fff',
  },
  registryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#fff',
    padding: 14,
    borderRadius: 20,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    shadowColor: '#0f172a',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.02,
    shadowRadius: 8,
    elevation: 2,
  },
  rowTitle: {
    color: '#1E293B',
    fontWeight: '700',
    fontSize: 14,
  },
  rowSubtitle: {
    color: '#64748b',
    fontSize: 11,
    marginTop: 2,
  },
  deleteButton: {
    backgroundColor: 'rgba(239, 68, 68, 0.08)',
    borderWidth: 1,
    borderColor: 'rgba(239, 68, 68, 0.2)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  deleteButtonText: {
    color: '#ef4444',
    fontSize: 11,
    fontWeight: '700',
  },
  // Stats
  statsRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 12,
  },
  statsCard: {
    flex: 1,
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 14,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#e2e8f0',
    shadowColor: '#0f172a',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.04,
    shadowRadius: 10,
    elevation: 4,
  },
  statsLabel: {
    color: '#64748b',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  statsValue: {
    color: '#f5a623',
    fontSize: 26,
    fontWeight: '800',
    marginTop: 4,
  },
  punchBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 10,
  },
  punchBadgeText: {
    fontSize: 10,
    fontWeight: '800',
  },
  badgeSuccessBg: {
    backgroundColor: 'rgba(16, 185, 129, 0.08)',
  },
  badgeSuccessText: {
    color: '#10b981',
  },
  badgeDangerBg: {
    backgroundColor: 'rgba(239, 68, 68, 0.08)',
  },
  badgeDangerText: {
    color: '#ef4444',
  },
  badgeDisabledBg: {
    backgroundColor: 'rgba(255, 255, 255, 0.03)',
  },
  badgeDisabledText: {
    color: '#475569',
  },
  // Passcode / PIN Entry Screen styles (Mockup 2)
  passcodeContainer: {
    flex: 1,
    backgroundColor: '#0E0E10',
    paddingHorizontal: 20,
    justifyContent: 'space-between',
  },
  passcodeHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 20,
  },
  circularBackBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  backBtnText: {
    color: '#fff',
    fontSize: 20,
    fontWeight: 'bold',
  },
  passcodeHeaderTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  pinCard: {
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.06)',
    borderRadius: 24,
    padding: 24,
    alignItems: 'center',
    marginTop: 20,
  },
  pinLockIcon: {
    fontSize: 40,
    color: '#f5a623',
    marginBottom: 12,
  },
  pinTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#fff',
    marginBottom: 6,
  },
  pinSubtitle: {
    fontSize: 13,
    color: '#94a3b8',
    marginBottom: 20,
  },
  pinDotsRow: {
    flexDirection: 'row',
    gap: 12,
  },
  pinDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  pinDotFilled: {
    backgroundColor: '#f5a623',
  },
  pinDotEmpty: {
    borderWidth: 1.5,
    borderColor: '#64748b',
    backgroundColor: 'transparent',
  },
  keypadGrid: {
    marginTop: 20,
    gap: 12,
    alignItems: 'center',
  },
  keypadRow: {
    flexDirection: 'row',
    gap: 16,
  },
  keypadBtn: {
    width: SCREEN_WIDTH * 0.25,
    height: 60,
    borderRadius: 16,
    backgroundColor: 'rgba(255, 255, 255, 0.06)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.02)',
  },
  keypadBtnSpecial: {
    backgroundColor: 'transparent',
    borderWidth: 0,
  },
  keypadBtnText: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
  },
  keypadSpecialText: {
    color: '#64748b',
    fontSize: 13,
    fontWeight: '700',
  },
  btnOrangePrimary: {
    backgroundColor: '#f5a623',
  },
  btnTextWhite: {
    color: '#fff',
    fontWeight: '800',
    fontSize: 15,
  },

  // Scanner Screen styles (Mockup 3)
  scannerContainer: {
    flex: 1,
    backgroundColor: '#0E0E10',
  },
  scannerFullScreenContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    backgroundColor: '#000',
    zIndex: 999,
    overflow: 'hidden',
  },
  scannerCameraOverlayImmersive: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    backgroundColor: 'rgba(0, 0, 0, 0.35)',
    justifyContent: 'space-between',
    paddingBottom: 30,
    paddingHorizontal: 20,
    alignItems: 'center',
    zIndex: 10,
  },
  scannerHeaderOverlay: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
  },
  unstretchedCamera: {
    position: 'absolute',
    width: CALC_CAMERA_WIDTH,
    height: CALC_CAMERA_HEIGHT,
    left: CALC_CAMERA_LEFT,
    top: 0,
  },
  scannerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 15,
  },
  circularBackBtnScanner: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  scannerHeaderTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  scannerCameraWrapper: {
    flex: 1,
    borderTopLeftRadius: 36,
    borderTopRightRadius: 36,
    overflow: 'hidden',
    backgroundColor: '#000',
  },
  fullCamera: {
    flex: 1,
  },
  fullCameraOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.3)',
    justifyContent: 'space-between',
    paddingVertical: 20,
    alignItems: 'center',
  },
  readyScanPill: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    gap: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  orangeIndicatorDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#f5a623',
  },
  readyScanText: {
    color: '#e2e8f0',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.2,
  },
  scannerGuidanceText: {
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'center',
    width: '90%',
    marginVertical: 10,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  premiumFaceGuide: {
    width: 220,
    height: 290,
    borderRadius: 110,
    borderWidth: 2,
    borderStyle: 'dashed',
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  bracketTL: {
    position: 'absolute',
    top: -5,
    left: -5,
    width: 25,
    height: 25,
    borderTopWidth: 4,
    borderLeftWidth: 4,
    borderTopLeftRadius: 12,
  },
  bracketTR: {
    position: 'absolute',
    top: -5,
    right: -5,
    width: 25,
    height: 25,
    borderTopWidth: 4,
    borderRightWidth: 4,
    borderTopRightRadius: 12,
  },
  bracketBL: {
    position: 'absolute',
    bottom: -5,
    left: -5,
    width: 25,
    height: 25,
    borderBottomWidth: 4,
    borderLeftWidth: 4,
    borderBottomLeftRadius: 12,
  },
  bracketBR: {
    position: 'absolute',
    bottom: -5,
    right: -5,
    width: 25,
    height: 25,
    borderBottomWidth: 4,
    borderRightWidth: 4,
    borderBottomRightRadius: 12,
  },
  contourFaceOutline: {
    width: 140,
    height: 200,
    borderWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.18)',
    borderRadius: 70,
    justifyContent: 'center',
    alignItems: 'center',
    opacity: 0.85,
  },
  contourEyebrows: {
    width: 80,
    height: 4,
    borderTopWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.15)',
    borderRadius: 2,
    marginBottom: 8,
  },
  contourEyesRow: {
    flexDirection: 'row',
    gap: 30,
    marginBottom: 10,
  },
  contourEye: {
    width: 24,
    height: 12,
    borderWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.15)',
    borderRadius: 12,
  },
  contourNose: {
    width: 16,
    height: 30,
    borderLeftWidth: 1.5,
    borderBottomWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.15)',
    marginBottom: 10,
  },
  contourLips: {
    width: 44,
    height: 14,
    borderWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.15)',
    borderRadius: 7,
  },
  successTickBadgeCircular: {
    position: 'absolute',
    width: 90,
    height: 90,
    borderRadius: 45,
    backgroundColor: '#10b981',
    justifyContent: 'center',
    alignItems: 'center',
  },
  successTickTextSymbol: {
    color: '#fff',
    fontSize: 50,
    fontWeight: '900',
  },
  translucentLocationCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.55)',
    borderRadius: 24,
    padding: 16,
    width: '90%',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  locationCardLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flex: 1,
  },
  locationPinBg: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(245, 166, 35, 0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  locationPinEmoji: {
    fontSize: 20,
  },
  locationTextContainer: {
    flex: 1,
  },
  locationLabelText: {
    fontSize: 9,
    fontWeight: '900',
    color: '#94a3b8',
    letterSpacing: 1.2,
    marginBottom: 4,
  },
  locationValueText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#f8fafc',
    lineHeight: 16,
  },
  reloadLocationBtn: {
    padding: 6,
  },
  reloadEmojiText: {
    color: '#e2e8f0',
    fontSize: 20,
    fontWeight: '700',
  },
  visualScannerButtonWrapper: {
    marginVertical: 10,
  },
  visualScannerOuterCircle: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 5,
    borderColor: '#fff',
    backgroundColor: 'transparent',
    justifyContent: 'center',
    alignItems: 'center',
  },
  visualScannerInnerCircle: {
    width: 54,
    height: 54,
    borderRadius: 27,
    backgroundColor: '#f5a623',
  },

  // Selfie Review Screen Styles (Mockup 4)
  reviewContainer: {
    flex: 1,
    backgroundColor: '#F9FAFB',
    paddingHorizontal: 20,
    justifyContent: 'space-between',
    paddingBottom: 20,
  },
  reviewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 15,
  },
  circularBackBtnReview: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#f1f5f9',
    justifyContent: 'center',
    alignItems: 'center',
  },
  backBtnTextDark: {
    color: '#1E293B',
    fontSize: 18,
    fontWeight: 'bold',
  },
  reviewHeaderTitle: {
    color: '#1E293B',
    fontSize: 18,
    fontWeight: '700',
  },
  reviewTopAlertPill: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#334155',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 24,
    gap: 8,
    marginVertical: 10,
  },
  alertPillIcon: {
    fontSize: 15,
  },
  alertPillText: {
    color: '#e2e8f0',
    fontSize: 13,
    fontWeight: '700',
  },
  reviewPhotoCard: {
    width: '100%',
    height: SCREEN_HEIGHT * 0.44,
    borderRadius: 32,
    overflow: 'hidden',
    position: 'relative',
    backgroundColor: '#e2e8f0',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 8,
  },
  reviewImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  reviewPhotoOverlayTop: {
    position: 'absolute',
    top: 16,
    left: 16,
    right: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  matchedBadgePill: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(15, 23, 42, 0.75)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
    gap: 6,
  },
  matchedBadgeTick: {
    color: '#f5a623',
    fontWeight: '900',
    fontSize: 11,
  },
  matchedBadgeText: {
    color: '#f8fafc',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  timeBadgePill: {
    backgroundColor: 'rgba(255, 255, 255, 0.85)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  timeBadgeText: {
    color: '#1e293b',
    fontSize: 10,
    fontWeight: '800',
  },
  reviewLocationOverlayBottom: {
    position: 'absolute',
    bottom: 16,
    left: 16,
    right: 16,
    backgroundColor: 'rgba(255,255,255,0.92)',
    borderRadius: 20,
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  locationValueTextReview: {
    fontSize: 12,
    fontWeight: '700',
    color: '#334155',
  },
  reviewTextPanel: {
    alignItems: 'center',
    marginVertical: 14,
  },
  reviewTitleText: {
    fontSize: 22,
    fontWeight: '700',
    color: '#1e293b',
    marginBottom: 6,
  },
  reviewSubtitleText: {
    fontSize: 13,
    color: '#64748b',
    textAlign: 'center',
    lineHeight: 18,
    paddingHorizontal: 20,
  },
  reviewActionsRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 10,
  },
  btnGreySecondary: {
    backgroundColor: '#e2e8f0',
  },
  btnTextGrey: {
    color: '#334155',
    fontWeight: '800',
    fontSize: 15,
  },

  // Success Screen Styles (Mockup 1 Match)
  successBgContainer: {
    flex: 1,
    backgroundColor: '#F9FAFB',
    paddingHorizontal: 24,
  },
  successContentScroll: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 40,
  },
  successEmojiWrapper: {
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 20,
  },
  successEmojiCircle: {
    width: 130,
    height: 130,
    borderRadius: 65,
    backgroundColor: '#FEF3C7',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#FEF3C7',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 15,
    elevation: 8,
  },
  successEmojiTextCharacter: {
    fontSize: 66,
  },
  successHeading: {
    fontSize: 25,
    fontWeight: '700',
    color: '#1E293B',
    textAlign: 'center',
    marginBottom: 10,
    lineHeight: 32,
    paddingHorizontal: 10,
  },
  successSubheading: {
    fontSize: 14,
    color: '#64748B',
    textAlign: 'center',
    lineHeight: 20,
    marginBottom: 30,
    paddingHorizontal: 20,
  },
  successRoundedCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    borderRadius: 24,
    padding: 16,
    width: '100%',
    marginBottom: 14,
    shadowColor: '#0f172a',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.04,
    shadowRadius: 10,
    elevation: 4,
  },
  statusIconCircle: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#EEF2FF',
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusIconEmoji: {
    fontSize: 18,
  },
  successCardTextCol: {
    marginLeft: 14,
    flex: 1,
  },
  successCardLabel: {
    fontSize: 9,
    fontWeight: '800',
    color: '#94a3b8',
    letterSpacing: 1.2,
    marginBottom: 2,
  },
  successCardValue: {
    fontSize: 14,
    fontWeight: '700',
    color: '#1E293B',
  },
  locationIconCircle: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#FEF3C7',
    alignItems: 'center',
    justifyContent: 'center',
  },
  locationIconEmoji: {
    fontSize: 18,
  },

  // Logout Screen Styles (Mockup 5 Match)
  logoutBgContainer: {
    flex: 1,
    backgroundColor: '#F9FAFB',
    paddingHorizontal: 24,
  },
  logoutHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 15,
  },
  circularBackBtnLogout: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#f1f5f9',
    justifyContent: 'center',
    alignItems: 'center',
  },
  logoutHeaderTitle: {
    color: '#f5a623',
    fontSize: 18,
    fontWeight: '700',
  },
  logoutContentCenter: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingBottom: 40,
  },
  logoutBackdropCircle: {
    width: 160,
    height: 160,
    borderRadius: 80,
    backgroundColor: '#FEF3C7',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
    marginBottom: 30,
  },
  doorIllustrationCard: {
    width: 110,
    height: 110,
    borderRadius: 55,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#f5a623',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 6,
  },
  logoutLockBadge: {
    position: 'absolute',
    bottom: 5,
    right: 5,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 4,
  },
  logoutPromptTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#1E293B',
    textAlign: 'center',
    paddingHorizontal: 20,
    marginBottom: 10,
    lineHeight: 28,
  },
  btnLightGreyCancel: {
    backgroundColor: '#f1f5f9',
  },
  btnElectricGreen: {
    backgroundColor: '#10b981',
    borderWidth: 2,
    borderColor: '#059669',
  },
  enrollFullScreenContainer: {
    flex: 1,
    backgroundColor: '#ffffff',
    overflow: 'hidden',
  },
  enrollCameraOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.3)',
    justifyContent: 'space-between',
    paddingVertical: 20,
    paddingHorizontal: 20,
    alignItems: 'center',
  },
  enrollFullCamera: {
    flex: 1,
  },
  enrollInputCard: {
    backgroundColor: 'rgba(0, 0, 0, 0.65)',
    borderRadius: 20,
    padding: 14,
    width: '100%',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    marginTop: 10,
  },
  enrollLabelText: {
    fontSize: 9,
    fontWeight: '900',
    color: '#94a3b8',
    letterSpacing: 1.2,
    marginBottom: 6,
  },
  enrollTextInput: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    padding: 10,
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  enrollFloatingActions: {
    width: '100%',
    gap: 10,
  },
  homeLogoImage: {
    width: SCREEN_WIDTH * 0.85, // Made logo larger per request
    height: 200,                // Taller height
    resizeMode: 'contain',
    alignSelf: 'center',
    marginVertical: 45,
  },
  sidebarOverlayContainer: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    zIndex: 10000,
    flexDirection: 'row',
  },
  sidebarBackdrop: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: 'rgba(15, 23, 42, 0.45)',
  },
  sidebarPanel: {
    width: SCREEN_WIDTH * 0.72,
    height: '100%',
    backgroundColor: '#ffffff',
    paddingHorizontal: 20,
    paddingVertical: 30,
    justifyContent: 'space-between',
    shadowColor: '#0f172a',
    shadowOffset: { width: 4, height: 0 },
    shadowOpacity: 0.15,
    shadowRadius: 16,
    elevation: 20,
    borderTopRightRadius: 28,
    borderBottomRightRadius: 28,
  },
  sidebarHeader: {
    borderBottomWidth: 1,
    borderBottomColor: '#f1f5f9',
    paddingBottom: 20,
    width: '100%',
  },
  sidebarBrandContainer: {
    alignItems: 'flex-start',
    width: '100%',
  },
  sidebarLogoImage: {
    width: 170,
    height: 75,
    resizeMode: 'contain',
    alignSelf: 'flex-start',
    marginBottom: 5,
  },
  sidebarBrandTitle: {
    fontSize: 22,
    fontWeight: '900',
    color: '#1E293B',
    marginTop: 5,
  },
  sidebarCloseBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#f1f5f9',
    justifyContent: 'center',
    alignItems: 'center',
  },
  sidebarCloseBtnText: {
    fontSize: 14,
    color: '#64748b',
    fontWeight: 'bold',
  },
  sidebarMenuItems: {
    flex: 1,
    marginTop: 35,
  },
  sidebarSectionLabel: {
    fontSize: 9,
    fontWeight: '800',
    color: '#94a3b8',
    letterSpacing: 1.5,
    marginBottom: 16,
  },
  sidebarMenuBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    borderWidth: 2,
    borderColor: '#d97706',
    borderRadius: 16,
    paddingVertical: 14,
    paddingHorizontal: 16,
    shadowColor: '#f5a623',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
  sidebarMenuBtnIcon: {
    fontSize: 18,
    marginRight: 12,
  },
  sidebarMenuBtnText: {
    fontSize: 14,
    fontWeight: '800',
    color: '#1E293B',
  },
  sidebarFooter: {
    borderTopWidth: 1,
    borderTopColor: '#f1f5f9',
    paddingTop: 15,
    alignItems: 'center',
  },
  sidebarFooterText: {
    fontSize: 10,
    color: '#94a3b8',
    fontWeight: '600',
  },
  enrollFloatingActions: {
    width: '100%',
    gap: 10,
  },
  loginFullScreenContainer: {
    flex: 1,
    backgroundColor: '#f5a623',
    position: 'relative',
  },
  loginTopDarkHalf: {
    height: '42%',
    backgroundColor: '#0E0E10',
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 10,
    borderBottomLeftRadius: 40,
    borderBottomRightRadius: 40,
  },
  loginLogoImage: {
    width: 260,
    height: 100,
    resizeMode: 'contain',
  },
  loginBottomGoldHalf: {
    flex: 1,
    backgroundColor: '#f5a623',
    alignItems: 'center',
    justifyContent: 'center',
  },
  loginCenterCard: {
    position: 'absolute',
    top: -110,
    backgroundColor: '#2D2D32',
    width: SCREEN_WIDTH * 0.88,
    borderRadius: 24,
    padding: 24,
    paddingTop: 32,
    paddingBottom: 32,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.35,
    shadowRadius: 15,
    elevation: 10,
  },
  loginInputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#3F3F46',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    width: '100%',
    height: 52,
    paddingHorizontal: 15,
    marginBottom: 20,
  },
  loginInputIcon: {
    fontSize: 18,
    marginRight: 12,
    color: '#f5a623',
  },
  loginTextInputField: {
    flex: 1,
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '500',
  },
  loginPasswordEyeToggle: {
    padding: 5,
  },
  loginPasswordEyeText: {
    fontSize: 13,
    color: '#f5a623',
    fontWeight: '700',
  },
  loginForgotPasswordText: {
    color: '#f5a623',
    fontSize: 13,
    fontWeight: '600',
  },
  loginBtn: {
    backgroundColor: '#f5a623',
    width: '100%',
    height: 52,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#f5a623',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
    marginTop: 10,
  },
  loginBtnText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '700',
  },
  // --- SPLASH SCREEN STYLES ---
  splashContainer: {
    flex: 1,
    backgroundColor: '#f5a623',
    alignItems: 'center',
    justifyContent: 'center',
  },
  splashHalo: {
    width: 155,
    height: 155,
    borderRadius: 77.5,
    backgroundColor: 'rgba(255, 255, 255, 0.18)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
  },
  splashCircle: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.12,
    shadowRadius: 6,
    elevation: 3,
  },
  splashLetterE: {
    fontSize: 70,
    fontWeight: '900',
    color: '#1C1C1E',
    marginTop: -8,
  },
  splashDot: {
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#f5a623',
    position: 'absolute',
    top: 36,
    left: 28,
  },
  splashBrandText: {
    color: '#ffffff',
    fontSize: 32,
    fontWeight: '800',
    letterSpacing: 0.8,
    marginBottom: 40,
  },
  splashDotsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    height: 20,
  },
  splashDotIndicator: {
    borderRadius: 8,
    backgroundColor: '#1C1C1E',
    marginHorizontal: 8,
  },
  splashDotActive: {
    width: 10,
    height: 10,
    opacity: 0.9,
  },
  splashDotInactive: {
    width: 6,
    height: 6,
    opacity: 0.45,
  },
  // --- CAMERA SCANNER ACTION TOGGLE STYLES ---
  scannerActionToggleContainer: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    borderRadius: 25,
    padding: 4,
    width: '80%',
    alignSelf: 'center',
    marginVertical: 15,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.15)',
  },
  scannerActionToggleBtn: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
    borderRadius: 21,
  },
  scannerActionToggleBtnActive: {
    backgroundColor: '#f5a623',
  },
  scannerActionToggleText: {
    color: 'rgba(255, 255, 255, 0.65)',
    fontSize: 14,
    fontWeight: '700',
  },
  scannerActionToggleTextActive: {
    color: '#ffffff',
    fontWeight: '800',
  },
  // --- EMPLOYEE GLASS CARD STYLES ---
  employeeGlassCard: {
    backgroundColor: 'rgba(20, 20, 22, 0.82)',
    borderRadius: 24,
    padding: 18,
    width: '90%',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.35,
    shadowRadius: 15,
    elevation: 8,
    marginBottom: 20,
  },
  bottomCardWrapper: {
    width: '100%',
    alignItems: 'center',
  },
  secondPunchButtonsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    width: '90%',
    gap: 12,
    marginBottom: 20,
  },
  btnTakeBreak: {
    flex: 1,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.25)',
    paddingVertical: 16,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnPunchOut: {
    flex: 1,
    backgroundColor: '#ef4444',
    paddingVertical: 16,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  employeeCardRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  employeeCardPhoto: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 1.5,
    borderColor: '#f5a623',
    backgroundColor: '#000',
  },
  employeeCardPhotoPlaceholder: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: 'rgba(255, 255, 255, 0.15)',
  },
  employeeCardPhotoPlaceholderText: {
    color: '#fff',
    fontSize: 32,
    fontWeight: '800',
  },
  employeeCardInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  employeeCardName: {
    color: '#ffffff',
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 4,
  },
  employeeCardSubText: {
    color: '#94a3b8',
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 2,
  },
  employeeCardBadgeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 6,
    gap: 10,
  },
  employeeStatusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
  },
  statusBadgePresent: {
    backgroundColor: 'rgba(16, 185, 129, 0.15)',
  },
  statusBadgeLate: {
    backgroundColor: 'rgba(245, 166, 35, 0.15)',
  },
  statusBadgeEarly: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
  },
  employeeStatusBadgeText: {
    fontSize: 10,
    fontWeight: '800',
    color: '#ffffff',
  },
  employeePunchTimeText: {
    color: '#cbd5e1',
    fontSize: 11,
    fontWeight: '700',
  },
  warningBanner: {
    marginTop: 12,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  warningBannerLate: {
    backgroundColor: 'rgba(245, 166, 35, 0.18)',
    borderWidth: 1,
    borderColor: 'rgba(245, 166, 35, 0.25)',
  },
  warningBannerEarly: {
    backgroundColor: 'rgba(239, 68, 68, 0.18)',
    borderWidth: 1,
    borderColor: 'rgba(239, 68, 68, 0.25)',
  },
  warningBannerText: {
    color: '#ffffff',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  }
});
