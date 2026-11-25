Pod::Spec.new do |s|
  s.name = 'BsiNativeInference'
  s.version = '1.0.0'
  s.summary = 'FP32 inference bridge for the BSI app.'
  s.homepage = 'https://github.com/th00tames1/BSIApp'
  s.author = 'BSIApp contributors'
  s.license = { :type => 'Proprietary' }
  s.ios.deployment_target = '16.0'
  s.source = { :path => '.' }
  s.source_files = 'ncnn_bridge.cpp'
  s.static_framework = true
  s.libraries = 'c++'
  s.dependency 'BsiAppleNCNN', '= 2026.10.20'
  s.dependency 'BsiAppleMoltenVK', '= 1.4.2'
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17' }
  # The FFI functions are looked up by name, and ncnn's MoltenVK import is weak.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-export_dynamic -Wl,-u,_bsi_ncnn_open -Wl,-u,_bsi_ncnn_run -Wl,-u,_bsi_ncnn_close -Wl,-u,_vkGetInstanceProcAddr'
  }
end