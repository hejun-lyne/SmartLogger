Pod::Spec.new do |spec|
  spec.name         = 'smartlogger'
  spec.version      = '1.0.0'
  spec.license      = { :type => 'BSD' }
  spec.authors      = { 'Li Hejun' => 'lihejun@yy.com' }
  spec.summary      = 'Log services'
  spec.homepage     = 'https://github.com/hejun-lyne'
  spec.source       = { :git => 'https://github.com/hejun-lyne/SmartLogger.git' }

  spec.ios.deployment_target = '9.0'
  spec.static_framework = true
  spec.default_subspec = 'All'
  spec.public_header_files = 'SmartLogger/SLInterfaces.h'
  spec.public_header_files = 'SmartLogger/SLLogger.h'

  spec.subspec 'All' do |ss|
    ss.dependency 'smartlogger/Core'
    ss.dependency 'smartlogger/fishhook'
    ss.dependency 'smartlogger/Function'
  end

  spec.subspec 'Core' do |ss|
    ss.source_files = 'SmartLogger/Core/**/*.{h,m}', 'SmartLogger/SLInterfaces.h'
  end

  spec.subspec 'fishhook' do |ss|
    ss.source_files = "SmartLogger/fishhook/fishhook.{h,c}"
  end

  spec.subspec 'Function' do |ss|
    ss.dependency 'smartlogger/Core'
    ss.dependency 'smartlogger/fishhook'
    ss.public_header_files = 'SmartLogger/Function/SLFunctionsWatcher.h'
    ss.source_files = 'SmartLogger/Function/*.{h,m,mm}'
  end

end
