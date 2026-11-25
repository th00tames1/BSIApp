Pod::Spec.new do |s|
  s.name = 'BsiAppleNCNN'
  s.version = '2026.10.20'
  s.summary = 'Pinned ncnn Vulkan SDK for the BSI iOS app.'
  s.homepage = 'https://github.com/Tencent/ncnn'
  s.author = 'Tencent ncnn contributors'
  s.license = { :type => 'BSD-3-Clause' }
  s.ios.deployment_target = '16.0'
  s.source = {
    :http => 'https://github.com/Tencent/ncnn/releases/download/20261020/ncnn-20261020-apple-vulkan.zip',
    :sha256 => '90a0d963d352404942b92e079b830031e688bdf0f8065f61ca3502e75e9d0392'
  }
  s.vendored_frameworks = %w[ncnn.xcframework glslang.xcframework openmp.xcframework]
end