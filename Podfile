source 'https://cdn.cocoapods.org/'
# Uncomment the next line to define a global platform for your project
platform :osx, '10.12'

# target 'PSMTabBar' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for PSMTabBar

# end

# inhibit warning on > 1.9.3
if Gem::Version.new(Pod::VERSION) > Gem::Version.new('1.9.3')
  install! 'cocoapods', :warn_for_unused_master_specs_repo => false
end



target 'Sequel Ace' do
  # Comment the next line if you don't want to use dynamic frameworks
  # use_frameworks!

  # Pods for Sequel Ace
  pod 'FirebaseCore'
  pod 'Firebase/Crashlytics'

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

end
