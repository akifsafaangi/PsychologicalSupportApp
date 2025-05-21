@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

cd backend

echo [INFO] Port 5002 kapatılıyor (varsa)...
FOR /F "tokens=5" %%A IN ('netstat -aon ^| find ":5002" ^| find "LISTENING"') DO (
    taskkill /F /PID %%A >nul 2>&1
)

echo [INFO] Gereken Python paketleri yükleniyor...
pip install -r requirements.txt >nul 2>&1

echo [INFO] Flask sunucusu (transcribe + analyze) başlatılıyor...
start "FLASK_BACKEND" cmd /k "call venv\Scripts\activate.bat && python app.py"

timeout /t 3 >nul

echo [INFO] Ngrok başlatılıyor (port 5002)...
start "NGROK_TUNNEL" cmd /k "ngrok http 5002 --domain=drum-resolved-earwig.ngrok-free.app"

cd ..

echo.
echo [OK] Tüm servisler başarıyla başlatıldı. Ngrok terminalinden URL'yi kopyalayabilirsiniz.
pause
