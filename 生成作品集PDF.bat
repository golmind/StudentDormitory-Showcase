@echo off
chcp 936 >nul 2>&1
cd /d "%~dp0"
echo ==========================================
echo   生成作品集 PDF
echo ==========================================
echo.
echo 会读取 截图\ 目录下的所有 png，生成 作品集.pdf
echo.
echo 想填姓名/联系方式：用记事本打开本文件改下面两行即可
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-portfolio-pdf.ps1" -Name "（你的姓名）" -Contact "（手机 / 邮箱）"
echo.
pause
