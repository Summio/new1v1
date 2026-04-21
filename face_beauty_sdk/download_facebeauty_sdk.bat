@echo off
chcp 65001 >nul
echo ========================================
echo FaceBeauty SDK 下载脚本
echo ========================================
echo.

set SDK_DIR=D:\1v1\new1v1\face_beauty_sdk

echo [1/4] 下载 Android SDK (FaceBeauty.aar)...
curl -L -o "%SDK_DIR%\FaceBeautySDK_Android\libs\FaceBeauty.aar" ^
  "https://github.com/FaceBeauty/FaceBeautySDK_Android/raw/main/libs/FaceBeauty.aar"
if %ERRORLEVEL%==0 (
  echo     OK: FaceBeauty.aar 下载成功
) else (
  echo     FAIL: FaceBeauty.aar 下载失败
)

echo.
echo [2/4] 克隆 FaceBeautySDK_iOS 仓库 (获取 Framework + Bundle)...
if not exist "%SDK_DIR%\FaceBeautySDK_iOS" (
  git clone --depth 1 https://github.com/FaceBeauty/FaceBeautySDK_iOS.git "%SDK_DIR%\FaceBeautySDK_iOS"
  if %ERRORLEVEL%==0 (
    echo     OK: FaceBeautySDK_iOS 克隆成功
  ) else (
    echo     FAIL: FaceBeautySDK_iOS 克隆失败
  )
) else (
  echo     SKIP: FaceBeautySDK_iOS 已存在
)

echo.
echo [3/4] 克隆 FBLiveFlutter (标准 Flutter 插件)...
if not exist "%SDK_DIR%\FBLiveFlutter" (
  git clone --depth 1 https://github.com/FaceBeauty/FBLiveFlutter.git "%SDK_DIR%\FBLiveFlutter"
  if %ERRORLEVEL%==0 (
    echo     OK: FBLiveFlutter 克隆成功
  ) else (
    echo     FAIL: FBLiveFlutter 克隆失败
  )
) else (
  echo     SKIP: FBLiveFlutter 已存在
)

echo.
echo [4/4] 克隆 FBAgoraLiveFlutter (Agora 集成版 Flutter 插件)...
if not exist "%SDK_DIR%\FBAgoraLiveFlutter" (
  git clone --depth 1 https://github.com/FaceBeauty/FBAgoraLiveFlutter.git "%SDK_DIR%\FBAgoraLiveFlutter"
  if %ERRORLEVEL%==0 (
    echo     OK: FBAgoraLiveFlutter 克隆成功
  ) else (
    echo     FAIL: FBAgoraLiveFlutter 克隆失败
  )
) else (
  echo     SKIP: FBAgoraLiveFlutter 已存在
)

echo.
echo ========================================
echo 下载完成！
echo.
echo 下载目录: %SDK_DIR%
echo.
echo 目录结构:
tree /F "%SDK_DIR%" 2>nul
echo ========================================
pause
