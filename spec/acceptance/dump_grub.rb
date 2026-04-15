

file_list = %w[ /etc/default/grub ]

d="/etc/grub.d"
Dir.open(d).each do |filename|
  puts filename
  file_list << "#{d}/#{filename}"
end

file_list.each do |name|
  puts "#### #{name} ####"
  puts File.read("#{name}") if File.file?(name)
end



