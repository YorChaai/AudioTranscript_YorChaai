$ErrorActionPreference = "Stop"
$url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$exe = "cloudflared.exe"

Write-Host "[*] Menyiapkan Cloudflare Tunnel..." -ForegroundColor Cyan

if (-not (Test-Path $exe)) {
    Write-Host "[+] Downloading cloudflared.exe..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $exe
    Write-Host "[OK] Download selesai." -ForegroundColor Green
}
else {
    Write-Host "[OK] cloudflared.exe sudah ada." -ForegroundColor Green
}

Write-Host ""
Write-Host "[*] Menjalankan Tunnel ke http://localhost:5000..." -ForegroundColor Cyan
Write-Host "[!] JANGAN TUTUP JENDELA INI!" -ForegroundColor Red
Write-Host "[i] Copy URL 'https://....trycloudflare.com' dan paste di Settings App." -ForegroundColor Yellow
Write-Host "---------------------------------------------------"

& ".\cloudflared.exe" tunnel --url http://localhost:5000
