Pod::Spec.new do |s|
  s.name         = "cpp-log"
  s.version      = "0.0.2"
  s.summary      = "cpp-log"
  s.description  = <<-DESC
  cpp-log 0.0.1
  DESC
  s.author       = { "shadow magic" => "shadowmagic@yeah.net" }
  s.homepage     = 'https://www.wikipedia.org'
  s.source       = { :git => "https://github.com/shijiancheng/cpp-log.git", :tag => s.version.to_s }
  s.source_files = 'Classes/**/*.{h,m}'
  s.platform     = :ios, '8.0'
  s.requires_arc = true
  s.vendored_frameworks = 'mars.framework'
  s.libraries = 'z'
  s.frameworks = 'Foundation', 'CoreTelephony', 'SystemConfiguration'
end
