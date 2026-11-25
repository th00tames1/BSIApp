Pod::Spec.new do |s|
  s.name = 'BsiAppleMoltenVK'
  s.version = '1.4.2'
  s.summary = 'Pinned Vulkan-to-Metal runtime for the BSI iOS app.'
  s.homepage = 'https://github.com/KhronosGroup/MoltenVK'
  s.author = 'The Khronos Group'
  s.license = { :type => 'Apache-2.0', :file => 'MoltenVK/LICENSE' }
  s.ios.deployment_target = '16.0'
  s.source = {
    :http => 'https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-all.tar',
    :sha256 => '562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276',
    :flatten => false
  }
  s.vendored_frameworks = 'MoltenVK/MoltenVK/static/MoltenVK.xcframework'
  s.frameworks = %w[Metal MetalKit QuartzCore CoreGraphics IOSurface Foundation]
end