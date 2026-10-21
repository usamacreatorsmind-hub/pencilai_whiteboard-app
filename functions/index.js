const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const path = require("path");
const os = require("os");
const fs = require("fs");
const fetch = require("node-fetch");
const FormData = require("form-data");

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket();

const CLOUD_RUN_URL = process.env.CLOUD_RUN_URL || "https://libreoffice-converter-851240445518.asia-south1.run.app";
const CLOUD_RUN_API_KEY = process.env.CLOUD_RUN_API_KEY || "default_secret_key";

// MSG91 Credentials
const MSG91_AUTH_KEY = "404117AQvUYpgj64e33a96P1";
const MSG91_TEMPLATE_ID = "6abca873eb3e65a8af034715";
const MSG91_EMAIL_TEMPLATE_ID = "YOUR_EMAIL_TEMPLATE_ID"; // Replace with your MSG91 Email Template ID


// OTP functions deployed in asia-south1 (Mumbai) for fast response
exports.sendMsg91Otp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const mobile = req.body?.mobile || req.query?.mobile;
    if (!mobile) {
      return res.status(400).json({success: false, error: "Mobile number is required"});
    }

    let cleanMobile = mobile.toString().replace(/\D/g, "");
    if (cleanMobile.length === 10) {
      cleanMobile = "91" + cleanMobile;
    }

    const url = `https://control.msg91.com/api/v5/otp?template_id=${MSG91_TEMPLATE_ID}&mobile=${cleanMobile}`;
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "authkey": MSG91_AUTH_KEY,
        "content-type": "application/json",
      },
    });

    const data = await response.json();
    return res.status(200).json({success: true, data});
  } catch (error) {
    console.error("Error sending MSG91 OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

exports.verifyMsg91Otp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const mobile = req.body?.mobile || req.query?.mobile;
    const otp = req.body?.otp || req.query?.otp;

    if (!mobile || !otp) {
      return res.status(400).json({success: false, error: "Mobile and OTP are required"});
    }

    let cleanMobile = mobile.toString().replace(/\D/g, "");
    if (cleanMobile.length === 10) {
      cleanMobile = "91" + cleanMobile;
    }

    const url = `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&mobile=${cleanMobile}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "authkey": MSG91_AUTH_KEY,
      },
    });

    const data = await response.json();
    if (response.ok && (data.type === "success" || data.status === "success" || data.message)) {
      const userUid = `phone_${cleanMobile}`;
      return res.status(200).json({success: true, uid: userUid, mobile: cleanMobile, data});
    } else {
      return res.status(400).json({success: false, error: data.message || "Invalid OTP"});
    }
  } catch (error) {
    console.error("Error verifying MSG91 OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

exports.resendMsg91Otp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const mobile = req.body?.mobile || req.query?.mobile;
    if (!mobile) {
      return res.status(400).json({success: false, error: "Mobile number is required"});
    }

    let cleanMobile = mobile.toString().replace(/\D/g, "");
    if (cleanMobile.length === 10) {
      cleanMobile = "91" + cleanMobile;
    }

    const url = `https://control.msg91.com/api/v5/otp/retry?retrytype=text&mobile=${cleanMobile}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "authkey": MSG91_AUTH_KEY,
      },
    });

    const data = await response.json();
    return res.status(200).json({success: true, data});
  } catch (error) {
    console.error("Error resending MSG91 OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

// MSG91 Email OTP Endpoints
exports.sendMsg91EmailOtp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const email = req.body?.email || req.query?.email;
    if (!email) {
      return res.status(400).json({success: false, error: "Email is required"});
    }

    const url = `https://control.msg91.com/api/v5/otp?template_id=${MSG91_EMAIL_TEMPLATE_ID}&email=${encodeURIComponent(email)}`;
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "authkey": MSG91_AUTH_KEY,
        "content-type": "application/json",
      },
    });

    const data = await response.json();
    console.log("MSG91 Email OTP Response:", data);

    if (response.ok && data.type !== "error" && data.status !== "error") {
      return res.status(200).json({success: true, data});
    } else {
      return res.status(400).json({success: false, error: data.message || "Failed to send OTP via email. Please ensure MSG91 template supports email."});
    }
  } catch (error) {
    console.error("Error sending MSG91 Email OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

exports.verifyMsg91EmailOtp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const email = req.body?.email || req.query?.email;
    const otp = req.body?.otp || req.query?.otp;

    if (!email || !otp) {
      return res.status(400).json({success: false, error: "Email and OTP are required"});
    }

    const url = `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&email=${encodeURIComponent(email)}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "authkey": MSG91_AUTH_KEY,
      },
    });

    const data = await response.json();
    if (response.ok && (data.type === "success" || data.status === "success" || data.message)) {
      const cleanEmail = email.toString().trim().toLowerCase();
      const userUid = `email_${cleanEmail.replace(/[^a-z0-9]/g, '_')}`;
      return res.status(200).json({success: true, uid: userUid, email: cleanEmail, data});
    } else {
      return res.status(400).json({success: false, error: data.message || "Invalid OTP"});
    }
  } catch (error) {
    console.error("Error verifying MSG91 Email OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

exports.resendMsg91EmailOtp = onRequest({region: "asia-south1", cors: true, memory: "256MiB"}, async (req, res) => {
  try {
    const email = req.body?.email || req.query?.email;
    if (!email) {
      return res.status(400).json({success: false, error: "Email is required"});
    }

    const url = `https://control.msg91.com/api/v5/otp/retry?retrytype=text&email=${encodeURIComponent(email)}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "authkey": MSG91_AUTH_KEY,
      },
    });

    const data = await response.json();
    return res.status(200).json({success: true, data});
  } catch (error) {
    console.error("Error resending MSG91 Email OTP:", error);
    return res.status(500).json({success: false, error: error.message});
  }
});

