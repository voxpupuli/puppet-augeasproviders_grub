Facter.add(:augeasprovider_grub_blscfg) do
  enabled = nil
  if File.exist?('/etc/default/grub')
    if File.foreach('/etc/default/grub').grep(/GRUB_ENABLE_BLSCFG=/) do |line|
      nospace = line.strip
      next if nospace.start_with?('#')
      nocomments = nospace[/[^#]+/].strip
      value = nocomments.split('=', 2).last
      enabled = if value.to_s.casecmp('true').zero?
                  true
                else
                  false
                end
      end
    end
  end

  setcode { enabled }
end
