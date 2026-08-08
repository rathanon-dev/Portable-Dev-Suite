# ========================================================
# Portable Dev Suite - Instant Feedback Web API / UI Demo
# Uses Python Standard Library (Zero External Dependencies)
# ========================================================

import os
import sys
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

def get_system_status():
    status = {
        "python_version": sys.version,
        "python_executable": sys.executable,
        "git_version": "Not Found",
        "cuda_available": False,
        "cuda_device_name": "None / CPU Mode",
        "pytorch_version": "Not Installed",
        "env_path": os.environ.get("PATH", "")
    }

    # Check Git
    try:
        git_res = subprocess.run(["git", "--version"], capture_output=True, text=True)
        if git_res.returncode == 0:
            status["git_version"] = git_res.stdout.strip()
    except Exception:
        pass

    # Check PyTorch & CUDA
    try:
        import torch
        status["pytorch_version"] = torch.__version__
        if torch.cuda.is_available():
            status["cuda_available"] = True
            status["cuda_device_name"] = torch.cuda.get_device_name(0)
    except ImportError:
        import glob
        # Smart Physical Check for CUDA DLLs in PATH
        cuda_dll_found = False
        for p in os.environ.get("PATH", "").split(os.pathsep):
            if p and os.path.isdir(p):
                if glob.glob(os.path.join(p, "cudart64_*.dll")):
                    cuda_dll_found = True
                    break
                    
        if cuda_dll_found:
            status["cuda_device_name"] = "CUDA Runtime DLLs detected in PATH (PyTorch not installed yet)"

    return status

class DemoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(get_system_status(), indent=2).encode('utf-8'))
            return

        # Serve Dashboard HTML
        status = get_system_status()
        cuda_badge_color = "#22c55e" if status["cuda_available"] else "#f59e0b"
        cuda_status_text = "READY (GPU Accelerated)" if status["cuda_available"] else status["cuda_device_name"]

        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Portable Dev Suite - System Status</title>
    <style>
        :root {{
            --bg: #0f172a;
            --card-bg: #1e293b;
            --text: #f8fafc;
            --accent: #38bdf8;
            --border: #334155;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 40px 20px;
            display: flex;
            justify-content: center;
        }}
        .container {{
            max-width: 750px;
            width: 100%;
        }}
        .header {{
            text-align: center;
            margin-bottom: 30px;
        }}
        .header h1 {{
            font-size: 2rem;
            color: var(--accent);
            margin-bottom: 8px;
        }}
        .header p {{
            color: #94a3b8;
            margin: 0;
        }}
        .card {{
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 20px;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.3);
        }}
        .card-title {{
            font-size: 1.1rem;
            font-weight: 600;
            margin-bottom: 16px;
            color: #e2e8f0;
            border-bottom: 1px solid var(--border);
            padding-bottom: 8px;
        }}
        .info-group {{
            display: grid;
            grid-template-columns: 180px 1fr;
            gap: 12px;
            margin-bottom: 12px;
            font-size: 0.95rem;
        }}
        .label {{
            color: #94a3b8;
            font-weight: 500;
        }}
        .value {{
            color: #f1f5f9;
            font-family: monospace;
            word-break: break-all;
        }}
        .badge {{
            display: inline-block;
            padding: 4px 10px;
            border-radius: 9999px;
            font-size: 0.85rem;
            font-weight: 600;
            color: #000;
        }}
        .footer {{
            text-align: center;
            color: #64748b;
            font-size: 0.85rem;
            margin-top: 30px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Portable Dev Suite (v20)</h1>
            <p>Instant Feedback Demo Web Server & System Diagnostics</p>
        </div>

        <div class="card">
            <div class="card-title">⚡ Environment Status</div>
            <div class="info-group">
                <span class="label">Python Version:</span>
                <span class="value">{status['python_version'].split()[0]}</span>
            </div>
            <div class="info-group">
                <span class="label">Python Path:</span>
                <span class="value">{status['python_executable']}</span>
            </div>
            <div class="info-group">
                <span class="label">Git Version:</span>
                <span class="value">{status['git_version']}</span>
            </div>
        </div>

        <div class="card">
            <div class="card-title">🎮 GPU & Acceleration</div>
            <div class="info-group">
                <span class="label">CUDA Status:</span>
                <span class="value">
                    <span class="badge" style="background-color: {cuda_badge_color};">
                        {cuda_status_text}
                    </span>
                </span>
            </div>
            <div class="info-group">
                <span class="label">PyTorch Engine:</span>
                <span class="value">{status['pytorch_version']}</span>
            </div>
        </div>

        <div class="footer">
            Portable Dev Suite • Zero System Footprint Environment
        </div>
    </div>
</body>
</html>
"""
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

    def log_message(self, format, *args):
        print(f" [HTTP] {self.address_string()} - {args[0]}")

def run_server(port=8000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, DemoHandler)
    print("====================================================================")
    print(" 🚀 PORTABLE DEV SUITE - DEMO WEB SERVER RUNNING")
    print("====================================================================")
    print(f" [ONLINE] Access Dashboard at : http://localhost:{port}")
    print(f" [ONLINE] Access API Endpoint at: http://localhost:{port}/api/status")
    print(" Press Ctrl+C to stop the server.")
    print("====================================================================")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n [STOPPING] Demo server stopped successfully.")

if __name__ == "__main__":
    run_server()