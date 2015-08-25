Facter.add(:augeasprovider_grub_version) do
  if File.exists?('/etc/default/grub')
    version = 2
  elsif File.exists?('/boot/efi/EFI/redhat/grub.conf') || File.exists?('/boot/grub/menu.lst')
    version = 1
  else
    fail('Failed to evaluate grub version')
  end

  setcode { version }
end