// Storage trigger function in us-east1 (matching storage bucket region)
exports.convertppttopdf = onObjectFinalized({region: "us-east1", memory: "512MiB", timeoutSeconds: 300}, async (event) => {
  const filePath = event.data.name;
  const fileName = path.basename(filePath);

  // Trigger only for files under temp_uploads/
  if (!filePath.startsWith("temp_uploads/")) {
    return;
  }

  const ext = path.extname(fileName).toLowerCase();
  if (ext !== ".ppt" && ext !== ".pptx") {
    return;
  }

  // Extract docId from filename format: {docId}_{originalName}
  const parts = fileName.split("_");
  const docId = parts[0];
  if (!docId) {
    console.error("Invalid filename format, missing docId:", fileName);
    return;
  }

  const docRef = db.collection("conversions").doc(docId);
  await docRef.set({
    status: "converting",
    fileName: fileName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const localTempFilePath = path.join(os.tmpdir(), fileName);

  try {
    console.log(`Downloading ${filePath} to ${localTempFilePath}`);
    await bucket.file(filePath).download({destination: localTempFilePath});

    console.log(`Sending to Cloud Run: ${CLOUD_RUN_URL}/convert`);
    const form = new FormData();
    form.append("file", fs.createReadStream(localTempFilePath));

    const response = await fetch(`${CLOUD_RUN_URL}/convert`, {
      method: "POST",
      headers: {
        "x-api-key": CLOUD_RUN_API_KEY,
        ...form.getHeaders(),
      },
      body: form,
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Cloud Run error (${response.status}): ${errText}`);
    }

    const pdfBuffer = await response.buffer();
    const pdfStoragePath = `converted_pdfs/${docId}.pdf`;
    const pdfFile = bucket.file(pdfStoragePath);

    console.log(`Uploading converted PDF to ${pdfStoragePath}`);
    await pdfFile.save(pdfBuffer, {
      metadata: {contentType: "application/pdf"},
    });

    // Update Firestore as completed
    await docRef.set({
      status: "completed",
      pdfPath: pdfStoragePath,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    console.log(`Successfully converted and stored PDF for docId: ${docId}`);

  } catch (error) {
    console.error(`Conversion pipeline failed for docId ${docId}:`, error);
    await docRef.set({
      status: "error",
      error: error.message,
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } finally {
    // Cleanup local temp file
    try {
      if (fs.existsSync(localTempFilePath)) {
        fs.unlinkSync(localTempFilePath);
      }
      // Cleanup original upload from temp_uploads/
      await bucket.file(filePath).delete().catch(() => {});
    } catch (cleanupErr) {
      console.error("Cleanup error in function:", cleanupErr);
    }
  }
});
