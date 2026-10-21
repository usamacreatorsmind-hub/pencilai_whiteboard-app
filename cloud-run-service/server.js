const express = require('express');
const multer = require('multer');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const app = express();
const port = process.env.PORT || 8080;
const API_KEY = process.env.API_KEY || 'default_secret_key';

const upload = multer({
  dest: os.tmpdir(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB max
});

// Middleware for API Key authentication
const authenticate = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || apiKey !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized: Invalid or missing API key' });
  }
  next();
};

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.post('/convert', authenticate, upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded in field "file"' });
  }

  const ext = path.extname(req.file.originalname).toLowerCase();
  if (ext !== '.ppt' && ext !== '.pptx') {
    if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'Invalid file type. Only .ppt and .pptx are supported.' });
  }

  const inputPath = req.file.path;
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'libre-out-'));
  const outputPath = path.join(outDir, `${path.basename(inputPath, ext)}.pdf`);

  try {
    console.log(`Starting conversion for ${req.file.originalname}`);

    // LibreOffice / soffice headless conversion with 120s timeout
    try {
      execSync(`soffice --headless --convert-to pdf --outdir "${outDir}" "${inputPath}"`, {
        timeout: 120000,
        stdio: 'inherit',
      });
    } catch (cmdErr) {
      execSync(`libreoffice --headless --convert-to pdf --outdir "${outDir}" "${inputPath}"`, {
        timeout: 120000,
        stdio: 'inherit',
      });
    }

    if (!fs.existsSync(outputPath)) {
      throw new Error('LibreOffice failed to generate PDF output.');
    }

    console.log(`Successfully converted to ${outputPath}`);

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="converted.pdf"');

    const stream = fs.createReadStream(outputPath);
    stream.pipe(res);

    stream.on('close', () => {
      // Cleanup temp files
      try {
        if (fs.existsSync(inputPath)) fs.unlinkSync(inputPath);
        if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
        if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
      } catch (cleanupErr) {
        console.error('Cleanup error:', cleanupErr);
      }
    });

  } catch (error) {
    console.error('Conversion error:', error);

    // Cleanup on error
    try {
      if (fs.existsSync(inputPath)) fs.unlinkSync(inputPath);
      if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
      if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    } catch (e) {}

    if (error.code === 'ETIMEDOUT' || error.signal === 'SIGTERM') {
      return res.status(504).json({ error: 'Conversion timed out (max 120s exceeded).' });
    }

    return res.status(500).json({ error: error.message || 'Internal server error during conversion.' });
  }
});

app.listen(port, () => {
  console.log(`Cloud Run LibreOffice service listening on port ${port}`);
});
