source 'https://github.com/CocoaPods/Specs.git'
# Uncomment the next line to define a global platform for your project
platform :osx, '10.12'

# target 'PSMTabBar' do
#   # Comment the next line if you don't want to use dynamic frameworks
#   use_frameworks!

#   # Pods for PSMTabBar

# end

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
      # let Xcode decide what arch are built
      # this is an Xcode settings recommendation
      config.build_settings.delete('ARCHS')
      if config.name == "Release"
        # Build all archs
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
      else
        # Only build active arch
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
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
  
#  can't get this to work right now...
#  system("for file in *.xcconfig; do sed -i ''  's/-framework "CoreTelephony" //g'; done")
  
end
