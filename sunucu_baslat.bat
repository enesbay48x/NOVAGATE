@echo off
chcp 65001 >nul
REM ============================================================
REM  NOVAGATE SUNUCUSU  -  kendi bilgisayarinda calistir
REM  1) Godot 4.7.2 CONSOLE exe yolu asagida otomatik denenir
REM     (ilk bulunan kullanilir; kendi yolunuz farkliysa GODOT
REM      satirinin onundeki yolu degistirin)
REM  2) Bu dosyayi project.godot'un oldugu klasore koy, cift tikla
REM ============================================================
set PORT=7777

REM -- Gercek Godot 4.7.2 executable yolu (bu bilgisayarda dogrulandi) --
set "GODOT=C:\Users\Pc\Desktop\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT%" set "GODOT=C:\Users\Pc\AppData\Local\Temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo [HATA] Godot consol exe bulunamadi.
    echo Asagidaki yolu kendi Godot 4.7.2 consol exe yolunuzla duzenleyin:
    echo    set GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe
    pause
    exit /b 1
)

pushd "%~dp0"
echo [NOVAGATE] Godot: %GODOT%
echo [NOVAGATE] Proje: %CD%  -  UDP port %PORT%
"%GODOT%" --headless --path . -- --server --port=%PORT%
popd
pause
