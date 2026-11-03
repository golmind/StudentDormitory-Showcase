@echo off
chcp 936 >nul 2>&1
cd /d "%~dp0"
echo ==========================================
echo   生成作品集 DOCX（可直接用 Word 修改）
echo ==========================================
echo.
echo 读 portfolio-content.json + captions.json + 截图\，
echo 用本机 Word/WPS 生成 作品集.docx。
echo.
echo 想改姓名/联系方式：
echo   方式一  直接改 portfolio-content.json 里的 meta
echo   方式二  在命令行传参数（见下方说明）
echo.
echo 改了截图或文案后，重新双击本文件即可重新生成。
echo ==========================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-portfolio-docx.ps1" %*
echo.
pause
