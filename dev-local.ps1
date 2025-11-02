# Local Development Script - Start frontend and AgentCore backend locally

Write-Host "🚀 Starting Local Development Mode" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# Check if Python is available
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Python 3 is required but not installed" -ForegroundColor Red
    exit 1
}

# Check if Node.js is available
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Node.js is required but not installed" -ForegroundColor Red
    exit 1
}

# Install agent dependencies if needed
Write-Host "📦 Installing agent dependencies..." -ForegroundColor Yellow
if (-not (Test-Path "agent/venv")) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Gray
    Push-Location agent
    python -m venv venv
    & "venv/Scripts/Activate.ps1"
    pip install -r requirements.txt
    Pop-Location
} else {
    Write-Host "Virtual environment already exists" -ForegroundColor Gray
}

# Install frontend dependencies if needed
Write-Host "📦 Installing frontend dependencies..." -ForegroundColor Yellow
Push-Location frontend
if (-not (Test-Path "node_modules")) {
    npm install
}
Pop-Location

# Create local environment file for frontend
Write-Host "⚙️  Setting up local environment..." -ForegroundColor Yellow
@"
VITE_LOCAL_DEV=true
VITE_AGENT_RUNTIME_URL=/api
"@ | Out-File -FilePath "frontend/.env.local" -Encoding UTF8

Write-Host ""
Write-Host "🎯 Starting services..." -ForegroundColor Green
Write-Host "Backend will be available at: http://localhost:8080" -ForegroundColor Cyan
Write-Host "Frontend will be available at: http://localhost:5173" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop all services" -ForegroundColor Yellow
Write-Host ""

# Start AgentCore backend in background
Write-Host "🔧 Starting AgentCore backend..." -ForegroundColor Blue

# Check if AWS credentials are available
$callerIdentity = aws sts get-caller-identity 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  AWS credentials not found. The agent needs AWS credentials to call Bedrock." -ForegroundColor Yellow
    Write-Host "Please configure AWS credentials using one of these methods:" -ForegroundColor Yellow
    Write-Host "  1. aws configure" -ForegroundColor Cyan
    Write-Host "  2. aws sso login --profile <profile-name>" -ForegroundColor Cyan
    Write-Host "  3. Set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press Enter to continue anyway, or Ctrl+C to exit and configure credentials first..." -ForegroundColor Yellow
    Read-Host
}

Push-Location agent
& "venv/Scripts/Activate.ps1"
$backendJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD/agent
    & "venv/Scripts/Activate.ps1"
    python strands_agent.py
}
Pop-Location

# Wait a moment for backend to start
Start-Sleep -Seconds 3

# Start frontend dev server in background
Write-Host "🎨 Starting frontend dev server..." -ForegroundColor Magenta
Push-Location frontend
$frontendJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD/frontend
    npm run dev
}
Pop-Location

# Function to cleanup
function Cleanup {
    Write-Host ""
    Write-Host "🛑 Stopping services..." -ForegroundColor Red
    Stop-Job $backendJob, $frontendJob -ErrorAction SilentlyContinue
    Remove-Job $backendJob, $frontendJob -ErrorAction SilentlyContinue
}

# Register cleanup on Ctrl+C
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

try {
    # Wait for jobs and show output
    while ($backendJob.State -eq "Running" -or $frontendJob.State -eq "Running") {
        Receive-Job $backendJob -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Green
        Receive-Job $frontendJob -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Blue
        Start-Sleep -Seconds 1
    }
} finally {
    Cleanup
}