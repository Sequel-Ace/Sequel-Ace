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

post_install do |installer_representation|

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
