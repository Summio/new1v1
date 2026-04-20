#
# FaceBeauty 美颜 SDK Flutter 插件
#
Pod::Spec.new do |s|
  s.name             = 'mt_plugin'
  s.version          = '0.0.1'
  s.summary          = 'FaceBeauty 美颜 SDK Flutter 插件'
  s.description      = 'FaceBeauty 美颜 SDK 的 Flutter 插件，支持美颜、美型、滤镜等功能'
  s.homepage         = 'https://github.com/FaceBeauty/FBLiveFlutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FaceBeauty' => 'dev@facebeauty.com' }
  s.source           = { :path => '.' }
  s.static_framework = true
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # FaceBeauty SDK (本地 vendored)
  s.vendored_frameworks = 'Vendored/FaceBeauty.framework'
  s.resources = 'Vendored/FaceBeauty.bundle'

  # CocoaPods 依赖
  s.dependency 'Masonry'
  s.dependency 'ZipArchive'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
