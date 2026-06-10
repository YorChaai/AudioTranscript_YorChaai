# FFmpeg Auto Installer
# Run as Administrator

Write-Host "Downloading FFmpeg..." -ForegroundColor Cyan
$url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$output = "C:\temp\ffmpeg.zip"
$extractPath = "C:\ffmpeg"

# Create temp folder
if (!(Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" | Out-Null
}

# Download
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
Write-Host "Download complete!" -ForegroundColor Green

# Extract
Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $output -DestinationPath $extractPath -Force

# Find ffmpeg.exe in extracted folder
$ffmpegFolder = Get-ChildItem -Path "$extractPath" -Directory | Where-Object {$_.Name -like "ffmpeg-*"} | Select-Object -First 1
if ($ffmpegFolder) {
    $binPath = Join-Path $ffmpegFolder.FullName "bin"

    # Add to PATH
    Write-Host "Adding to PATH..." -ForegroundColor Cyan
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*$binPath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "Machine")
        Write-Host "FFmpeg added to PATH!" -ForegroundColor Green
    }

    Write-Host "`nInstallation complete!" -ForegroundColor Green
    Write-Host "Restart your terminal and run: ffmpeg -version" -ForegroundColor Yellow
} else {
    Write-Host "Error: Could not find FFmpeg folder" -ForegroundColor Red
}

# Cleanup
Remove-Item $output -Force

Write-Host "`nDone!" -ForegroundColor Green
