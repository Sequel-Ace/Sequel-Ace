source 'https://cdn.cocoapods.org/'
# Uncomment the next line to define a global platform for your project
platform :osx, '10.12'

# target 'PSMTabBar' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for PSMTabBar

# end

# had to add this as ShortcutRecorder also creates Assets.car
install! 'cocoapods', :disable_input_output_paths => true

target 'Sequel Ace' do
  # Comment the next line if you don't want to use dynamic frameworks
  # use_frameworks!

  # Pods for Sequel Ace
  pod 'SwiftLint', '~> 0.40'
  pod 'FirebaseCore'
  pod 'Firebase/Crashlytics'
  pod 'ShortcutRecorder', '~> 3.3.0'
end

# target 'Sequel Ace QLGenerator' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for Sequel Ace QLGenerator

# end

# target 'SequelAceTunnelAssistant' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for SequelAceTunnelAssistant

# end

# target 'xibLocalizationPostprocessor' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for xibLocalizationPostprocessor

# end

# ** Import/update licences **
#
# Firebase etc Apache License 2.0 (and some others) so we need include License and copyright notices
# What I wanted to do here was to take our current Licence.rtf and re-create it in Markdown: License.md
# The reason for the new file is that we want it at the top of Licence.rtf and you can't use pandoc to concat rtf + md -> rtf.
# Strangely, you can oncat  md + rtf -> rtf. Anyway, we do md + md -> rtf
# Then, I created an empty Pods-Sequel Ace-acknowledgements.markdown for state changes
# On pod install, this code checks to see if the licenses have changed, if they have, copy to Pods-Sequel Ace-acknowledgements.markdown
# Then I use pandoc (https://pandoc.org/index.html) to concatenate License.md + Pods-Sequel Ace-acknowledgements.markdown
# and output to License.rtf

post_install do |installer_representation|

  installer_representation.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # let Xcode decide what archs are built
      # this is an Xcode settings recommendation
      config.build_settings.delete('ARCHS')
      if config.name == "Release" or config.name == "Distribution"
        # Build all archs
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
      else
        # Only build active arch
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
      end

      # ShortcutRecorder sets a weird PRODUCT_BUNDLE_IDENTIFIER
      # change to ours
      if target.name == "ShortcutRecorder"
        xcconfig_path = config.base_configuration_reference.real_path
        xcconfig = File.read(xcconfig_path)
        xcconfig_mod = xcconfig.gsub(/com.kulakov.ShortcutRecorder/, "com.sequel-ace.sequel-ace")
        File.open(xcconfig_path, "w") { |file| file << xcconfig_mod }
        config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.sequel-ace.sequel-ace'
      end
      
      # just in case pods messes this up
      # set symbols correctly
      if config.name == "Debug"
        config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf'
      else
        config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
      end
    end
  end

    
  require 'fileutils'
  
  unless FileUtils.identical?("Pods/Target Support Files/Pods-Sequel Ace/Pods-Sequel Ace-acknowledgements.markdown", "Resources/Pods-Sequel Ace-acknowledgements.markdown")
    puts "not identical"
    FileUtils.cp_r("Pods/Target Support Files/Pods-Sequel Ace/Pods-Sequel Ace-acknowledgements.markdown", "Resources/Pods-Sequel Ace-acknowledgements.markdown", :remove_destination => true)
    
    if system("hash pandoc 2> /dev/null")
      puts "pandoc installed"
      if system("pandoc -s 'Resources/License.md' 'Resources/Pods-Sequel Ace-acknowledgements.markdown' -o 'Resources/License.rtf' 2> /dev/null")
        puts "new license file generated"
      else
        puts "pandoc error, check license.rtf"
      end
    else
      puts "pandoc not installed. Try brew install pandoc"
    end
  end

  # a minimal ruby version of sed (doesn't work with regexes)
  def justLikeSed(file, text_to_replace, text_to_put_in_place)
      text = File.read(file)
      File.open(file, 'w+'){|f| f << text.gsub(text_to_replace, text_to_put_in_place)}
  end

  # remove CoreTelephony from the build configs, it's an iOS-only requirement
  # see: https://github.com/firebase/firebase-ios-sdk/blob/bde8e07844577ecc44799b82c88273ca96a93f2a/GoogleDataTransport/GDTCORLibrary/Internal/GDTCORPlatform.h#L31-L33
  Dir.glob('**/Pods*.xcconfig') do |filename|
    puts "Removing CoreTelephony from: " + filename
    justLikeSed(filename , '-framework "CoreTelephony" ' , '')
  end

  # ShortcutRecorder sets a weird PRODUCT_BUNDLE_IDENTIFIER
  # change to ours
  SRCommonFileName='Pods/ShortcutRecorder/Sources/ShortcutRecorder/SRCommon.m'

  puts "chmod +w: Pods/ShortcutRecorder/Sources/ShortcutRecorder/SRCommon.m"

  if system("chmod +w Pods/ShortcutRecorder/Sources/ShortcutRecorder/SRCommon.m")
    puts "chmod success"
  else
    puts "chmod failed"
  end

  puts "Replacing 'com.kulakov.ShortcutRecorder' with 'com.sequel-ace.sequel-ace'"

  justLikeSed(SRCommonFileName, 'com.kulakov.ShortcutRecorder', 'com.sequel-ace.sequel-ace')

  # ShortcutRecorder has loads of resources that we don't need
  # remove them
  puts "Removing uneeded resources"

  resourcesShellFileName='Pods/Target Support Files/Pods-Sequel Ace/Pods-Sequel Ace-resources.sh'

  justLikeSed(resourcesShellFileName, 'install_resource "${PODS_ROOT}/ShortcutRecorder/ATTRIBUTION.md"', '')
  justLikeSed(resourcesShellFileName, 'install_resource "${PODS_ROOT}/ShortcutRecorder/LICENSE.txt"', '')

  arr = ['ca', 'cs', 'de', 'el', 'es', 'fr', 'it', 'ja', 'ko', 'nb', 'nl', 'pl', 'pt-BR', 'pt', 'ro', 'ru', 'sk', 'sv', 'th', 'zh-Hans', 'zh-Hant']

  arr.each do |lang|
    search = 'install_resource "${PODS_ROOT}/ShortcutRecorder/Sources/ShortcutRecorder/Resources/' + lang + '.lproj"'
    justLikeSed(resourcesShellFileName, search, '')
  end

  # ShortcutRecorder sets default font to 13
  # we want 11, so change it here
  # There must be a way to do this in code, but
  # I haven't figured it out yet
  srMojaveInfoFile='Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-mojave-info.dataset/info.json'

  puts "chmod +w: Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-mojave-info.dataset/info.json"

  if system("chmod +w Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-mojave-info.dataset/info.json")
    puts "chmod success"
  else
    puts "chmod failed"
  end

  puts "Replacing '13.0' with '11.0'"

  justLikeSed(srMojaveInfoFile, '13.0', '11.0')

  srYosemiteInfoFile='Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-yosemite-info.dataset/info.json'

  puts "chmod +w: Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-yosemite-info.dataset/info.json"

  if system("chmod +w Pods/ShortcutRecorder/Sources/ShortcutRecorder/Resources/Images.xcassets/sr-yosemite-info.dataset/info.json")
    puts "chmod success"
  else
    puts "chmod failed"
  end

  puts "Replacing '13.0' with '11.0'"

  justLikeSed(srYosemiteInfoFile, '13.0', '11.0')

end

