Pod::Spec.new do |s|
  s.name         = "cpp-log"
  s.version      = "0.0.1"
  s.summary      = "cpp-log"
  s.source       = { :git => "https://github.com/shijiancheng/cpp-log.git", :tag => s.version.to_s }
  s.platform     = :ios, '8.0'
  s.requires_arc = true
  s.preserve_paths      = 'cpp-log.framework'
  s.public_header_files = "cpp-log.framework/Headers/**/*{.h,.hpp}"
  s.vendored_frameworks = 'cpp-log.framework'
  s.libraries = 'z'
  s.frameworks = 'Foundation', 'CoreTelephony', 'SystemConfiguration'
end
